// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Core contracts
import {HedgeRouter} from "../src/HedgeRouter.sol";
import {IHedgeRouter} from "../src/interfaces/IHedgeRouter.sol";
import {ForgeVault} from "../src/forge/ForgeVault.sol";
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {TrancheToken} from "../src/forge/TrancheToken.sol";
import {CDSContract} from "../src/shield/CDSContract.sol";
import {ShieldFactory} from "../src/shield/ShieldFactory.sol";
import {ShieldPricer} from "../src/shield/ShieldPricer.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {PremiumEngine} from "../src/shield/PremiumEngine.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";
import {ICDSContract} from "../src/interfaces/ICDSContract.sol";
import {ICreditEventOracle} from "../src/interfaces/ICreditEventOracle.sol";

// Mocks
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

// Libraries
import {MeridianMath} from "../src/libraries/MeridianMath.sol";

contract HedgeRouterTest is Test {
    // Actors
    address user = makeAddr("user");
    address originator = makeAddr("originator");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");
    address cdsSeller = makeAddr("cdsSeller");

    // Forge layer
    ForgeFactory forgeFactory;
    ForgeVault vault;
    MockYieldSource underlying;
    TrancheToken seniorToken;
    TrancheToken mezzToken;
    TrancheToken equityToken;

    // Shield layer
    ShieldFactory shieldFactory;
    ShieldPricer pricer;
    CreditEventOracle oracle;
    CDSContract cds;

    // Router
    HedgeRouter router;

    uint256 constant INVEST_AMOUNT = 100_000e18;
    uint256 constant NOTIONAL = 100_000e18;
    uint256 constant PREMIUM_RATE = 200; // 2% annual
    uint256 constant YEAR = 365 days;
    uint256 constant WEEK = 7 days;

    function setUp() public {
        // --- Deploy Forge layer ---
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);

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
        pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));

        // Create a CDS referencing the vault
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

        // --- Deploy Router ---
        router = new HedgeRouter(address(pricer), address(shieldFactory), address(this));

        // --- Fund actors ---
        underlying.mint(user, 1_000_000e18);
        underlying.mint(cdsSeller, NOTIONAL);

        // User approves router for everything
        vm.prank(user);
        underlying.approve(address(router), type(uint256).max);

        // Seller approves CDS for collateral
        vm.prank(cdsSeller);
        underlying.approve(address(cds), type(uint256).max);
    }

    // ============================================================
    // investAndHedge Tests
    // ============================================================

    function test_investAndHedge_atomicExecution() public {
        uint256 maxPremium = 50_000e18; // generous slippage

        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0, // Senior
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: maxPremium
        }));

        // User has tranche tokens
        assertEq(seniorToken.balanceOf(user), INVEST_AMOUNT, "User received senior tokens");

        // User is the CDS buyer
        assertEq(cds.buyer(), user, "User is CDS buyer");

        // Router has no leftover tokens
        assertEq(underlying.balanceOf(address(router)), 0, "Router balance is 0");
    }

    function test_investAndHedge_refundsUnused() public {
        uint256 balanceBefore = underlying.balanceOf(user);
        uint256 maxPremium = 50_000e18;

        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: maxPremium
        }));

        uint256 balanceAfter = underlying.balanceOf(user);

        // User spent investAmount + actual premium (not maxPremium)
        // Actual premium = notional * premiumRate * durationDays / (BPS * 365)
        // ~ 100_000e18 * 200 * 365 / (10_000 * 365) = 2_000e18
        uint256 spent = balanceBefore - balanceAfter;
        uint256 actualPremium = spent - INVEST_AMOUNT;

        // Premium should be ~2000e18 (2% of 100k for 1 year), NOT 50_000
        assertLt(actualPremium, maxPremium, "Refund occurred - didn't charge max");
        assertApproxEqRel(actualPremium, 2_000e18, 0.01e18, "Premium ~2% of notional");
    }

    function test_investAndHedge_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IHedgeRouter.HedgeExecuted(user, address(vault), 0, INVEST_AMOUNT, address(cds));

        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: 50_000e18
        }));
    }

    function test_investAndHedge_mezzanineTranche() public {
        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 1, // Mezzanine
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: 50_000e18
        }));

        assertEq(mezzToken.balanceOf(user), INVEST_AMOUNT, "User received mezz tokens");
        assertEq(cds.buyer(), user, "User is CDS buyer");
    }

    function test_investAndHedge_revert_cdsAlreadyMatched() public {
        // First user buys protection
        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: 50_000e18
        }));

        // Second user tries — should revert
        address user2 = makeAddr("user2");
        underlying.mint(user2, 500_000e18);
        vm.prank(user2);
        underlying.approve(address(router), type(uint256).max);

        vm.expectRevert("CDSContract: buyer already set");
        vm.prank(user2);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: 50_000e18
        }));
    }

    function test_investAndHedge_revert_zeroInvest() public {
        vm.expectRevert("HedgeRouter: zero invest");
        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: 0,
            cds: address(cds),
            maxPremium: 50_000e18
        }));
    }

    // ============================================================
    // createAndHedge Tests
    // ============================================================

    function test_createAndHedge_createsNewCDS() public {
        uint256 cdsBefore = shieldFactory.cdsCount();

        vm.prank(user);
        router.createAndHedge(IHedgeRouter.CreateAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            oracle: address(oracle),
            paymentInterval: 30 days,
            maxPremium: 50_000e18
        }));

        // New CDS was created
        assertEq(shieldFactory.cdsCount(), cdsBefore + 1, "New CDS created");

        // User has tranche tokens
        assertEq(seniorToken.balanceOf(user), INVEST_AMOUNT, "User received tokens");

        // Get the new CDS and verify user is buyer
        address newCDS = shieldFactory.getCDS(cdsBefore);
        assertEq(CDSContract(newCDS).buyer(), user, "User is buyer of new CDS");

        // Router has nothing
        assertEq(underlying.balanceOf(address(router)), 0, "Router balance is 0");
    }

    function test_createAndHedge_emitsEvent() public {
        uint256 expectedCdsId = shieldFactory.cdsCount();
        address expectedCds = vm.computeCreateAddress(address(shieldFactory), vm.getNonce(address(shieldFactory)));

        vm.expectEmit(true, true, false, true);
        emit IHedgeRouter.HedgeCreated(user, address(vault), 0, INVEST_AMOUNT, expectedCds);

        vm.prank(user);
        router.createAndHedge(IHedgeRouter.CreateAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            protectionAmount: NOTIONAL,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            oracle: address(oracle),
            paymentInterval: 30 days,
            maxPremium: 50_000e18
        }));
    }

    // ============================================================
    // quoteHedge Tests
    // ============================================================

    function test_quoteHedge_accuracy() public view {
        (uint256 spreadBps, uint256 estimatedPremium) = router.quoteHedge(address(vault), INVEST_AMOUNT, 365);

        // Spread should be at least baseRate (50 bps) + tenor adjustment (100 * 365/365 = 100)
        assertGe(spreadBps, 150, "Spread >= base + tenor");

        // Premium = notional * spreadBps * days / (BPS * 365)
        uint256 expected = PremiumEngine.calculateTotalPremium(INVEST_AMOUNT, spreadBps, 365);
        assertEq(estimatedPremium, expected, "Premium matches manual calc");
    }

    function test_quoteHedge_shortTenor() public view {
        (uint256 spreadShort,) = router.quoteHedge(address(vault), INVEST_AMOUNT, 30);
        (uint256 spreadLong,) = router.quoteHedge(address(vault), INVEST_AMOUNT, 365);

        // Longer tenor should have higher spread due to tenor adjustment
        assertGt(spreadLong, spreadShort, "Longer tenor = higher spread");
    }

    // ============================================================
    // investFor Standalone Tests
    // ============================================================

    function test_investFor_standalone() public {
        // Approve vault directly
        vm.prank(user);
        underlying.approve(address(vault), INVEST_AMOUNT);

        // Invest for a different beneficiary
        address beneficiary = makeAddr("beneficiary");
        vm.prank(user);
        vault.investFor(0, INVEST_AMOUNT, beneficiary);

        // Beneficiary has the tokens
        assertEq(seniorToken.balanceOf(beneficiary), INVEST_AMOUNT, "Beneficiary has tokens");
        // User does NOT have tokens
        assertEq(seniorToken.balanceOf(user), 0, "User has no tokens");
    }

    function test_investFor_settlesYieldForBeneficiary() public {
        address beneficiary = makeAddr("beneficiary");

        // First invest directly so beneficiary has shares
        underlying.mint(beneficiary, INVEST_AMOUNT);
        vm.prank(beneficiary);
        underlying.approve(address(vault), INVEST_AMOUNT);
        vm.prank(beneficiary);
        vault.invest(0, INVEST_AMOUNT);

        // Generate yield and distribute
        underlying.mint(address(vault), 50_000e18);
        vm.warp(block.timestamp + WEEK);
        vault.triggerWaterfall();

        // User does investFor to same beneficiary — should settle yield (accumulate pending)
        vm.prank(user);
        underlying.approve(address(vault), INVEST_AMOUNT);
        vm.prank(user);
        vault.investFor(0, INVEST_AMOUNT, beneficiary);

        // Beneficiary should have 2x tranche tokens
        assertEq(seniorToken.balanceOf(beneficiary), 2 * INVEST_AMOUNT, "Beneficiary has 2x tokens");

        // Yield was settled (accumulated as pending) — beneficiary claims it
        vm.prank(beneficiary);
        uint256 claimed = vault.claimYield(0);
        assertGt(claimed, 0, "Beneficiary claimed settled yield");
    }

    function test_investFor_revert_zeroBeneficiary() public {
        vm.prank(user);
        underlying.approve(address(vault), INVEST_AMOUNT);

        vm.expectRevert("ForgeVault: zero beneficiary");
        vm.prank(user);
        vault.investFor(0, INVEST_AMOUNT, address(0));
    }

    // ============================================================
    // buyProtectionFor Standalone Tests
    // ============================================================

    function test_buyProtectionFor_standalone() public {
        address beneficiary = makeAddr("beneficiary");

        // User pays, beneficiary is buyer
        vm.prank(user);
        underlying.approve(address(cds), 50_000e18);
        vm.prank(user);
        cds.buyProtectionFor(NOTIONAL, 50_000e18, beneficiary);

        assertEq(cds.buyer(), beneficiary, "Beneficiary is buyer");

        // Seller posts collateral
        vm.prank(cdsSeller);
        cds.sellProtection(NOTIONAL);

        // Trigger credit event and settle — payout goes to beneficiary
        oracle.setReporter(address(this), true);
        oracle.reportCreditEvent(address(vault), ICreditEventOracle.EventType.Default, NOTIONAL);

        cds.triggerCreditEvent();
        cds.settle();

        // Beneficiary received settlement payout + unused premium
        assertGt(underlying.balanceOf(beneficiary), 0, "Beneficiary received settlement");
    }

    function test_buyProtectionFor_revert_zeroBeneficiary() public {
        vm.prank(user);
        underlying.approve(address(cds), 50_000e18);

        vm.expectRevert("CDSContract: zero beneficiary");
        vm.prank(user);
        cds.buyProtectionFor(NOTIONAL, 50_000e18, address(0));
    }

    // ============================================================
    // Full Integration: investAndHedge → settle
    // ============================================================

    function test_integration_investAndHedge_thenSettle() public {
        // 1. User invests and hedges atomically
        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: INVEST_AMOUNT,
            cds: address(cds),
            maxPremium: 50_000e18
        }));

        // 2. Seller posts collateral
        vm.prank(cdsSeller);
        cds.sellProtection(NOTIONAL);

        // 3. Credit event occurs
        oracle.setReporter(address(this), true);
        oracle.reportCreditEvent(address(vault), ICreditEventOracle.EventType.Default, NOTIONAL);

        // 4. Trigger and settle
        cds.triggerCreditEvent();

        uint256 balanceBefore = underlying.balanceOf(user);
        cds.settle();

        // 5. User (buyer) receives settlement payout directly
        uint256 payout = underlying.balanceOf(user) - balanceBefore;
        assertGt(payout, 0, "User received settlement payout");

        // User still has their tranche tokens
        assertEq(seniorToken.balanceOf(user), INVEST_AMOUNT, "User still has tranche tokens");
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function test_fuzz_investAndHedge(uint256 investAmt) public {
        // Bound to reasonable range: 1e18 to 500_000e18
        investAmt = bound(investAmt, 1e18, 500_000e18);

        // Create a CDS matching the invest amount
        address cdsAddr = shieldFactory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: address(vault),
            protectionAmount: investAmt,
            premiumRate: PREMIUM_RATE,
            maturity: block.timestamp + YEAR,
            collateralToken: address(underlying),
            oracle: address(oracle),
            paymentInterval: 30 days
        }));

        // Fund user
        underlying.mint(user, investAmt + 100_000e18); // extra for premium

        uint256 maxPremium = investAmt; // generous max
        uint256 balanceBefore = underlying.balanceOf(user);

        vm.prank(user);
        router.investAndHedge(IHedgeRouter.InvestAndHedgeParams({
            vault: address(vault),
            trancheId: 0,
            investAmount: investAmt,
            cds: cdsAddr,
            maxPremium: maxPremium
        }));

        // User has tranche tokens
        assertEq(seniorToken.balanceOf(user), investAmt, "Tranche tokens match invest");

        // User is buyer
        assertEq(CDSContract(cdsAddr).buyer(), user, "User is buyer");

        // Router is empty
        assertEq(underlying.balanceOf(address(router)), 0, "Router empty");

        // Premium spent is reasonable (< maxPremium)
        uint256 spent = balanceBefore - underlying.balanceOf(user);
        assertLe(spent, investAmt + maxPremium, "Didn't overspend");
    }

    // ============================================================
    // Constructor Tests
    // ============================================================

    function test_constructor_revert_zeroPricer() public {
        vm.expectRevert("HedgeRouter: zero pricer");
        new HedgeRouter(address(0), address(shieldFactory), address(this));
    }

    function test_constructor_revert_zeroFactory() public {
        vm.expectRevert("HedgeRouter: zero factory");
        new HedgeRouter(address(pricer), address(0), address(this));
    }
}
