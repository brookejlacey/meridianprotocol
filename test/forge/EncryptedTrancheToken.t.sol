// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EncryptedTrancheToken} from "../../src/forge/EncryptedTrancheToken.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ITrancheToken} from "../../src/interfaces/ITrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

// ===================================================================
//  Contract A: EncryptedTrancheToken Unit Tests
// ===================================================================

contract EncryptedTrancheTokenTest is Test {
    address vaultAddr = makeAddr("vault");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    EncryptedTrancheToken token;

    function setUp() public {
        token = new EncryptedTrancheToken("Senior Tranche", "SR-eT", vaultAddr, 0);
    }

    // --- Constructor tests ---

    function test_constructor_setsVaultAsOwner() public view {
        assertEq(token.owner(), vaultAddr);
        assertEq(token.vault(), vaultAddr);
    }

    function test_constructor_setsTrancheId() public {
        assertEq(token.trancheId(), 0);

        EncryptedTrancheToken mezz = new EncryptedTrancheToken("Mezz", "MZ", vaultAddr, 1);
        assertEq(mezz.trancheId(), 1);

        EncryptedTrancheToken equity = new EncryptedTrancheToken("Equity", "EQ", vaultAddr, 2);
        assertEq(equity.trancheId(), 2);
    }

    function test_constructor_setsTransferHookTarget() public view {
        assertEq(token.transferHookTarget(), vaultAddr);
    }

    function test_constructor_setsDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(token.name(), "Senior Tranche");
        assertEq(token.symbol(), "SR-eT");
    }

    function test_constructor_revert_invalidTrancheId() public {
        vm.expectRevert("EncryptedTrancheToken: invalid tranche id");
        new EncryptedTrancheToken("Bad", "BAD", vaultAddr, 3);
    }

    function test_constructor_revert_zeroVault() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new EncryptedTrancheToken("Bad", "BAD", address(0), 0);
    }

    // --- mint/burn access control ---

    function test_mint_onlyOwner() public {
        vm.prank(vaultAddr);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_mint_revert_notOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        token.mint(alice, 1000e18);
    }

    function test_burn_onlyOwner() public {
        vm.prank(vaultAddr);
        token.mint(alice, 1000e18);

        vm.prank(vaultAddr);
        token.burn(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    function test_burn_revert_notOwner() public {
        vm.prank(vaultAddr);
        token.mint(alice, 1000e18);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        token.burn(alice, 500e18);
    }

    // --- Transfer hook tests ---

    function test_transfer_emitsShareTransferHook() public {
        // Deploy a mock vault that accepts the hook
        MockHookReceiver receiver = new MockHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(receiver), 0);

        vm.prank(address(receiver));
        hookToken.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ITrancheToken.ShareTransferHook(alice, bob, 500e18);
        hookToken.transfer(bob, 500e18);
    }

    function test_transfer_callsVaultHook() public {
        MockHookReceiver receiver = new MockHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(receiver), 0);

        vm.prank(address(receiver));
        hookToken.mint(alice, 1000e18);

        vm.prank(alice);
        hookToken.transfer(bob, 500e18);

        // Verify the receiver got called
        assertEq(receiver.lastFrom(), alice);
        assertEq(receiver.lastTo(), bob);
        assertEq(receiver.lastAmount(), 500e18);
        assertEq(receiver.callCount(), 1);
    }

    function test_transferFrom_callsVaultHook() public {
        MockHookReceiver receiver = new MockHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(receiver), 0);

        vm.prank(address(receiver));
        hookToken.mint(alice, 1000e18);

        vm.prank(alice);
        hookToken.approve(bob, 500e18);

        vm.prank(bob);
        hookToken.transferFrom(alice, bob, 500e18);

        assertEq(receiver.lastFrom(), alice);
        assertEq(receiver.lastTo(), bob);
        assertEq(receiver.lastAmount(), 500e18);
    }

    function test_transfer_revert_hookFailure() public {
        RevertingHookReceiver reverter = new RevertingHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(reverter), 0);

        vm.prank(address(reverter));
        hookToken.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert("EncryptedTrancheToken: hook failed");
        hookToken.transfer(bob, 500e18);
    }

    function test_mint_doesNotCallHook() public {
        MockHookReceiver receiver = new MockHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(receiver), 0);

        vm.prank(address(receiver));
        hookToken.mint(alice, 1000e18);

        // mint() calls _mint() internally, which calls _update() — but MockEERC's
        // transfer hook is only in transfer()/transferFrom(), not in _update().
        // So the hook should NOT be called.
        assertEq(receiver.callCount(), 0);
    }

    function test_burn_doesNotCallHook() public {
        MockHookReceiver receiver = new MockHookReceiver();
        EncryptedTrancheToken hookToken = new EncryptedTrancheToken("Test", "TST", address(receiver), 0);

        vm.prank(address(receiver));
        hookToken.mint(alice, 1000e18);
        assertEq(receiver.callCount(), 0);

        vm.prank(address(receiver));
        hookToken.burn(alice, 500e18);
        assertEq(receiver.callCount(), 0);
    }

    // --- Interface conformance ---

    function test_implementsITrancheToken() public view {
        ITrancheToken iToken = ITrancheToken(address(token));
        assertEq(iToken.vault(), vaultAddr);
        assertEq(iToken.trancheId(), 0);
        assertEq(iToken.totalSupply(), 0);
    }
}

// ===================================================================
//  Contract B: ForgeVault Integration with EncryptedTrancheToken
// ===================================================================

contract EncryptedTrancheVaultIntegrationTest is Test {
    // --- Actors ---
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");

    // --- Contracts ---
    ForgeFactory factory;
    ForgeVault vault;
    MockYieldSource underlying;
    EncryptedTrancheToken seniorToken;
    EncryptedTrancheToken mezzToken;
    EncryptedTrancheToken equityToken;

    // --- Constants ---
    uint256 constant POOL_SIZE = 1_000_000e18;
    uint256 constant SENIOR_SIZE = 700_000e18;
    uint256 constant MEZZ_SIZE = 200_000e18;
    uint256 constant EQUITY_SIZE = 100_000e18;
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;

    function setUp() public {
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        factory = new ForgeFactory(treasury, protocolAdmin, 0);

        // Predict vault address
        uint256 factoryNonce = vm.getNonce(address(factory));
        address predictedVault = vm.computeCreateAddress(address(factory), factoryNonce);

        // Deploy EncryptedTrancheTokens pointing to predicted vault
        seniorToken = new EncryptedTrancheToken("Senior eERC", "eSR", predictedVault, 0);
        mezzToken = new EncryptedTrancheToken("Mezzanine eERC", "eMZ", predictedVault, 1);
        equityToken = new EncryptedTrancheToken("Equity eERC", "eEQ", predictedVault, 2);

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

        vm.prank(alice);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(carol);
        underlying.approve(address(vault), type(uint256).max);
    }

    // --- Setup validation ---

    function test_setUp_trancheTokensCorrect() public view {
        assertEq(seniorToken.vault(), address(vault));
        assertEq(seniorToken.owner(), address(vault));
        assertEq(seniorToken.trancheId(), 0);
        assertEq(mezzToken.vault(), address(vault));
        assertEq(mezzToken.trancheId(), 1);
        assertEq(equityToken.vault(), address(vault));
        assertEq(equityToken.trancheId(), 2);
    }

    function test_setUp_transferHookAutoSetup() public view {
        assertEq(seniorToken.transferHookTarget(), address(vault));
        assertEq(mezzToken.transferHookTarget(), address(vault));
        assertEq(equityToken.transferHookTarget(), address(vault));
    }

    // --- Invest ---

    function test_invest_senior() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);

        // eERC token balance matches investment
        assertEq(seniorToken.balanceOf(alice), SENIOR_SIZE);
        // Plaintext mirror matches
        assertEq(vault.getShares(alice, 0), SENIOR_SIZE);
    }

    function test_invest_allTranches() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);

        assertEq(seniorToken.balanceOf(alice), SENIOR_SIZE);
        assertEq(mezzToken.balanceOf(bob), MEZZ_SIZE);
        assertEq(equityToken.balanceOf(carol), EQUITY_SIZE);

        assertEq(vault.getShares(alice, 0), SENIOR_SIZE);
        assertEq(vault.getShares(bob, 1), MEZZ_SIZE);
        assertEq(vault.getShares(carol, 2), EQUITY_SIZE);
    }

    // --- Waterfall + Yield ---

    function test_waterfall_basicDistribution() public {
        // Invest
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);

        // Simulate yield
        uint256 yieldAmount = 50_000e18;
        underlying.mint(address(vault), yieldAmount);

        // Advance time and trigger waterfall
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        // Check claimable yield exists
        uint256 seniorClaimable = vault.getClaimableYield(alice, 0);
        uint256 mezzClaimable = vault.getClaimableYield(bob, 1);
        uint256 equityClaimable = vault.getClaimableYield(carol, 2);

        // Senior gets filled first
        assertGt(seniorClaimable, 0, "Senior should have claimable yield");
        // Total distributed should equal yield
        assertApproxEqRel(
            seniorClaimable + mezzClaimable + equityClaimable,
            yieldAmount,
            1e13 // 0.001% tolerance
        );
    }

    function test_claimYield_success() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);

        underlying.mint(address(vault), 50_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        uint256 claimable = vault.getClaimableYield(alice, 0);
        uint256 balanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        vault.claimYield(0);

        assertEq(underlying.balanceOf(alice), balanceBefore + claimable);
        assertEq(vault.getClaimableYield(alice, 0), 0);
    }

    // --- Withdraw ---

    function test_withdraw_full() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);

        vm.prank(alice);
        vault.withdraw(0, SENIOR_SIZE);

        assertEq(seniorToken.balanceOf(alice), 0);
        assertEq(vault.getShares(alice, 0), 0);
        assertEq(underlying.balanceOf(alice), SENIOR_SIZE);
    }

    // --- Transfer Hook Integration ---

    function test_transferHook_syncsPlaintextMirror() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);

        uint256 transferAmount = SENIOR_SIZE / 2;

        // Alice transfers half to Dave
        vm.prank(alice);
        seniorToken.transfer(dave, transferAmount);

        // Both token balances and plaintext mirrors should be updated
        assertEq(seniorToken.balanceOf(alice), SENIOR_SIZE - transferAmount);
        assertEq(seniorToken.balanceOf(dave), transferAmount);
        assertEq(vault.getShares(alice, 0), SENIOR_SIZE - transferAmount);
        assertEq(vault.getShares(dave, 0), transferAmount);
    }

    function test_transferHook_settlesYieldForBothParties() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);

        // Generate and distribute yield
        underlying.mint(address(vault), 50_000e18);
        vm.warp(block.timestamp + YEAR);
        vault.triggerWaterfall();

        uint256 aliceYieldBefore = vault.getClaimableYield(alice, 0);
        assertGt(aliceYieldBefore, 0, "Alice should have yield before transfer");

        // Transfer half to Dave — should settle Alice's yield first
        vm.prank(alice);
        seniorToken.transfer(dave, SENIOR_SIZE / 2);

        // Alice's settled yield should be preserved
        uint256 aliceYieldAfter = vault.getClaimableYield(alice, 0);
        assertEq(aliceYieldAfter, aliceYieldBefore, "Alice yield should be settled and preserved");
    }

    function test_transferHook_newRecipientEarnsYieldAfterTransfer() public {
        vm.prank(alice);
        vault.invest(0, SENIOR_SIZE);
        vm.prank(bob);
        vault.invest(1, MEZZ_SIZE);
        vm.prank(carol);
        vault.invest(2, EQUITY_SIZE);

        // Transfer half to Dave before any yield
        vm.prank(alice);
        seniorToken.transfer(dave, SENIOR_SIZE / 2);

        // Now generate and distribute yield
        underlying.mint(address(vault), 50_000e18);
        vm.warp(block.timestamp + WEEK + YEAR);
        vault.triggerWaterfall();

        // Dave should now have claimable yield proportional to his share
        uint256 daveYield = vault.getClaimableYield(dave, 0);
        uint256 aliceYield = vault.getClaimableYield(alice, 0);

        // They hold equal shares, so yield should be approximately equal
        assertGt(daveYield, 0, "Dave should earn yield after receiving shares");
        assertApproxEqRel(daveYield, aliceYield, 1e13);
    }
}

// ===================================================================
//  Helper Contracts
// ===================================================================

/// @notice Mock vault that accepts transfer hooks and records calls
contract MockHookReceiver {
    address public lastFrom;
    address public lastTo;
    uint256 public lastAmount;
    uint256 public callCount;

    function onShareTransfer(address from, address to, uint256 amount) external {
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
        callCount++;
    }
}

/// @notice Mock vault that always reverts on hook calls
contract RevertingHookReceiver {
    function onShareTransfer(address, address, uint256) external pure {
        revert("Hook reverted!");
    }

    // Need mint capability as owner
    // The EncryptedTrancheToken constructor sets this as owner
}
