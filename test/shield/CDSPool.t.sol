// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";

// AMM contracts
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {ICreditEventOracle} from "../../src/interfaces/ICreditEventOracle.sol";

// Existing contracts
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";

// Libraries
import {BondingCurve} from "../../src/libraries/BondingCurve.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

// Mocks
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

/// @dev Wrapper to test BondingCurve library reverts (internal calls are inlined)
contract BondingCurveWrapper {
    function quotePremium(
        uint256 notional, uint256 totalLiquidity, uint256 totalProtection,
        uint256 baseSpreadWad, uint256 slopeWad, uint256 tenorSeconds
    ) external pure returns (uint256) {
        return BondingCurve.quotePremium(notional, totalLiquidity, totalProtection, baseSpreadWad, slopeWad, tenorSeconds);
    }
}

// ============================================================
// BondingCurve Library Tests
// ============================================================

contract BondingCurveTest is Test {
    BondingCurveWrapper wrapper;

    function setUp() public {
        wrapper = new BondingCurveWrapper();
    }
    uint256 constant WAD = 1e18;

    // Base spread = 2% annual, slope = 5%
    uint256 constant BASE = 0.02e18;
    uint256 constant SLOPE = 0.05e18;
    uint256 constant YEAR = 365 days;

    function test_getSpread_zeroUtilization() public pure {
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, 0);
        assertEq(spread, BASE, "Zero util = base spread");
    }

    function test_getSpread_lowUtilization() public pure {
        // At 10%: spread = 0.02 + 0.05 * 0.01 / 0.9 ≈ 0.02 + 0.000556 ≈ 0.020556
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, 0.1e18);
        assertGt(spread, BASE, "Spread > base at 10%");
        assertLt(spread, BASE + SLOPE, "Spread < base + slope at 10%");
    }

    function test_getSpread_midUtilization() public pure {
        // At 50%: spread = 0.02 + 0.05 * 0.25 / 0.5 = 0.02 + 0.025 = 0.045
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, 0.5e18);
        assertApproxEqRel(spread, 0.045e18, 1e15, "50% util spread");
    }

    function test_getSpread_highUtilization() public pure {
        // At 80%: spread = 0.02 + 0.05 * 0.64 / 0.2 = 0.02 + 0.16 = 0.18
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, 0.8e18);
        assertApproxEqRel(spread, 0.18e18, 1e15, "80% util spread");
    }

    function test_getSpread_veryHighUtilization() public pure {
        // At 90%: spread = 0.02 + 0.05 * 0.81 / 0.1 = 0.02 + 0.405 = 0.425
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, 0.9e18);
        assertApproxEqRel(spread, 0.425e18, 1e15, "90% util spread");
    }

    function test_getSpread_monotonicallyIncreasing() public pure {
        uint256 prevSpread = BondingCurve.getSpread(BASE, SLOPE, 0);
        for (uint256 u = 0.05e18; u <= 0.9e18; u += 0.05e18) {
            uint256 spread = BondingCurve.getSpread(BASE, SLOPE, u);
            assertGe(spread, prevSpread, "Spread must be monotonically increasing");
            prevSpread = spread;
        }
    }

    function test_getSpread_capsAt100Pct() public pure {
        // Should not revert even at 100%+ (capped at 95%)
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, WAD);
        assertGt(spread, 0, "Spread at 100% cap");
    }

    function test_quotePremium_basic() public pure {
        // Pool: 1M liquidity, 0 existing protection, buy 100k protection for 1 year
        uint256 premium = BondingCurve.quotePremium(
            100_000e18,  // notional
            1_000_000e18, // liquidity
            0,            // existing protection
            BASE,
            SLOPE,
            YEAR
        );
        // At ~5% utilization midpoint, spread ≈ base + tiny curve
        // Premium ≈ 100k * ~2.01% ≈ ~2,013
        assertGt(premium, 0, "Premium > 0");
        assertGt(premium, 1_900e18, "Premium > 1900 (near base rate)");
        assertLt(premium, 3_000e18, "Premium < 3000 (reasonable)");
    }

    function test_quotePremium_higherWithExistingProtection() public pure {
        uint256 premiumLow = BondingCurve.quotePremium(
            100_000e18, 1_000_000e18, 0, BASE, SLOPE, YEAR
        );
        uint256 premiumHigh = BondingCurve.quotePremium(
            100_000e18, 1_000_000e18, 500_000e18, BASE, SLOPE, YEAR
        );
        assertGt(premiumHigh, premiumLow, "Premium higher at higher utilization");
    }

    function test_quotePremium_revert_exceedsMaxUtil() public {
        // Try to buy 960k from 1M pool → 96% utilization → exceeds 95% cap
        vm.expectRevert("BondingCurve: exceeds max utilization");
        wrapper.quotePremium(960_000e18, 1_000_000e18, 0, BASE, SLOPE, YEAR);
    }

    function test_quotePremium_revert_noLiquidity() public {
        vm.expectRevert("BondingCurve: no liquidity");
        wrapper.quotePremium(100e18, 0, 0, BASE, SLOPE, YEAR);
    }

    function test_utilization_basic() public pure {
        assertEq(BondingCurve.utilization(0, 1_000_000e18), 0, "Zero util");
        assertApproxEqRel(
            BondingCurve.utilization(500_000e18, 1_000_000e18),
            0.5e18, 1e15, "50% util"
        );
    }

    function test_utilization_noLiquidity() public pure {
        assertEq(BondingCurve.utilization(0, 0), 0, "No liquidity = 0 util");
    }

    /// @dev Fuzz: spread is always >= baseSpread and monotonically increases with u
    function testFuzz_getSpread_alwaysAboveBase(uint256 u) public pure {
        u = bound(u, 0, 0.94e18);
        uint256 spread = BondingCurve.getSpread(BASE, SLOPE, u);
        assertGe(spread, BASE, "Spread >= base");
    }

    /// @dev Fuzz: premium is always positive for valid inputs
    function testFuzz_quotePremium_positive(uint256 notional, uint256 liquidity) public pure {
        notional = bound(notional, 1e18, 100_000e18);
        liquidity = bound(liquidity, notional * 100 / 95 + 1e18, 10_000_000e18);
        uint256 premium = BondingCurve.quotePremium(
            notional, liquidity, 0, BASE, SLOPE, YEAR
        );
        assertGt(premium, 0, "Premium always positive");
    }
}

// ============================================================
// CDSPool Tests
// ============================================================

contract CDSPoolTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;
    uint256 constant BASE_SPREAD = 0.02e18;  // 2%
    uint256 constant SLOPE = 0.05e18;        // 5%

    MockYieldSource usdc;
    CreditEventOracle oracle;
    CDSPool pool;

    address alice = makeAddr("alice");  // LP
    address bob = makeAddr("bob");      // Protection buyer
    address charlie = makeAddr("charlie"); // Another LP
    address vault = makeAddr("vault");  // Reference asset

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();

        ICDSPool.PoolTerms memory terms = ICDSPool.PoolTerms({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: BASE_SPREAD,
            slopeWad: SLOPE
        });

        pool = new CDSPool(terms, address(this), address(this), address(this), 0);

        // Fund actors
        usdc.mint(alice, 10_000_000e18);
        usdc.mint(bob, 10_000_000e18);
        usdc.mint(charlie, 10_000_000e18);

        // Approvals
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(pool), type(uint256).max);
    }

    // --- Deposit Tests ---

    function test_deposit_basic() public {
        vm.prank(alice);
        uint256 shares = pool.deposit(1_000_000e18);
        assertEq(shares, 1_000_000e18, "First deposit: 1:1 shares");
        assertEq(pool.totalShares(), 1_000_000e18);
        assertEq(pool.totalAssets(), 1_000_000e18);
        assertEq(pool.sharesOf(alice), 1_000_000e18);
    }

    function test_deposit_multipleLP() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(charlie);
        uint256 shares = pool.deposit(500_000e18);
        assertEq(shares, 500_000e18, "Proportional shares");
        assertEq(pool.totalAssets(), 1_500_000e18);
    }

    function test_deposit_revert_zero() public {
        vm.prank(alice);
        vm.expectRevert("CDSPool: zero deposit");
        pool.deposit(0);
    }

    // --- Withdraw Tests ---

    function test_withdraw_full() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Warp past LP cooldown
        vm.warp(block.timestamp + pool.LP_COOLDOWN() + 1);

        vm.prank(alice);
        uint256 amount = pool.withdraw(1_000_000e18);
        assertApproxEqRel(amount, 1_000_000e18, 1e15, "Full withdrawal");
        assertEq(pool.totalShares(), 0);
    }

    function test_withdraw_partial() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Warp past LP cooldown
        vm.warp(block.timestamp + pool.LP_COOLDOWN() + 1);

        vm.prank(alice);
        uint256 amount = pool.withdraw(500_000e18);
        assertApproxEqRel(amount, 500_000e18, 1e15, "Half withdrawal");
        assertEq(pool.sharesOf(alice), 500_000e18);
    }

    function test_withdraw_revert_undercollateralized() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Warp past LP cooldown
        vm.warp(block.timestamp + pool.LP_COOLDOWN() + 1);

        // Buy protection (using up some capacity)
        vm.prank(bob);
        pool.buyProtection(500_000e18, 100_000e18);

        // Try to withdraw too much (would leave pool undercollateralized)
        vm.prank(alice);
        vm.expectRevert("CDSPool: withdrawal would undercollateralize");
        pool.withdraw(800_000e18);
    }

    function test_withdraw_revert_insufficientShares() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(alice);
        vm.expectRevert("CDSPool: insufficient shares");
        pool.withdraw(2_000_000e18);
    }

    // --- Buy Protection Tests ---

    function test_buyProtection_basic() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 quote = pool.quoteProtection(100_000e18);
        assertGt(quote, 0, "Quote > 0");

        vm.prank(bob);
        uint256 posId = pool.buyProtection(100_000e18, quote + 1e18);
        assertEq(posId, 0, "First position ID = 0");
        assertEq(pool.totalProtectionSold(), 100_000e18);

        ICDSPool.ProtectionPosition memory pos = pool.getPosition(0);
        assertEq(pos.buyer, bob);
        assertEq(pos.notional, 100_000e18);
        assertEq(pos.premiumPaid, quote);
        assertTrue(pos.active);
    }

    function test_buyProtection_multiplePositions() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(100_000e18, 50_000e18);

        vm.prank(bob);
        pool.buyProtection(200_000e18, 100_000e18);

        assertEq(pool.totalProtectionSold(), 300_000e18);
        assertEq(pool.nextPositionId(), 2);
    }

    function test_buyProtection_spreadIncreasesWithUtilization() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 quote1 = pool.quoteProtection(100_000e18);

        // Buy first chunk
        vm.prank(bob);
        pool.buyProtection(100_000e18, quote1 + 1e18);

        // Second chunk should be more expensive
        uint256 quote2 = pool.quoteProtection(100_000e18);
        assertGt(quote2, quote1, "Spread increases with utilization");
    }

    function test_buyProtection_revert_exceedsSlippage() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        vm.expectRevert("CDSPool: premium exceeds max");
        pool.buyProtection(100_000e18, 1); // maxPremium = 1 wei (way too low)
    }

    function test_buyProtection_revert_zeroNotional() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        vm.expectRevert("CDSPool: zero notional");
        pool.buyProtection(0, 100_000e18);
    }

    // --- Close Protection Tests ---

    function test_closeProtection_earlyClose() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        uint256 posId = pool.buyProtection(100_000e18, 50_000e18);

        ICDSPool.ProtectionPosition memory posBefore = pool.getPosition(posId);

        // Advance 25% of the way to maturity
        vm.warp(block.timestamp + YEAR / 4);

        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        uint256 refund = pool.closeProtection(posId);

        // Should get back ~75% of premium (earned ~25%)
        assertGt(refund, 0, "Got refund");
        assertApproxEqRel(refund, posBefore.premiumPaid * 3 / 4, 0.05e18, "~75% refund");
        assertEq(usdc.balanceOf(bob), bobBefore + refund);

        ICDSPool.ProtectionPosition memory posAfter = pool.getPosition(posId);
        assertFalse(posAfter.active, "Position closed");
        assertEq(pool.totalProtectionSold(), 0, "Protection removed");
    }

    function test_closeProtection_revert_notOwner() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        uint256 posId = pool.buyProtection(100_000e18, 50_000e18);

        vm.prank(charlie);
        vm.expectRevert("CDSPool: not position owner");
        pool.closeProtection(posId);
    }

    // --- Premium Accrual Tests ---

    function test_premiumAccrual_increasesAssets() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(100_000e18, 50_000e18);

        uint256 assetsBefore = pool.totalAssets();

        // Advance 6 months
        vm.warp(block.timestamp + YEAR / 2);
        pool.accrueAllPremiums();

        uint256 assetsAfter = pool.totalAssets();
        assertGt(assetsAfter, assetsBefore, "Assets increased from premiums");
    }

    function test_premiumAccrual_lpSharesAppreciate() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 shareValueBefore = pool.convertToAssets(1e18);

        // Buy protection
        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Advance 6 months
        vm.warp(block.timestamp + YEAR / 2);
        pool.accrueAllPremiums();

        uint256 shareValueAfter = pool.convertToAssets(1e18);
        assertGt(shareValueAfter, shareValueBefore, "LP share value appreciated");
    }

    function test_premiumAccrual_proportionalToLPs() public {
        // Alice deposits 750k, Charlie deposits 250k (3:1 ratio)
        vm.prank(alice);
        pool.deposit(750_000e18);
        vm.prank(charlie);
        pool.deposit(250_000e18);

        // Buy protection
        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Advance to maturity
        vm.warp(block.timestamp + YEAR);
        pool.accrueAllPremiums();

        // Withdraw everything
        uint256 aliceShares = pool.sharesOf(alice);
        uint256 charlieShares = pool.sharesOf(charlie);

        uint256 aliceValue = pool.convertToAssets(aliceShares);
        uint256 charlieValue = pool.convertToAssets(charlieShares);

        // Alice should get ~3x what Charlie gets
        assertApproxEqRel(aliceValue, charlieValue * 3, 0.01e18, "3:1 premium distribution");
    }

    // --- Credit Event / Settlement Tests ---

    function test_triggerCreditEvent() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Report credit event
        oracle.reportCreditEvent(
            vault,
            ICreditEventOracle.EventType.Default,
            500_000e18
        );

        pool.triggerCreditEvent();
        assertEq(uint256(pool.getPoolStatus()), uint256(ICDSPool.PoolStatus.Triggered));
    }

    function test_triggerCreditEvent_revert_noEvent() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.expectRevert("CDSPool: no credit event");
        pool.triggerCreditEvent();
    }

    function test_settle_fullLoss() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Trigger
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500_000e18);
        pool.triggerCreditEvent();

        uint256 bobBefore = usdc.balanceOf(bob);

        // Settle with 0% recovery (total loss) — now pull-based
        pool.settle(0);

        // Bob must claim his settlement
        vm.prank(bob);
        pool.claimSettlement();

        uint256 bobAfter = usdc.balanceOf(bob);
        assertEq(bobAfter - bobBefore, 500_000e18, "Full payout to buyer");
        assertEq(uint256(pool.getPoolStatus()), uint256(ICDSPool.PoolStatus.Settled));
    }

    function test_settle_partialRecovery() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Trigger
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500_000e18);
        pool.triggerCreditEvent();

        uint256 bobBefore = usdc.balanceOf(bob);

        // Settle with 60% recovery → 40% loss → 200k payout — now pull-based
        pool.settle(0.6e18);

        // Bob must claim
        vm.prank(bob);
        pool.claimSettlement();

        uint256 payout = usdc.balanceOf(bob) - bobBefore;
        assertApproxEqRel(payout, 200_000e18, 1e15, "40% loss payout");
    }

    function test_settle_lpBearLoss() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Trigger and settle (total loss)
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500_000e18);
        pool.triggerCreditEvent();
        pool.settle(0);

        // Alice's shares should now be worth less
        uint256 aliceValue = pool.convertToAssets(pool.sharesOf(alice));
        assertLt(aliceValue, 1_000_000e18, "LP lost capital");
    }

    function test_settle_multiplePositions() public {
        vm.prank(alice);
        pool.deposit(2_000_000e18);

        // Two buyers
        vm.prank(bob);
        pool.buyProtection(300_000e18, 100_000e18);
        vm.prank(charlie);
        pool.buyProtection(200_000e18, 100_000e18);

        // Trigger and settle
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500_000e18);
        pool.triggerCreditEvent();

        uint256 bobBefore = usdc.balanceOf(bob);
        uint256 charlieBefore = usdc.balanceOf(charlie);

        pool.settle(0); // Total loss — pull-based

        // Both must claim
        vm.prank(bob);
        pool.claimSettlement();
        vm.prank(charlie);
        pool.claimSettlement();

        assertEq(usdc.balanceOf(bob) - bobBefore, 300_000e18, "Bob payout");
        assertEq(usdc.balanceOf(charlie) - charlieBefore, 200_000e18, "Charlie payout");
    }

    // --- Expiry Tests ---

    function test_expire_basic() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(100_000e18, 50_000e18);

        // Advance past maturity
        vm.warp(block.timestamp + YEAR + 1);
        pool.expire();

        assertEq(uint256(pool.getPoolStatus()), uint256(ICDSPool.PoolStatus.Expired));
        assertEq(pool.totalProtectionSold(), 0, "All protection expired");
    }

    function test_expire_lpCanWithdraw() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(bob);
        pool.buyProtection(100_000e18, 50_000e18);

        // Expire
        vm.warp(block.timestamp + YEAR + 1);
        pool.expire();

        // LP should withdraw more than deposited (earned premiums)
        uint256 aliceShares = pool.sharesOf(alice);
        vm.prank(alice);
        uint256 amount = pool.withdraw(aliceShares);
        assertGt(amount, 1_000_000e18, "LP earned premium");
    }

    function test_expire_revert_notMatured() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.expectRevert("CDSPool: not matured");
        pool.expire();
    }

    // --- View Function Tests ---

    function test_currentSpread_changesWithUtil() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 spreadBefore = pool.currentSpread();
        assertEq(spreadBefore, BASE_SPREAD, "Zero util = base spread");

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        uint256 spreadAfter = pool.currentSpread();
        assertGt(spreadAfter, spreadBefore, "Spread increased");
    }

    function test_utilizationRate() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        assertEq(pool.utilizationRate(), 0, "Initial utilization = 0");

        vm.prank(bob);
        pool.buyProtection(500_000e18, 200_000e18);

        // Utilization ≈ 500k / (1M + premium) — slightly less than 50% due to premium in assets
        uint256 util = pool.utilizationRate();
        assertGt(util, 0.4e18, "Utilization > 40%");
        assertLt(util, 0.55e18, "Utilization < 55%");
    }

    function test_convertToShares_and_convertToAssets() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 shares = pool.convertToShares(500_000e18);
        uint256 assets = pool.convertToAssets(shares);
        assertApproxEqRel(assets, 500_000e18, 1e15, "Round-trip conversion");
    }

    // --- Fuzz Tests ---

    /// @dev Fuzz: LP deposit and withdrawal should preserve value (no profit/loss without premiums)
    function testFuzz_depositWithdraw_preservesValue(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e18, 10_000_000e18);

        usdc.mint(alice, depositAmount);
        vm.startPrank(alice);
        usdc.approve(address(pool), depositAmount);
        uint256 shares = pool.deposit(depositAmount);
        vm.stopPrank();

        // Warp past LP cooldown
        vm.warp(block.timestamp + pool.LP_COOLDOWN() + 1);

        vm.prank(alice);
        uint256 withdrawn = pool.withdraw(shares);

        assertApproxEqRel(withdrawn, depositAmount, 1e15, "Value preserved");
    }

    /// @dev Fuzz: buying protection should always increase utilization
    function testFuzz_buyProtection_increasesUtil(uint256 notional) public {
        notional = bound(notional, 1e18, 900_000e18);

        vm.prank(alice);
        pool.deposit(1_000_000e18);

        uint256 utilBefore = pool.utilizationRate();

        uint256 quote = pool.quoteProtection(notional);
        usdc.mint(bob, quote + 1e18);
        vm.startPrank(bob);
        usdc.approve(address(pool), quote + 1e18);
        pool.buyProtection(notional, quote + 1e18);
        vm.stopPrank();

        uint256 utilAfter = pool.utilizationRate();
        assertGt(utilAfter, utilBefore, "Utilization increased");
    }
}

// ============================================================
// CDSPoolFactory Tests
// ============================================================

contract CDSPoolFactoryTest is Test {
    uint256 constant YEAR = 365 days;

    MockYieldSource usdc;
    CreditEventOracle oracle;
    CDSPoolFactory factory;

    address vault1 = makeAddr("vault1");
    address vault2 = makeAddr("vault2");
    address creator = makeAddr("creator");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        factory = new CDSPoolFactory(address(this), address(this), 0);
    }

    function test_createPool() public {
        vm.prank(creator);
        address poolAddr = factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault1,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));

        assertEq(factory.poolCount(), 1);
        assertEq(factory.getPool(0), poolAddr);
        assertTrue(poolAddr != address(0));

        CDSPool pool = CDSPool(poolAddr);
        ICDSPool.PoolTerms memory terms = pool.getPoolTerms();
        assertEq(terms.referenceAsset, vault1);
        assertEq(terms.baseSpreadWad, 0.02e18);
    }

    function test_createPool_tracksByReferenceAsset() public {
        vm.startPrank(creator);
        factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault1,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));
        factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault1,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + 2 * YEAR,
            baseSpreadWad: 0.03e18,
            slopeWad: 0.05e18
        }));
        factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault2,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));
        vm.stopPrank();

        assertEq(factory.getPoolsForVault(vault1).length, 2);
        assertEq(factory.getPoolsForVault(vault2).length, 1);
    }

    function test_createPool_tracksByCreator() public {
        vm.prank(creator);
        factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault1,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));

        assertEq(factory.getCreatorPools(creator).length, 1);
    }

    function test_createPool_multiplePools() public {
        vm.startPrank(creator);
        for (uint256 i = 0; i < 5; i++) {
            factory.createPool(CDSPoolFactory.CreatePoolParams({
                referenceAsset: vault1,
                collateralToken: address(usdc),
                oracle: address(oracle),
                maturity: block.timestamp + YEAR,
                baseSpreadWad: 0.02e18,
                slopeWad: 0.05e18
            }));
        }
        vm.stopPrank();

        assertEq(factory.poolCount(), 5);
    }
}

// ============================================================
// Integration Tests
// ============================================================

contract CDSPoolIntegrationTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;

    MockYieldSource usdc;
    CreditEventOracle oracle;
    CDSPoolFactory factory;

    address alice = makeAddr("alice");   // LP
    address bob = makeAddr("bob");       // Buyer
    address charlie = makeAddr("charlie"); // LP 2
    address vault = makeAddr("vault");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        oracle = new CreditEventOracle();
        factory = new CDSPoolFactory(address(this), address(this), 0);

        usdc.mint(alice, 100_000_000e18);
        usdc.mint(bob, 100_000_000e18);
        usdc.mint(charlie, 100_000_000e18);
    }

    function test_fullLifecycle_noEvent() public {
        // 1. Create pool
        address poolAddr = factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));
        CDSPool pool = CDSPool(poolAddr);

        // 2. LPs deposit
        vm.prank(alice);
        usdc.approve(poolAddr, type(uint256).max);
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(charlie);
        usdc.approve(poolAddr, type(uint256).max);
        vm.prank(charlie);
        pool.deposit(500_000e18);

        assertEq(pool.totalAssets(), 1_500_000e18);

        // 3. Buy protection
        uint256 quote = pool.quoteProtection(200_000e18);
        vm.prank(bob);
        usdc.approve(poolAddr, type(uint256).max);
        vm.prank(bob);
        pool.buyProtection(200_000e18, quote + 1e18);

        // 4. Time passes, premiums accrue
        vm.warp(block.timestamp + YEAR / 2);
        pool.accrueAllPremiums();
        assertGt(pool.totalPremiumsEarned(), 0, "Premiums earned");

        // 5. Expire at maturity
        vm.warp(block.timestamp + YEAR);
        pool.expire();

        // 6. LPs withdraw (should profit)
        uint256 aliceShares = pool.sharesOf(alice);
        uint256 charlieShares = pool.sharesOf(charlie);

        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(aliceShares);
        uint256 aliceProfit = usdc.balanceOf(alice) - aliceBefore;

        uint256 charlieBefore = usdc.balanceOf(charlie);
        vm.prank(charlie);
        pool.withdraw(charlieShares);
        uint256 charlieProfit = usdc.balanceOf(charlie) - charlieBefore;

        assertGt(aliceProfit, 1_000_000e18, "Alice profited");
        assertGt(charlieProfit, 500_000e18, "Charlie profited");

        // Alice gets 2x Charlie's premium (deposited 2x)
        uint256 alicePremium = aliceProfit - 1_000_000e18;
        uint256 charliePremium = charlieProfit - 500_000e18;
        assertApproxEqRel(alicePremium, charliePremium * 2, 0.02e18, "2:1 premium split");
    }

    function test_fullLifecycle_withCreditEvent() public {
        // 1. Create pool
        address poolAddr = factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));
        CDSPool pool = CDSPool(poolAddr);

        // 2. LP deposits
        vm.prank(alice);
        usdc.approve(poolAddr, type(uint256).max);
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // 3. Buy protection
        vm.prank(bob);
        usdc.approve(poolAddr, type(uint256).max);
        uint256 quote = pool.quoteProtection(500_000e18);
        vm.prank(bob);
        pool.buyProtection(500_000e18, quote + 1e18);

        // 4. Credit event occurs
        vm.warp(block.timestamp + 90 days);
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500_000e18);
        pool.triggerCreditEvent();

        // 5. Settle with 30% recovery (must go through factory — settle restricted to factory)
        uint256 bobBefore = usdc.balanceOf(bob);
        factory.settlePool(0, 0.3e18);

        // Pull-based: bob must claim settlement
        vm.prank(bob);
        pool.claimSettlement();
        uint256 bobPayout = usdc.balanceOf(bob) - bobBefore;

        // Bob should get 500k * 70% = 350k
        assertApproxEqRel(bobPayout, 350_000e18, 1e15, "70% loss payout");

        // 6. LP withdraws (lost money)
        uint256 aliceShares = pool.sharesOf(alice);
        vm.prank(alice);
        uint256 aliceWithdraw = pool.withdraw(aliceShares);
        assertLt(aliceWithdraw, 1_000_000e18, "Alice lost capital to payout");
    }

    function test_dynamicPricingE2E() public {
        // Create pool
        address poolAddr = factory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));
        CDSPool pool = CDSPool(poolAddr);

        vm.prank(alice);
        usdc.approve(poolAddr, type(uint256).max);
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Track quotes as we buy more and more protection
        uint256[] memory quotes = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            quotes[i] = pool.quoteProtection(100_000e18);
            vm.prank(bob);
            usdc.approve(poolAddr, type(uint256).max);
            vm.prank(bob);
            pool.buyProtection(100_000e18, quotes[i] + 1e18);
        }

        // Each successive quote should be higher (bonding curve effect)
        for (uint256 i = 1; i < 5; i++) {
            assertGt(quotes[i], quotes[i - 1], "Quote increases with utilization");
        }
    }
}
