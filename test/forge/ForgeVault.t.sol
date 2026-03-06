// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

contract ForgeVaultTest is Test {
    // --- Actors ---
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice"); // Senior investor
    address bob = makeAddr("bob"); // Mezzanine investor
    address carol = makeAddr("carol"); // Equity investor
    address dave = makeAddr("dave"); // Additional investor

    // --- Contracts ---
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource underlying;
    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    // --- Constants ---
    uint256 constant POOL_SIZE = 1_000_000e18;
    uint256 constant SENIOR_SIZE = 700_000e18; // 70%
    uint256 constant MEZZ_SIZE = 200_000e18; // 20%
    uint256 constant EQUITY_SIZE = 100_000e18; // 10%
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;

    function setUp() public {
        // Deploy underlying asset
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);

        // Deploy factory
        factory = new ForgeFactory(treasury, protocolAdmin, 0);

        // We need to deploy vault first to get address for TrancheToken constructor,
        // but vault needs token addresses. Use CREATE2 or deploy tokens with placeholder,
        // then deploy vault, then update tokens.
        //
        // Simpler approach: deploy vault via factory, then deploy tokens pointing to vault.
        // But ForgeVault constructor needs token addresses...
        //
        // Solution: pre-compute vault address or deploy in two steps.
        // For testing, deploy tokens with a temporary vault address, then redeploy.
        //
        // Actually, simplest: deploy tokens first pointing to address(this) as vault,
        // then deploy the real vault. Since tokens only check vault on mint/burn/transfer,
        // we can deploy them first if we know the vault address.
        //
        // Best approach: use vm.computeCreateAddress to predict vault address.

        // Predict the vault address (next contract deployed by factory)
        // Factory uses `new ForgeVault(...)` so address = CREATE from factory
        uint256 factoryNonce = vm.getNonce(address(factory));
        address predictedVault = vm.computeCreateAddress(address(factory), factoryNonce);

        // Deploy tranche tokens pointing to predicted vault address
        seniorToken = new TrancheToken("Senior Tranche", "SR-T", predictedVault, 0);
        mezzToken = new TrancheToken("Mezzanine Tranche", "MZ-T", predictedVault, 1);
        equityToken = new TrancheToken("Equity Tranche", "EQ-T", predictedVault, 2);

        // Create vault via factory
        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)});
        params[1] = IForgeVault.TrancheParams({targetApr: 800, allocationPct: 20, token: address(mezzToken)});
        params[2] = IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(equityToken)});

        vm.prank(originator);
        address vaultAddr = factory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(underlying),
                trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );

        vault = ForgeVault(vaultAddr);
        assertEq(vaultAddr, predictedVault, "Vault address prediction failed");

        // Fund investors
        underlying.mint(alice, SENIOR_SIZE);
        underlying.mint(bob, MEZZ_SIZE);
        underlying.mint(carol, EQUITY_SIZE);

        // Approve vault to spend
        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(carol);
        underlying.approve(address(vault), type(uint256).max);
    }

    // ===== SETUP VALIDATION =====

    function test_setUp_vaultDeployed() public view {
        assertEq(vault.originator(), originator);
        assertEq(address(vault.underlyingAsset()), address(underlying));
        assertEq(uint256(vault.poolStatus()), uint256(IForgeVault.PoolStatus.Active));
    }

    function test_setUp_factoryTracksVault() public view {
        assertEq(factory.vaultCount(), 1);
        assertEq(factory.getVault(0), address(vault));

        uint256[] memory originatorVaults = factory.getOriginatorVaults(originator);
        assertEq(originatorVaults.length, 1);
        assertEq(originatorVaults[0], 0);
    }

    function test_setUp_trancheTokensCorrect() public view {
        assertEq(seniorToken.vault(), address(vault));
        assertEq(seniorToken.trancheId(), 0);
        assertEq(mezzToken.vault(), address(vault));
        assertEq(mezzToken.trancheId(), 1);
        assertEq(equityToken.vault(), address(vault));
        assertEq(equityToken.trancheId(), 2);
    }

    // ===== INVEST TESTS =====

    function test_invest_senior() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);

        assertEq(seniorToken.balanceOf(alice), SENIOR_SIZE, "Alice should hold senior tokens");
        assertEq(vault.getShares(alice, 0), SENIOR_SIZE, "Plaintext mirror should match");
        assertEq(vault.totalShares(0), SENIOR_SIZE);
        assertEq(vault.totalPoolDeposited(), SENIOR_SIZE);
        assertEq(underlying.balanceOf(address(vault)), SENIOR_SIZE, "Vault holds underlying");
    }

    function test_invest_allTranches() public {
        _investAll();

        assertEq(vault.totalPoolDeposited(), POOL_SIZE);
        assertEq(vault.totalShares(0), SENIOR_SIZE);
        assertEq(vault.totalShares(1), MEZZ_SIZE);
        assertEq(vault.totalShares(2), EQUITY_SIZE);
        assertEq(underlying.balanceOf(address(vault)), POOL_SIZE);
    }

    function test_invest_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("ForgeVault: zero amount");
        vault.invest(0, 0);
    }

    function test_invest_revert_invalidTranche() public {
        vm.prank(alice);
        vm.expectRevert("ForgeVault: invalid tranche");
        vault.invest(3, 1000e18);
    }

    function test_invest_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IForgeVault.Invested(alice, 0, SENIOR_SIZE);
        vault.invest(0, SENIOR_SIZE);
    }

    // ===== WATERFALL DISTRIBUTION TESTS =====

    function test_waterfall_basicDistribution() public {
        _investAll();

        // Simulate yield: 100k arrives after 1 year
        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + YEAR);

        vault.triggerWaterfall();

        // Senior: 700k * 5% = 35k
        // Mezz: 200k * 8% = 16k
        // Equity: remainder = 49k
        uint256 aliceClaimable = vault.getClaimableYield(alice, 0);
        uint256 bobClaimable = vault.getClaimableYield(bob, 1);
        uint256 carolClaimable = vault.getClaimableYield(carol, 2);

        assertApproxEqRel(aliceClaimable, 35_000e18, 1e15, "Senior yield ~35k");
        assertApproxEqRel(bobClaimable, 16_000e18, 1e15, "Mezz yield ~16k");
        assertApproxEqRel(carolClaimable, 49_000e18, 1e15, "Equity yield ~49k");
    }

    function test_waterfall_scarceYield_seniorPriority() public {
        _investAll();

        // Only 20k yield — not enough for full senior coupon (35k)
        underlying.mint(address(vault), 20_000e18);
        vm.warp(block.timestamp + YEAR);

        vault.triggerWaterfall();

        uint256 aliceClaimable = vault.getClaimableYield(alice, 0);
        uint256 bobClaimable = vault.getClaimableYield(bob, 1);
        uint256 carolClaimable = vault.getClaimableYield(carol, 2);

        assertApproxEqRel(aliceClaimable, 20_000e18, 1e15, "Senior gets all scarce yield");
        assertEq(bobClaimable, 0, "Mezz gets nothing");
        assertEq(carolClaimable, 0, "Equity gets nothing");
    }

    function test_waterfall_revert_tooSoon() public {
        _investAll();
        underlying.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + 1 days); // less than 1 week

        vm.expectRevert("ForgeVault: too soon");
        vault.triggerWaterfall();
    }

    function test_waterfall_noYield() public {
        _investAll();
        vm.warp(block.timestamp + YEAR);

        // No extra yield — waterfall should be a no-op
        vault.triggerWaterfall();

        assertEq(vault.getClaimableYield(alice, 0), 0);
        assertEq(vault.getClaimableYield(bob, 1), 0);
        assertEq(vault.getClaimableYield(carol, 2), 0);
    }

    // ===== CLAIM YIELD TESTS =====

    function test_claimYield_success() public {
        _investAll();

        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        uint256 aliceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = vault.claimYield(0);

        assertApproxEqRel(claimed, 35_000e18, 1e15, "Alice claims ~35k");
        assertEq(underlying.balanceOf(alice), aliceBefore + claimed);

        // Claiming again should return 0
        vm.prank(alice);
        uint256 secondClaim = vault.claimYield(0);
        assertEq(secondClaim, 0, "Double claim should return 0");
    }

    function test_claimYield_multipleDistributions() public {
        _investAll();

        // Week 1
        underlying.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();

        // Week 2
        underlying.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();

        // Claim after 2 weeks
        vm.prank(alice);
        uint256 claimed = vault.claimYield(0);
        assertGt(claimed, 0, "Should have accumulated yield from both weeks");
    }

    // ===== WITHDRAW TESTS =====

    function test_withdraw_full() public {
        _investAll();

        uint256 aliceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(0, SENIOR_SIZE);

        assertEq(seniorToken.balanceOf(alice), 0, "Tokens burned");
        assertEq(vault.getShares(alice, 0), 0, "Mirror cleared");
        assertEq(vault.totalShares(0), 0, "Total shares reduced");
        assertEq(underlying.balanceOf(alice), aliceBefore + SENIOR_SIZE, "Got underlying back");
    }

    function test_withdraw_partial() public {
        _investAll();
        uint256 half = SENIOR_SIZE / 2;

        vm.prank(alice);
        vault.withdraw(0, half);

        assertEq(seniorToken.balanceOf(alice), SENIOR_SIZE - half);
        assertEq(vault.getShares(alice, 0), SENIOR_SIZE - half);
    }

    function test_withdraw_revert_insufficientShares() public {
        _investAll();

        vm.prank(alice);
        vm.expectRevert("ForgeVault: insufficient shares");
        vault.withdraw(0, SENIOR_SIZE + 1);
    }

    function test_withdraw_settlesYieldFirst() public {
        _investAll();

        // Generate yield
        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        // Withdraw should settle yield first
        vm.prank(alice);
        vault.withdraw(0, SENIOR_SIZE);

        // Alice should still be able to claim the yield from before withdrawal
        vm.prank(alice);
        uint256 claimed = vault.claimYield(0);
        assertApproxEqRel(claimed, 35_000e18, 1e15, "Yield settled before withdrawal");
    }

    // ===== TRANSFER HOOK TESTS =====

    function test_transferHook_syncsPlaintextMirror() public {
        _investAll();

        // Alice transfers half her senior tokens to Dave
        uint256 transferAmount = SENIOR_SIZE / 2;
        vm.prank(alice);
        seniorToken.transfer(dave, transferAmount);

        // Check plaintext mirrors are updated
        assertEq(vault.getShares(alice, 0), SENIOR_SIZE - transferAmount, "Alice mirror reduced");
        assertEq(vault.getShares(dave, 0), transferAmount, "Dave mirror increased");
    }

    function test_transferHook_settlesYieldForBothParties() public {
        _investAll();

        // Generate yield
        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        // Alice transfers to Dave — both should have yield settled
        uint256 transferAmount = SENIOR_SIZE / 2;
        vm.prank(alice);
        seniorToken.transfer(dave, transferAmount);

        // Alice's claimable yield should be her full share (she held 100% during distribution)
        uint256 aliceClaimable = vault.getClaimableYield(alice, 0);
        assertApproxEqRel(aliceClaimable, 35_000e18, 1e15, "Alice yield settled at transfer time");

        // Dave had no shares during distribution, so 0 yield
        uint256 daveClaimable = vault.getClaimableYield(dave, 0);
        assertEq(daveClaimable, 0, "Dave has no yield yet");
    }

    function test_transferHook_newRecipientEarnsYieldAfterTransfer() public {
        _investAll();

        // Transfer half to Dave
        vm.prank(alice);
        seniorToken.transfer(dave, SENIOR_SIZE / 2);

        // Now generate yield
        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        // Alice and Dave should split the senior yield
        uint256 aliceClaimable = vault.getClaimableYield(alice, 0);
        uint256 daveClaimable = vault.getClaimableYield(dave, 0);

        assertApproxEqRel(aliceClaimable, 17_500e18, 1e15, "Alice gets half of senior yield");
        assertApproxEqRel(daveClaimable, 17_500e18, 1e15, "Dave gets half of senior yield");
    }

    // ===== POOL STATUS TESTS =====

    function test_setPoolStatus_onlyOriginator() public {
        vm.prank(originator);
        vault.setPoolStatus(IForgeVault.PoolStatus.Impaired);
        assertEq(uint256(vault.poolStatus()), uint256(IForgeVault.PoolStatus.Impaired));
    }

    function test_setPoolStatus_revert_notOriginator() public {
        vm.prank(alice);
        vm.expectRevert("ForgeVault: not originator");
        vault.setPoolStatus(IForgeVault.PoolStatus.Impaired);
    }

    function test_invest_revert_poolNotActive() public {
        vm.prank(originator);
        vault.setPoolStatus(IForgeVault.PoolStatus.Defaulted);

        vm.prank(alice);
        vm.expectRevert("ForgeVault: pool not active");
        vault.invest(0, 1000e18);
    }

    // ===== FUZZ TESTS =====

    function testFuzz_invest_anyAmount(uint256 amount) public {
        amount = bound(amount, 1e18, 1e30);
        underlying.mint(alice, amount);
        vm.prank(alice);
        underlying.approve(address(vault), amount);

        vm.prank(alice);
        vault.invest(0, amount);

        assertEq(vault.getShares(alice, 0), amount);
        assertEq(seniorToken.balanceOf(alice), amount);
    }

    function testFuzz_waterfall_yieldSumsCorrectly(uint256 yield_) public {
        yield_ = bound(yield_, 1e18, 1e30);
        _investAll();

        underlying.mint(address(vault), yield_);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        uint256 totalClaimable = vault.getClaimableYield(alice, 0)
            + vault.getClaimableYield(bob, 1) + vault.getClaimableYield(carol, 2);

        // Total claimable should equal the yield distributed
        assertApproxEqRel(totalClaimable, yield_, 1e14, "Total claimable ~ total yield");
    }

    // ===== HELPERS =====

    function _investAll() internal {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);
    }
}
