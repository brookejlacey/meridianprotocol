// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Shield contracts
import {CDSContract} from "../../src/shield/CDSContract.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {PremiumEngine} from "../../src/shield/PremiumEngine.sol";
import {ShieldFactory} from "../../src/shield/ShieldFactory.sol";
import {ShieldPricer} from "../../src/shield/ShieldPricer.sol";

// Forge contracts (for integration test)
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {ICDSContract} from "../../src/interfaces/ICDSContract.sol";
import {ICreditEventOracle} from "../../src/interfaces/ICreditEventOracle.sol";

// Mocks
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

// Libraries
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

// ============================================================
// PremiumEngine Tests
// ============================================================

contract PremiumEngineTest is Test {
    uint256 constant YEAR = 365 days;
    uint256 constant BPS = 10_000;

    function test_calculateTotalPremium_basic() public pure {
        // 1M notional, 200 bps (2%), 365 days → 20,000
        uint256 premium = PremiumEngine.calculateTotalPremium(1_000_000e18, 200, 365);
        assertEq(premium, 20_000e18, "2% of 1M for 1 year = 20k");
    }

    function test_calculateTotalPremium_halfYear() public pure {
        // 1M notional, 200 bps, 182 days → ~9,972 (rounding)
        uint256 premium = PremiumEngine.calculateTotalPremium(1_000_000e18, 200, 182);
        // 1_000_000e18 * 200 * 182 / (10_000 * 365) = 9,972.602..e18
        assertApproxEqRel(premium, 9_972.602e18, 1e15);
    }

    function test_calculateTotalPremium_zeroDuration() public pure {
        uint256 premium = PremiumEngine.calculateTotalPremium(1_000_000e18, 200, 0);
        assertEq(premium, 0);
    }

    function test_accruedPremium_basic() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000,
            totalPaid: 0
        });

        // After half a year
        uint256 halfYear = 1000 + YEAR / 2;
        uint256 accrued = PremiumEngine.accruedPremium(state, halfYear);

        // Expected: 1M * 200/10000 * (YEAR/2) / YEAR = 10,000
        assertApproxEqRel(accrued, 10_000e18, 1e15, "Half year accrual ~10k");
    }

    function test_accruedPremium_cappedAtMaturity() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000,
            totalPaid: 0
        });

        // Well past maturity
        uint256 pastMaturity = 1000 + 2 * YEAR;
        uint256 accrued = PremiumEngine.accruedPremium(state, pastMaturity);

        // Should be capped at 1 year's premium
        assertApproxEqRel(accrued, 20_000e18, 1e15, "Capped at full year premium");
    }

    function test_accruedPremium_afterPartialPayment() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000 + YEAR / 4, // paid at Q1
            totalPaid: 5_000e18
        });

        // At half-year mark
        uint256 halfYear = 1000 + YEAR / 2;
        uint256 accrued = PremiumEngine.accruedPremium(state, halfYear);

        // Should be premium for Q2 only (Q1 was already paid)
        assertApproxEqRel(accrued, 5_000e18, 1e15, "Q2 accrual ~5k");
    }

    function test_accruedPremium_noTimeElapsed() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000,
            totalPaid: 0
        });

        assertEq(PremiumEngine.accruedPremium(state, 1000), 0);
        assertEq(PremiumEngine.accruedPremium(state, 999), 0);
    }

    function test_dailyPremium() public pure {
        // 1M notional, 365 bps → 100 per day
        uint256 daily = PremiumEngine.dailyPremium(1_000_000e18, 365);
        assertEq(daily, 100e18);
    }

    function test_isPaymentOverdue() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000,
            totalPaid: 0
        });

        uint256 interval = 30 days;
        assertFalse(PremiumEngine.isPaymentOverdue(state, 1000 + 29 days, interval));
        assertFalse(PremiumEngine.isPaymentOverdue(state, 1000 + 30 days, interval));
        assertTrue(PremiumEngine.isPaymentOverdue(state, 1000 + 31 days, interval));
    }

    function test_remainingPremium_midTerm() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000 + YEAR / 2,
            totalPaid: 10_000e18
        });

        uint256 remaining = PremiumEngine.remainingPremium(state, 1000 + YEAR / 2);
        // Remaining: half year in seconds (now seconds-precise, no day truncation)
        // 1M * 200 * (YEAR/2) / (10000 * YEAR) = 10,000
        assertApproxEqRel(remaining, 10_000e18, 1e14);
    }

    function test_remainingPremium_pastMaturity() public pure {
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: 1_000_000e18,
            annualSpreadBps: 200,
            startTime: 1000,
            maturity: 1000 + YEAR,
            lastPaymentTime: 1000,
            totalPaid: 0
        });

        assertEq(PremiumEngine.remainingPremium(state, 1000 + 2 * YEAR), 0);
    }

    function testFuzz_accruedPremium_neverExceedsTotalPremium(
        uint256 notional,
        uint256 spreadBps,
        uint256 elapsed
    ) public pure {
        notional = bound(notional, 1e18, 1e30);
        spreadBps = bound(spreadBps, 1, 5000);
        elapsed = bound(elapsed, 0, 2 * YEAR);

        uint256 startTime = 1000;
        PremiumEngine.PremiumState memory state = PremiumEngine.PremiumState({
            notional: notional,
            annualSpreadBps: spreadBps,
            startTime: startTime,
            maturity: startTime + YEAR,
            lastPaymentTime: startTime,
            totalPaid: 0
        });

        uint256 accrued = PremiumEngine.accruedPremium(state, startTime + elapsed);
        uint256 maxPremium = PremiumEngine.calculateTotalPremium(notional, spreadBps, 365);

        assertLe(accrued, maxPremium, "Accrued should never exceed total annual premium");
    }
}

// ============================================================
// ShieldPricer Tests
// ============================================================

contract ShieldPricerTest is Test {
    ShieldPricer pricer;

    ShieldPricer.PricingParams defaultParams;

    function setUp() public {
        defaultParams = ShieldPricer.PricingParams({
            baseRateBps: 50,            // 0.5%
            riskMultiplierBps: 2000,    // 20x for undercollateralization
            utilizationKinkBps: 8000,   // 80% kink
            utilizationSurchargeBps: 500, // +5% above kink
            tenorScalerBps: 100,        // +1% per year
            maxSpreadBps: 5000          // 50% cap
        });
        pricer = new ShieldPricer(defaultParams);
    }

    function test_calculateSpread_fullyCollateralized() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: MeridianMath.WAD, // 100%
            utilization: 0,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Active
        });

        // base(50) + risk(0) + util(0) + tenor(100*365/365=100) = 150
        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        assertEq(spread, 150, "Healthy pool: base + tenor only");
    }

    function test_calculateSpread_undercollateralized() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: 8e17, // 80%
            utilization: 0,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Active
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        // base(50) + risk(20% deficit * 2000 multiplier ≈ 400) + tenor(100) = ~550
        assertGt(spread, 150, "Undercollateralized increases spread");
        assertLt(spread, 5000, "Below max cap");
    }

    function test_calculateSpread_highUtilization() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: MeridianMath.WAD,
            utilization: 9e17, // 90% — above 80% kink
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Active
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        // base(50) + util surcharge(500) + tenor(100) = 650
        assertEq(spread, 650);
    }

    function test_calculateSpread_impairedPool() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: MeridianMath.WAD,
            utilization: 0,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Impaired
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        // base(50) + impaired penalty(1000) + tenor(100) = 1150
        assertEq(spread, 1150);
    }

    function test_calculateSpread_defaultedPool() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: MeridianMath.WAD,
            utilization: 0,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Defaulted
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        assertEq(spread, 5000, "Defaulted = max spread");
    }

    function test_calculateSpread_cappedAtMax() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: 1e17, // 10% — very undercollateralized
            utilization: 95e16,    // 95% — above kink
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Impaired
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 365);
        // Even if individual components sum > max, the cap enforces maxSpreadBps
        assertLe(spread, 5000, "Capped at maxSpread");
        // With 90% deficit + utilization surcharge + impaired penalty + tenor, should be high
        assertGt(spread, 2000, "Spread is significant for risky pool");
    }

    function test_calculateSpread_zeroTenor() public view {
        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: MeridianMath.WAD,
            utilization: 0,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Active
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, 0);
        assertEq(spread, 50, "Zero tenor = base rate only");
    }

    function test_setDefaultParams() public {
        ShieldPricer.PricingParams memory newParams = ShieldPricer.PricingParams({
            baseRateBps: 100,
            riskMultiplierBps: 3000,
            utilizationKinkBps: 7000,
            utilizationSurchargeBps: 800,
            tenorScalerBps: 200,
            maxSpreadBps: 8000
        });

        pricer.setDefaultParams(newParams);
        (uint256 baseRate,,,,, ) = pricer.defaultParams();
        assertEq(baseRate, 100);
    }

    function test_setVaultOverride() public {
        address vault = makeAddr("vault");
        ShieldPricer.PricingParams memory vaultParams = ShieldPricer.PricingParams({
            baseRateBps: 200,
            riskMultiplierBps: 1000,
            utilizationKinkBps: 9000,
            utilizationSurchargeBps: 300,
            tenorScalerBps: 50,
            maxSpreadBps: 3000
        });

        pricer.setVaultOverride(vault, vaultParams);
        assertTrue(pricer.hasOverride(vault));
    }

    function test_onlyOwner_setDefaultParams() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("ShieldPricer: not owner");
        pricer.setDefaultParams(defaultParams);
    }

    function testFuzz_calculateSpread_neverExceedsMax(
        uint256 collateralRatio,
        uint256 utilization,
        uint256 tenorDays
    ) public view {
        collateralRatio = bound(collateralRatio, 0, MeridianMath.WAD);
        utilization = bound(utilization, 0, MeridianMath.WAD);
        tenorDays = bound(tenorDays, 0, 3650);

        ShieldPricer.RiskMetrics memory metrics = ShieldPricer.RiskMetrics({
            collateralRatio: collateralRatio,
            utilization: utilization,
            poolTvl: 1_000_000e18,
            poolStatus: IForgeVault.PoolStatus.Active
        });

        uint256 spread = pricer.calculateSpread(metrics, defaultParams, 1_000_000e18, tenorDays);
        assertLe(spread, defaultParams.maxSpreadBps, "Spread should never exceed max");
    }
}

// ============================================================
// CreditEventOracle Tests
// ============================================================

contract CreditEventOracleTest is Test {
    CreditEventOracle oracle;
    address admin;
    address reporter = makeAddr("reporter");
    address vault = makeAddr("vault");

    function setUp() public {
        admin = address(this);
        oracle = new CreditEventOracle();
    }

    function test_reportCreditEvent_asOwner() public {
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Impairment, 100e18);

        assertTrue(oracle.hasActiveEvent(vault));
        ICreditEventOracle.CreditEvent memory evt = oracle.getLatestEvent(vault);
        assertEq(uint256(evt.eventType), uint256(ICreditEventOracle.EventType.Impairment));
        assertEq(evt.lossAmount, 100e18);
        assertEq(evt.reporter, admin);
    }

    function test_reportCreditEvent_asReporter() public {
        oracle.setReporter(reporter, true);

        vm.prank(reporter);
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 500e18);

        assertTrue(oracle.hasActiveEvent(vault));
        ICreditEventOracle.CreditEvent memory evt = oracle.getLatestEvent(vault);
        assertEq(uint256(evt.eventType), uint256(ICreditEventOracle.EventType.Default));
        assertEq(evt.reporter, reporter);
    }

    function test_reportCreditEvent_revert_unauthorized() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert("CreditEventOracle: not authorized");
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Impairment, 0);
    }

    function test_reportCreditEvent_revert_noneType() public {
        vm.expectRevert("CreditEventOracle: invalid event type");
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.None, 0);
    }

    function test_reportCreditEvent_revert_zeroVault() public {
        vm.expectRevert("CreditEventOracle: zero vault");
        oracle.reportCreditEvent(address(0), ICreditEventOracle.EventType.Default, 0);
    }

    function test_eventHistory() public {
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Impairment, 50e18);
        vm.warp(block.timestamp + 1 days);
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 200e18);

        assertEq(oracle.getEventCount(vault), 2);

        ICreditEventOracle.CreditEvent[] memory history = oracle.getEventHistory(vault);
        assertEq(uint256(history[0].eventType), uint256(ICreditEventOracle.EventType.Impairment));
        assertEq(uint256(history[1].eventType), uint256(ICreditEventOracle.EventType.Default));
    }

    function test_clearEvent() public {
        oracle.reportCreditEvent(vault, ICreditEventOracle.EventType.Default, 100e18);
        assertTrue(oracle.hasActiveEvent(vault));

        oracle.clearEvent(vault);
        assertFalse(oracle.hasActiveEvent(vault));
    }

    function test_clearEvent_revert_notOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        oracle.clearEvent(vault);
    }

    function test_setThreshold() public {
        oracle.setThreshold(vault, 9e17); // 90%
        assertEq(oracle.thresholds(vault), 9e17);
    }

    function test_setReporter_toggle() public {
        oracle.setReporter(reporter, true);
        assertTrue(oracle.isReporter(reporter));

        oracle.setReporter(reporter, false);
        assertFalse(oracle.isReporter(reporter));
    }

    function test_hasActiveEvent_default_false() public view {
        assertFalse(oracle.hasActiveEvent(vault));
    }
}

// ============================================================
// CDSContract Tests
// ============================================================

contract CDSContractTest is Test {
    CDSContract cds;
    CreditEventOracle oracle;
    MockYieldSource collateral;

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address refAsset = makeAddr("referenceAsset");

    uint256 constant NOTIONAL = 1_000_000e18;
    uint256 constant PREMIUM_RATE = 200; // 2% annual
    uint256 constant YEAR = 365 days;

    function setUp() public {
        collateral = new MockYieldSource("Mock USDC", "mUSDC", 18);
        oracle = new CreditEventOracle();

        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: refAsset,
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral)
        });

        cds = new CDSContract(terms, address(oracle), 30 days, address(this));

        // Fund participants
        collateral.mint(buyer, 100_000e18);
        collateral.mint(seller, 2_000_000e18);

        vm.prank(buyer);
        collateral.approve(address(cds), type(uint256).max);
        vm.prank(seller);
        collateral.approve(address(cds), type(uint256).max);
    }

    // --- Constructor ---

    function test_constructor_setsTerms() public view {
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Active));
        assertEq(address(cds.oracle()), address(oracle));
        assertEq(address(cds.collateralToken()), address(collateral));
    }

    function test_constructor_revert_zeroRefAsset() public {
        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: address(0),
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral)
        });
        vm.expectRevert("CDSContract: zero ref asset");
        new CDSContract(terms, address(oracle), 30 days, address(this));
    }

    function test_constructor_revert_zeroNotional() public {
        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: refAsset,
            protectionAmount: 0,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral)
        });
        vm.expectRevert("CDSContract: zero notional");
        new CDSContract(terms, address(oracle), 30 days, address(this));
    }

    function test_constructor_revert_maturityPassed() public {
        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: refAsset,
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp - 1,
            collateralToken: address(collateral)
        });
        vm.expectRevert("CDSContract: maturity passed");
        new CDSContract(terms, address(oracle), 30 days, address(this));
    }

    // --- Buy Protection ---

    function test_buyProtection_success() public {
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        assertEq(cds.buyer(), buyer);
        assertGt(cds.buyerPremiumDeposit(), 0);
    }

    function test_buyProtection_revert_alreadySet() public {
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        address buyer2 = makeAddr("buyer2");
        collateral.mint(buyer2, 100_000e18);
        vm.prank(buyer2);
        collateral.approve(address(cds), type(uint256).max);

        vm.prank(buyer2);
        vm.expectRevert("CDSContract: buyer already set");
        cds.buyProtection(NOTIONAL, 100_000e18);
    }

    function test_buyProtection_revert_amountMismatch() public {
        vm.prank(buyer);
        vm.expectRevert("CDSContract: amount mismatch");
        cds.buyProtection(NOTIONAL + 1, 100_000e18);
    }

    function test_buyProtection_revert_premiumExceedsMax() public {
        vm.prank(buyer);
        vm.expectRevert("CDSContract: premium exceeds max");
        cds.buyProtection(NOTIONAL, 1); // maxPremium too low
    }

    // --- Sell Protection ---

    function test_sellProtection_success() public {
        vm.prank(seller);
        cds.sellProtection(NOTIONAL);

        assertEq(cds.seller(), seller);
        assertEq(cds.collateralPosted(), NOTIONAL);
        assertEq(collateral.balanceOf(address(cds)), NOTIONAL);
    }

    function test_sellProtection_excessCollateral() public {
        uint256 excess = NOTIONAL + 500_000e18;
        vm.prank(seller);
        cds.sellProtection(excess);

        assertEq(cds.collateralPosted(), excess);
    }

    function test_sellProtection_revert_insufficient() public {
        vm.prank(seller);
        vm.expectRevert("CDSContract: insufficient collateral");
        cds.sellProtection(NOTIONAL - 1);
    }

    function test_sellProtection_revert_alreadySet() public {
        vm.prank(seller);
        cds.sellProtection(NOTIONAL);

        address seller2 = makeAddr("seller2");
        collateral.mint(seller2, NOTIONAL);
        vm.prank(seller2);
        collateral.approve(address(cds), type(uint256).max);

        vm.prank(seller2);
        vm.expectRevert("CDSContract: seller already set");
        cds.sellProtection(NOTIONAL);
    }

    // --- Pay Premium ---

    function test_payPremium_streamsToSeller() public {
        _setupFullCDS();

        // Advance 90 days
        vm.warp(block.timestamp + 90 days);

        uint256 sellerBefore = collateral.balanceOf(seller);
        cds.payPremium();
        uint256 sellerAfter = collateral.balanceOf(seller);

        uint256 premiumPaid = sellerAfter - sellerBefore;
        assertGt(premiumPaid, 0, "Seller should receive premium");

        // ~90 days of 2% on 1M = ~4,931
        assertApproxEqRel(premiumPaid, 4_931e18, 5e15, "~90 days premium");
    }

    function test_payPremium_revert_incomplete() public {
        // Only buyer, no seller
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        vm.warp(block.timestamp + 30 days);
        vm.expectRevert("CDSContract: incomplete");
        cds.payPremium();
    }

    function test_payPremium_revert_noPremiumDue() public {
        _setupFullCDS();

        // No time elapsed
        vm.expectRevert("CDSContract: no premium due");
        cds.payPremium();
    }

    // --- Trigger Credit Event ---

    function test_triggerCreditEvent_success() public {
        _setupFullCDS();

        // Report credit event via oracle
        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);

        cds.triggerCreditEvent();
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Triggered));
    }

    function test_triggerCreditEvent_revert_noEvent() public {
        _setupFullCDS();

        vm.expectRevert("CDSContract: no credit event");
        cds.triggerCreditEvent();
    }

    function test_triggerCreditEvent_revert_incomplete() public {
        // Only buyer
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);

        vm.expectRevert("CDSContract: incomplete");
        cds.triggerCreditEvent();
    }

    // --- Settle ---

    function test_settle_fullPayout() public {
        _setupFullCDS();

        // Trigger immediately (no premium accrued)
        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);
        cds.triggerCreditEvent();

        uint256 premiumDeposit = cds.buyerPremiumDeposit();
        uint256 buyerBefore = collateral.balanceOf(buyer);

        // Settle
        cds.settle();
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Settled));

        uint256 buyerTotal = collateral.balanceOf(buyer) - buyerBefore;
        // Buyer receives: protection payout (notional) + refunded premium deposit
        assertEq(buyerTotal, NOTIONAL + premiumDeposit, "Payout + premium refund");
    }

    function test_settle_returnExcessCollateral() public {
        // Seller posts 1.5M for 1M protection
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);
        vm.prank(seller);
        cds.sellProtection(1_500_000e18);

        // Trigger and settle
        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);
        cds.triggerCreditEvent();

        uint256 sellerBefore = collateral.balanceOf(seller);
        cds.settle();

        uint256 sellerRecovered = collateral.balanceOf(seller) - sellerBefore;
        // Seller gets excess collateral (500k) + any accrued premium
        assertGe(sellerRecovered, 500_000e18, "Seller recovers excess collateral");
    }

    function test_settle_refundsUnusedPremium() public {
        _setupFullCDS();

        // Trigger immediately (no time passes, no premium accrued)
        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);
        cds.triggerCreditEvent();

        uint256 premiumDeposit = cds.buyerPremiumDeposit();
        uint256 buyerBefore = collateral.balanceOf(buyer);
        cds.settle();

        uint256 buyerTotal = collateral.balanceOf(buyer) - buyerBefore;
        // Buyer gets protection payout + unused premium refund
        assertEq(buyerTotal, NOTIONAL + premiumDeposit, "Payout + premium refund");
    }

    function test_settle_revert_notTriggered() public {
        _setupFullCDS();

        vm.expectRevert("CDSContract: not triggered");
        cds.settle();
    }

    // --- Expire ---

    function test_expire_returnsCollateralToSeller() public {
        _setupFullCDS();

        vm.warp(block.timestamp + YEAR);

        uint256 sellerBefore = collateral.balanceOf(seller);
        cds.expire();

        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Expired));

        uint256 sellerRecovered = collateral.balanceOf(seller) - sellerBefore;
        // Seller gets collateral back + full premium
        assertGe(sellerRecovered, NOTIONAL, "Seller recovers collateral");
    }

    function test_expire_paysFinalPremium() public {
        _setupFullCDS();
        vm.warp(block.timestamp + YEAR);

        uint256 sellerBefore = collateral.balanceOf(seller);
        cds.expire();

        uint256 sellerGot = collateral.balanceOf(seller) - sellerBefore;
        // Seller gets collateral (1M) + full premium (~20k)
        assertGt(sellerGot, NOTIONAL, "Seller gets collateral + premium");
        assertApproxEqRel(sellerGot - NOTIONAL, 20_000e18, 5e15, "Premium ~20k");
    }

    function test_expire_refundsUnusedPremiumToBuyer() public {
        _setupFullCDS();

        // Expire at half term
        vm.warp(block.timestamp + YEAR / 2);

        // Need maturity to pass for expire — adjust test: warp to maturity
        vm.warp(block.timestamp + YEAR); // well past maturity

        uint256 buyerBefore = collateral.balanceOf(buyer);
        cds.expire();

        // Buyer should get some refund (unused premium deposit after full premium paid)
        // Full premium was deposited upfront and should cover 1 year exactly
        // So any remaining deposit is refunded
        uint256 buyerRefund = collateral.balanceOf(buyer) - buyerBefore;
        // After full year's premium is paid, refund should be near 0
        // (since full premium was exactly enough for the term)
        assertLe(buyerRefund, 1e18, "Refund near zero after full term");
    }

    function test_expire_revert_notMatured() public {
        _setupFullCDS();

        vm.expectRevert("CDSContract: not matured");
        cds.expire();
    }

    function test_expire_revert_notActive() public {
        _setupFullCDS();

        oracle.reportCreditEvent(refAsset, ICreditEventOracle.EventType.Default, NOTIONAL);
        cds.triggerCreditEvent();

        vm.warp(block.timestamp + YEAR);
        vm.expectRevert("CDSContract: not active");
        cds.expire();
    }

    // --- View Functions ---

    function test_getAccruedPremium() public {
        _setupFullCDS();

        vm.warp(block.timestamp + 30 days);
        uint256 accrued = cds.getAccruedPremium();
        assertGt(accrued, 0);
    }

    function test_isFullyMatched() public {
        assertFalse(cds.isFullyMatched());

        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);
        assertFalse(cds.isFullyMatched());

        vm.prank(seller);
        cds.sellProtection(NOTIONAL);
        assertTrue(cds.isFullyMatched());
    }

    function test_timeToMaturity() public {
        uint256 ttm = cds.timeToMaturity();
        assertApproxEqAbs(ttm, YEAR, 2);

        vm.warp(block.timestamp + YEAR / 2);
        assertApproxEqAbs(cds.timeToMaturity(), YEAR / 2, 2);

        vm.warp(block.timestamp + YEAR);
        assertEq(cds.timeToMaturity(), 0);
    }

    // --- Fuzz Tests ---

    function testFuzz_premiumDeposit_matchesCalculation(
        uint256 premiumRate,
        uint256 durationDays
    ) public {
        premiumRate = bound(premiumRate, 1, 5000);
        durationDays = bound(durationDays, 1, 3650);
        uint256 maturity = block.timestamp + durationDays * 1 days;

        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: refAsset,
            protectionAmount: NOTIONAL,
            premiumRate: premiumRate,
            maturity: maturity,
            collateralToken: address(collateral)
        });

        CDSContract newCds = new CDSContract(terms, address(oracle), 30 days, address(this));

        // Calculate expected premium
        uint256 actualDurationDays = (maturity - block.timestamp) / 1 days;
        uint256 expectedPremium = PremiumEngine.calculateTotalPremium(
            NOTIONAL, premiumRate, actualDurationDays
        );

        // Give buyer enough
        collateral.mint(buyer, expectedPremium + 1e18);
        vm.prank(buyer);
        collateral.approve(address(newCds), type(uint256).max);

        if (expectedPremium > 0) {
            vm.prank(buyer);
            newCds.buyProtection(NOTIONAL, expectedPremium + 1e18);
            assertEq(newCds.buyerPremiumDeposit(), expectedPremium);
        }
    }

    // --- Helpers ---

    function _setupFullCDS() internal {
        vm.prank(buyer);
        cds.buyProtection(NOTIONAL, 100_000e18);
        vm.prank(seller);
        cds.sellProtection(NOTIONAL);
    }
}

// ============================================================
// ShieldFactory Tests
// ============================================================

contract ShieldFactoryTest is Test {
    ShieldFactory factory;
    CreditEventOracle oracle;
    MockYieldSource collateral;
    address refAsset = makeAddr("referenceAsset");
    address creator = makeAddr("creator");

    uint256 constant YEAR = 365 days;

    function setUp() public {
        factory = new ShieldFactory();
        oracle = new CreditEventOracle();
        collateral = new MockYieldSource("Mock USDC", "mUSDC", 18);
    }

    function test_createCDS() public {
        vm.prank(creator);
        address cdsAddr = factory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: refAsset,
            protectionAmount: 1_000_000e18,
            premiumRate: 200,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral),
            oracle: address(oracle),
            paymentInterval: 30 days
        }));

        assertEq(factory.cdsCount(), 1);
        assertEq(factory.getCDS(0), cdsAddr);
        assertTrue(cdsAddr != address(0));

        CDSContract cds = CDSContract(cdsAddr);
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Active));
    }

    function test_createCDS_tracksReferenceAsset() public {
        vm.prank(creator);
        factory.createCDS(_defaultParams());

        uint256[] memory ids = factory.getCDSForVault(refAsset);
        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
    }

    function test_createCDS_tracksParticipant() public {
        vm.prank(creator);
        factory.createCDS(_defaultParams());

        uint256[] memory ids = factory.getParticipantCDS(creator);
        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
    }

    function test_createCDS_multipleCDS() public {
        vm.startPrank(creator);
        factory.createCDS(_defaultParams());
        factory.createCDS(_defaultParams());
        factory.createCDS(_defaultParams());
        vm.stopPrank();

        assertEq(factory.cdsCount(), 3);
        assertEq(factory.getParticipantCDS(creator).length, 3);
        assertEq(factory.getCDSForVault(refAsset).length, 3);
    }

    function test_createCDS_differentReferenceAssets() public {
        address refAsset2 = makeAddr("referenceAsset2");

        vm.startPrank(creator);
        factory.createCDS(_defaultParams());

        factory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: refAsset2,
            protectionAmount: 500_000e18,
            premiumRate: 300,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral),
            oracle: address(oracle),
            paymentInterval: 30 days
        }));
        vm.stopPrank();

        assertEq(factory.getCDSForVault(refAsset).length, 1);
        assertEq(factory.getCDSForVault(refAsset2).length, 1);
    }

    function _defaultParams() internal view returns (ShieldFactory.CreateCDSParams memory) {
        return ShieldFactory.CreateCDSParams({
            referenceAsset: refAsset,
            protectionAmount: 1_000_000e18,
            premiumRate: 200,
            maturity: block.timestamp + YEAR,
            collateralToken: address(collateral),
            oracle: address(oracle),
            paymentInterval: 30 days
        });
    }
}

// ============================================================
// Integration Test: Forge Vault Impairment → CDS Settlement
// ============================================================

contract ShieldForgeIntegrationTest is Test {
    // Actors
    address originator = makeAddr("originator");
    address investor = makeAddr("investor");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address cdsBuyer = makeAddr("cdsBuyer");
    address cdsSeller = makeAddr("cdsSeller");

    // Forge contracts
    ForgeFactory forgeFactory;
    ForgeVault vault;
    MockYieldSource underlying;
    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    // Shield contracts
    ShieldFactory shieldFactory;
    CreditEventOracle oracle;
    CDSContract cds;

    uint256 constant POOL_SIZE = 1_000_000e18;
    uint256 constant NOTIONAL = 500_000e18; // CDS covers 500k
    uint256 constant PREMIUM_RATE = 200;    // 2% annual
    uint256 constant YEAR = 365 days;
    uint256 constant WEEK = 7 days;

    function setUp() public {
        // --- Deploy Forge layer ---
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

        // Predict vault address
        uint256 factoryNonce = vm.getNonce(address(forgeFactory));
        address predictedVault = vm.computeCreateAddress(address(forgeFactory), factoryNonce);

        seniorToken = new TrancheToken("Senior", "SR", predictedVault, 0);
        mezzToken = new TrancheToken("Mezz", "MZ", predictedVault, 1);
        equityToken = new TrancheToken("Equity", "EQ", predictedVault, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)});
        params[1] = IForgeVault.TrancheParams({targetApr: 800, allocationPct: 20, token: address(mezzToken)});
        params[2] = IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(equityToken)});

        vm.prank(originator);
        address vaultAddr = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(underlying),
                trancheTokenAddresses: [address(seniorToken), address(mezzToken), address(equityToken)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );
        vault = ForgeVault(vaultAddr);

        // --- Deploy Shield layer ---
        oracle = new CreditEventOracle();
        shieldFactory = new ShieldFactory();

        address cdsAddr = shieldFactory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: address(vault),
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            collateralToken: address(underlying),
            oracle: address(oracle),
            paymentInterval: 30 days
        }));
        cds = CDSContract(cdsAddr);

        // --- Fund participants ---
        underlying.mint(investor, POOL_SIZE);
        underlying.mint(cdsBuyer, 100_000e18);
        underlying.mint(cdsSeller, NOTIONAL);

        vm.prank(investor);
        underlying.approve(address(vault), type(uint256).max);
        vm.prank(cdsBuyer);
        underlying.approve(address(cds), type(uint256).max);
        vm.prank(cdsSeller);
        underlying.approve(address(cds), type(uint256).max);
    }

    /// @notice Full happy path: no credit event, CDS expires, everyone profits
    function test_integration_happyPath_noDefault() public {
        // 1. Investor invests in senior tranche
        vm.prank(investor);
        vault.invest(0, POOL_SIZE);

        // 2. CDS buyer buys protection
        vm.prank(cdsBuyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        // 3. CDS seller provides collateral
        vm.prank(cdsSeller);
        cds.sellProtection(NOTIONAL);

        // 4. Time passes, premiums stream
        vm.warp(block.timestamp + 90 days);
        cds.payPremium();

        // Seller received some premium
        assertGt(underlying.balanceOf(cdsSeller), 0, "Seller earned premium");

        // 5. Yield flows into vault
        underlying.mint(address(vault), 100_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();

        // 6. CDS expires at maturity
        vm.warp(block.timestamp + YEAR);
        cds.expire();

        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Expired));

        // Seller got collateral back + premium
        assertGt(underlying.balanceOf(cdsSeller), NOTIONAL, "Seller profits on no-default");
    }

    /// @notice Credit event: vault impaired → oracle reports → CDS triggered → settled
    function test_integration_creditEvent_fullSettlement() public {
        // 1. Setup positions
        vm.prank(investor);
        vault.invest(0, POOL_SIZE);

        vm.prank(cdsBuyer);
        cds.buyProtection(NOTIONAL, 100_000e18);

        vm.prank(cdsSeller);
        cds.sellProtection(NOTIONAL);

        // 2. Some time passes, premiums flow
        vm.warp(block.timestamp + 60 days);
        cds.payPremium();

        // 3. Originator marks vault as impaired (simulating credit deterioration)
        vm.prank(originator);
        vault.setPoolStatus(IForgeVault.PoolStatus.Defaulted);

        // 4. Oracle detects and reports credit event
        oracle.reportCreditEvent(
            address(vault),
            ICreditEventOracle.EventType.Default,
            NOTIONAL
        );

        // 5. Anyone can trigger the CDS
        cds.triggerCreditEvent();
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Triggered));

        // 6. Settlement — buyer receives protection payout
        uint256 buyerBefore = underlying.balanceOf(cdsBuyer);
        cds.settle();

        uint256 buyerPayout = underlying.balanceOf(cdsBuyer) - buyerBefore;

        // Buyer should receive notional (protection amount) + unused premium refund
        assertGe(buyerPayout, NOTIONAL, "Buyer receives at least protection amount");
        assertEq(uint256(cds.status()), uint256(ICDSContract.CDSStatus.Settled));
    }

    /// @notice Premium streaming works correctly over multiple periods
    function test_integration_premiumStreaming() public {
        vm.prank(cdsBuyer);
        cds.buyProtection(NOTIONAL, 100_000e18);
        vm.prank(cdsSeller);
        cds.sellProtection(NOTIONAL);

        uint256 totalPremiumPaid;

        // Pay premium every 30 days for 6 months
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(block.timestamp + 30 days);
            uint256 sellerBefore = underlying.balanceOf(cdsSeller);
            cds.payPremium();
            totalPremiumPaid += underlying.balanceOf(cdsSeller) - sellerBefore;
        }

        // After 180 days: expected ~0.98% of 500k = ~4,931 * 2 periods
        // 500k * 200bps * 180/365 = ~4,931
        assertApproxEqRel(totalPremiumPaid, 4_931e18, 5e15, "~180 days of premium");
    }
}
