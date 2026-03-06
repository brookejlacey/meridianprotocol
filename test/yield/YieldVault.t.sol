// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {YieldVault} from "../../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../../src/yield/YieldVaultFactory.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract YieldVaultTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant WEEK = 7 days;
    uint256 constant DAY = 1 days;

    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    YieldVaultFactory yvFactory;
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    YieldVault yv;

    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address keeper = makeAddr("keeper");
    address originator = makeAddr("originator");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        // Predict vault address
        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        seniorToken = new TrancheToken("Senior", "SR", predicted, 0);
        mezzToken = new TrancheToken("Mezzanine", "MZ", predicted, 1);
        equityToken = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mezzToken)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(equityToken)});

        vm.prank(originator);
        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
            trancheParams: params,
            distributionInterval: WEEK
        }));
        forgeVault = ForgeVault(fv);

        // Create YieldVault via factory
        yvFactory = new YieldVaultFactory(address(this));
        address yvAddr = yvFactory.createYieldVault(fv, 0, "Auto Senior", "acSR", DAY);
        yv = YieldVault(yvAddr);

        // Fund users
        usdc.mint(alice, 10_000_000e18);
        usdc.mint(bob, 10_000_000e18);

        vm.prank(alice);
        usdc.approve(address(yv), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(yv), type(uint256).max);
    }

    // --- Deposit ---

    function test_deposit_basic() public {
        vm.prank(alice);
        uint256 shares = yv.deposit(100_000e18, alice);

        assertGt(shares, 0, "Got shares");
        assertEq(yv.balanceOf(alice), shares);
        assertEq(yv.totalInvested(), 100_000e18);
    }

    function test_deposit_twoUsers() public {
        vm.prank(alice);
        yv.deposit(200_000e18, alice);

        vm.prank(bob);
        uint256 bobShares = yv.deposit(100_000e18, bob);

        assertGt(bobShares, 0);
        assertEq(yv.totalInvested(), 300_000e18);
    }

    function test_deposit_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert();
        yv.deposit(0, alice);
    }

    // --- Withdraw ---

    function test_withdraw_basic() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        uint256 shares = yv.balanceOf(alice);
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        yv.redeem(shares, alice, alice);

        uint256 received = usdc.balanceOf(alice) - balBefore;
        assertApproxEqRel(received, 100_000e18, 1e15, "Got back ~deposit");
    }

    function test_withdraw_partial() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        uint256 halfShares = yv.balanceOf(alice) / 2;
        vm.prank(alice);
        yv.redeem(halfShares, alice, alice);

        assertGt(yv.balanceOf(alice), 0, "Still has shares");
    }

    // --- Compound ---

    function test_compound_basic() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        // Inject yield into ForgeVault
        usdc.mint(address(forgeVault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        forgeVault.triggerWaterfall();

        // Compound
        vm.warp(block.timestamp + DAY);
        uint256 harvested = yv.compound();

        assertGt(harvested, 0, "Yield harvested");
        assertEq(yv.totalHarvested(), harvested);
    }

    function test_compound_sharePriceAppreciates() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        // Inject yield and distribute
        usdc.mint(address(forgeVault), 10_000e18);
        vm.warp(block.timestamp + WEEK);
        forgeVault.triggerWaterfall();

        vm.warp(block.timestamp + DAY);
        yv.compound();

        // Bob deposits after compound — should get fewer shares per USDC
        // With _decimalsOffset()=3, shares are scaled by 10^3. First depositor gets
        // 100_000e18 * 1000 = 100_000_000e18 shares. After appreciation, Bob gets fewer.
        vm.prank(bob);
        uint256 bobShares = yv.deposit(100_000e18, bob);

        assertLt(bobShares, 100_000_000e18, "Bob gets fewer shares after appreciation");
    }

    function test_compound_revert_tooSoon() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        // Compound once
        vm.warp(block.timestamp + WEEK);
        usdc.mint(address(forgeVault), 1_000e18);
        forgeVault.triggerWaterfall();
        vm.warp(block.timestamp + DAY);
        yv.compound();

        // Try again immediately
        vm.expectRevert("YieldVault: too soon");
        yv.compound();
    }

    function test_compound_noYield() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        vm.warp(block.timestamp + WEEK + DAY);
        uint256 harvested = yv.compound();
        assertEq(harvested, 0, "No yield to harvest");
    }

    // --- TotalAssets ---

    function test_totalAssets_includesClaimableYield() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        usdc.mint(address(forgeVault), 5_000e18);
        vm.warp(block.timestamp + WEEK);
        forgeVault.triggerWaterfall();

        uint256 total = yv.totalAssets();
        assertGt(total, 100_000e18, "Includes claimable yield");
    }

    // --- ERC4626 Compliance ---

    function test_convertToShares_and_Assets() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        uint256 shares = yv.convertToShares(50_000e18);
        uint256 assets = yv.convertToAssets(shares);
        assertApproxEqRel(assets, 50_000e18, 1e15);
    }

    function test_previewDeposit() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        uint256 preview = yv.previewDeposit(50_000e18);
        assertGt(preview, 0);
    }

    // --- View ---

    function test_getMetrics() public {
        vm.prank(alice);
        yv.deposit(100_000e18, alice);

        (uint256 totalAssets_, uint256 invested, uint256 harvested, uint256 sharePrice,) = yv.getMetrics();
        assertEq(invested, 100_000e18);
        assertEq(harvested, 0);
        assertGt(sharePrice, 0);
        assertGt(totalAssets_, 0);
    }

    // --- Fuzz ---

    function testFuzz_depositCompoundWithdraw_noLoss(uint256 deposit, uint256 yield_) public {
        deposit = bound(deposit, 1e18, 1_000_000e18);
        yield_ = bound(yield_, 0, deposit / 10);

        vm.prank(alice);
        yv.deposit(deposit, alice);

        if (yield_ > 0) {
            usdc.mint(address(forgeVault), yield_);
            vm.warp(block.timestamp + WEEK);
            forgeVault.triggerWaterfall();
            vm.warp(block.timestamp + DAY);
            yv.compound();
        }

        uint256 shares = yv.balanceOf(alice);
        vm.prank(alice);
        uint256 withdrawn = yv.redeem(shares, alice, alice);

        // Waterfall distributes only a portion of yield to senior tranche,
        // so withdrawn >= deposit (no principal loss). Use 1e15 tolerance for WAD rounding.
        assertGe(withdrawn + 1e15, deposit, "No principal loss");
    }
}

contract YieldVaultFactoryTest is Test {
    MockYieldSource usdc;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    YieldVaultFactory yvFactory;
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        TrancheToken sr = new TrancheToken("SR", "SR", predicted, 0);
        TrancheToken mz = new TrancheToken("MZ", "MZ", predicted, 1);
        TrancheToken eq = new TrancheToken("EQ", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory p;
        p[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(sr)});
        p[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mz)});
        p[2] = IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(eq)});

        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(sr), address(mz), address(eq)],
            trancheParams: p,
            distributionInterval: 7 days
        }));
        forgeVault = ForgeVault(fv);
        yvFactory = new YieldVaultFactory(address(this));
    }

    function test_createYieldVault() public {
        address yv = yvFactory.createYieldVault(address(forgeVault), 0, "acSR", "acSR", 1 days);
        assertNotEq(yv, address(0));
        assertEq(yvFactory.vaultCount(), 1);
        assertEq(yvFactory.getYieldVault(address(forgeVault), 0), yv);
        assertEq(yvFactory.getVault(0), yv);
    }

    function test_createYieldVault_revert_duplicate() public {
        yvFactory.createYieldVault(address(forgeVault), 0, "acSR", "acSR", 1 days);
        vm.expectRevert("YieldVaultFactory: already exists");
        yvFactory.createYieldVault(address(forgeVault), 0, "acSR2", "acSR2", 1 days);
    }

    function test_createYieldVault_revert_invalidTranche() public {
        vm.expectRevert("YieldVaultFactory: invalid tranche");
        yvFactory.createYieldVault(address(forgeVault), 5, "bad", "bad", 1 days);
    }

    function test_createYieldVault_revert_zeroVault() public {
        vm.expectRevert("YieldVaultFactory: zero vault");
        yvFactory.createYieldVault(address(0), 0, "bad", "bad", 1 days);
    }

    function test_multipleTranches() public {
        yvFactory.createYieldVault(address(forgeVault), 0, "acSR", "acSR", 1 days);
        yvFactory.createYieldVault(address(forgeVault), 1, "acMZ", "acMZ", 1 days);
        yvFactory.createYieldVault(address(forgeVault), 2, "acEQ", "acEQ", 1 days);
        assertEq(yvFactory.vaultCount(), 3);
    }
}
