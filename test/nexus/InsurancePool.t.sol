// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {InsurancePool} from "../../src/nexus/InsurancePool.sol";
import {NexusHub} from "../../src/nexus/NexusHub.sol";
import {CollateralOracle} from "../../src/nexus/CollateralOracle.sol";
import {MockTeleporter} from "../../src/mocks/MockTeleporter.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";
import {IInsurancePool} from "../../src/interfaces/IInsurancePool.sol";

// ============================================================
// InsurancePool Unit Tests
// ============================================================

contract InsurancePoolTest is Test {
    InsurancePool pool;
    MockYieldSource usdc;

    address hub = makeAddr("hub");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner;

    function setUp() public {
        owner = address(this);
        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);
        pool = new InsurancePool(address(usdc), hub, 50); // 0.5% premium rate

        // Fund users
        usdc.mint(alice, 1_000_000e18);
        usdc.mint(bob, 1_000_000e18);
        usdc.mint(hub, 1_000_000e18);

        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
    }

    // --- Constructor ---

    function test_constructor_setsParams() public view {
        assertEq(address(pool.reserveToken()), address(usdc));
        assertEq(pool.nexusHub(), hub);
        assertEq(pool.premiumRateBps(), 50);
    }

    function test_constructor_revert_zeroToken() public {
        vm.expectRevert("InsurancePool: zero token");
        new InsurancePool(address(0), hub, 50);
    }

    function test_constructor_revert_rateTooHigh() public {
        vm.expectRevert("InsurancePool: rate > 10%");
        new InsurancePool(address(usdc), hub, 1001);
    }

    // --- Deposit ---

    function test_deposit_happyPath() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        assertEq(pool.deposits(alice), 100_000e18);
        assertEq(pool.totalDeposited(), 100_000e18);
        assertEq(pool.totalReserves(), 100_000e18);
        assertEq(usdc.balanceOf(address(pool)), 100_000e18);
    }

    function test_deposit_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IInsurancePool.Deposited(alice, 100_000e18);
        vm.prank(alice);
        pool.deposit(100_000e18);
    }

    function test_deposit_multipleDepositors() public {
        vm.prank(alice);
        pool.deposit(100_000e18);
        vm.prank(bob);
        pool.deposit(50_000e18);

        assertEq(pool.totalDeposited(), 150_000e18);
        assertEq(pool.totalReserves(), 150_000e18);
    }

    function test_deposit_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("InsurancePool: zero amount");
        pool.deposit(0);
    }

    // --- Withdraw ---

    function test_withdraw_happyPath() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.prank(alice);
        pool.withdraw(50_000e18);

        assertEq(pool.deposits(alice), 50_000e18);
        assertEq(pool.totalReserves(), 50_000e18);
    }

    function test_withdraw_proRataAfterShortfall() public {
        // Alice deposits 100k, bob deposits 100k
        vm.prank(alice);
        pool.deposit(100_000e18);
        vm.prank(bob);
        pool.deposit(100_000e18);

        // Pool absorbs 50k shortfall → 200k deposited, 150k reserves
        vm.prank(hub);
        pool.coverShortfall(makeAddr("user"), 50_000e18);

        assertEq(pool.totalReserves(), 150_000e18);

        // Alice's effective balance = 100k * 150k / 200k = 75k
        assertEq(pool.getEffectiveBalance(alice), 75_000e18);

        // Alice withdraws full deposit (100k), but only gets 75k
        vm.prank(alice);
        pool.withdraw(100_000e18);

        assertEq(usdc.balanceOf(alice), 900_000e18 + 75_000e18); // started with 1M, deposited 100k, got 75k back
    }

    function test_withdraw_revert_insufficientDeposit() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.prank(alice);
        vm.expectRevert("InsurancePool: insufficient deposit");
        pool.withdraw(200_000e18);
    }

    function test_withdraw_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("InsurancePool: zero amount");
        pool.withdraw(0);
    }

    // --- Cover Shortfall ---

    function test_coverShortfall_fullCoverage() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.prank(hub);
        uint256 covered = pool.coverShortfall(makeAddr("user"), 30_000e18);

        assertEq(covered, 30_000e18);
        assertEq(pool.totalReserves(), 70_000e18);
        assertEq(pool.totalCovered(), 30_000e18);
        assertEq(usdc.balanceOf(hub), 1_000_000e18 + 30_000e18);
    }

    function test_coverShortfall_partialCoverage() public {
        vm.prank(alice);
        pool.deposit(20_000e18);

        vm.prank(hub);
        uint256 covered = pool.coverShortfall(makeAddr("user"), 50_000e18);

        assertEq(covered, 20_000e18); // Can only cover what's available
        assertEq(pool.totalReserves(), 0);
    }

    function test_coverShortfall_zeroReserves() public {
        vm.prank(hub);
        uint256 covered = pool.coverShortfall(makeAddr("user"), 50_000e18);

        assertEq(covered, 0);
    }

    function test_coverShortfall_emitsEvent() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.expectEmit(true, false, false, true);
        emit IInsurancePool.ShortfallCovered(makeAddr("user"), 30_000e18, 30_000e18);
        vm.prank(hub);
        pool.coverShortfall(makeAddr("user"), 30_000e18);
    }

    function test_coverShortfall_revert_notHub() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.prank(alice);
        vm.expectRevert("InsurancePool: not hub");
        pool.coverShortfall(makeAddr("user"), 10_000e18);
    }

    // --- Collect Premium ---

    function test_collectPremium_happyPath() public {
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);

        pool.collectPremium(alice, 100_000e18); // 0.5% of 100k = 500

        assertEq(pool.totalPremiumsCollected(), 500e18);
        assertEq(pool.totalReserves(), 500e18);
    }

    function test_collectPremium_zeroRate() public {
        pool.setPremiumRate(0);

        uint256 balBefore = usdc.balanceOf(alice);
        pool.collectPremium(alice, 100_000e18);

        assertEq(usdc.balanceOf(alice), balBefore); // No transfer
    }

    // --- Admin ---

    function test_setPremiumRate_happyPath() public {
        pool.setPremiumRate(100);
        assertEq(pool.premiumRateBps(), 100);
    }

    function test_setPremiumRate_revert_tooHigh() public {
        vm.expectRevert("InsurancePool: rate > 10%");
        pool.setPremiumRate(1001);
    }

    function test_setNexusHub_happyPath() public {
        address newHub = makeAddr("newHub");
        pool.setNexusHub(newHub);
        assertEq(pool.nexusHub(), newHub);
    }

    // --- View ---

    function test_getEffectiveBalance_noLosses() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        assertEq(pool.getEffectiveBalance(alice), 100_000e18);
    }

    function test_getEffectiveBalance_afterLoss() public {
        vm.prank(alice);
        pool.deposit(100_000e18);

        vm.prank(hub);
        pool.coverShortfall(makeAddr("user"), 40_000e18);

        assertEq(pool.getEffectiveBalance(alice), 60_000e18);
    }

    function test_getEffectiveBalance_noDeposit() public view {
        assertEq(pool.getEffectiveBalance(alice), 0);
    }

    // --- Fuzz ---

    function testFuzz_depositWithdraw_proRata(uint256 deposit, uint256 shortfall) public {
        deposit = bound(deposit, 1e18, 1_000_000e18);
        shortfall = bound(shortfall, 0, deposit - 1); // Leave at least 1 wei in reserves

        vm.prank(alice);
        pool.deposit(deposit);

        if (shortfall > 0) {
            vm.prank(hub);
            pool.coverShortfall(makeAddr("user"), shortfall);
        }

        uint256 effectiveBalance = pool.getEffectiveBalance(alice);
        assertEq(effectiveBalance, deposit - shortfall);

        vm.prank(alice);
        pool.withdraw(deposit);

        // Pool should be empty
        assertEq(pool.totalReserves(), 0);
    }
}

// ============================================================
// NexusHub + InsurancePool Integration Tests
// ============================================================

contract InsurancePoolIntegrationTest is Test {
    NexusHub hub;
    InsurancePool insurancePool;
    CollateralOracle oracle;
    MockTeleporter teleporter;
    MockYieldSource usdc;

    address alice = makeAddr("alice");
    address liquidator = makeAddr("liquidator");
    address insuranceDepositor = makeAddr("insuranceDepositor");

    bytes32 constant CCHAIN_ID = bytes32(uint256(43113));

    function setUp() public {
        oracle = new CollateralOracle();
        teleporter = new MockTeleporter(CCHAIN_ID);

        hub = new NexusHub(
            address(oracle),
            address(teleporter),
            11e17, // 110% liquidation threshold
            500    // 5% penalty
        );

        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);
        oracle.registerAsset(address(usdc), 1e18, 10000); // $1, 100% weight (simplify math)

        insurancePool = new InsurancePool(address(usdc), address(hub), 50);
        hub.setInsurancePool(address(insurancePool));

        // Fund accounts
        usdc.mint(alice, 100_000e18);
        usdc.mint(insuranceDepositor, 500_000e18);

        vm.prank(alice);
        usdc.approve(address(hub), type(uint256).max);
        vm.prank(insuranceDepositor);
        usdc.approve(address(insurancePool), type(uint256).max);

        // Seed insurance pool
        vm.prank(insuranceDepositor);
        insurancePool.deposit(200_000e18);
    }

    function test_integration_liquidationShortfall_coveredByInsurance() public {
        // Alice deposits 5k USDC, obligation set to 8k (underwater)
        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 5_000e18);
        hub.setObligation(alice, 8_000e18);

        assertFalse(hub.isHealthy(alice));

        // Liquidate: seize 5k collateral, obligation = 8k
        // totalSeized value = 5000 (since collateral < seizureTarget)
        // shortfall = 8000 - 5000 = 3000
        // Insurance covers 3000
        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        assertEq(hub.obligations(alice), 0);
        assertEq(insurancePool.totalReserves(), 200_000e18 - 3_000e18);
        assertEq(insurancePool.totalCovered(), 3_000e18);
    }

    function test_integration_liquidationShortfall_partialCoverage() public {
        // Drain insurance pool first
        InsurancePool smallPool = new InsurancePool(address(usdc), address(hub), 0);
        hub.setInsurancePool(address(smallPool));

        // Seed small pool with only 1k
        usdc.mint(address(this), 1_000e18);
        usdc.approve(address(smallPool), 1_000e18);
        smallPool.deposit(1_000e18);

        // Alice deposits 5k, obligation 8k
        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 5_000e18);
        hub.setObligation(alice, 8_000e18);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        // shortfall = 3000, insurance covers 1000, remaining = 2000
        assertEq(hub.obligations(alice), 2_000e18);
    }

    function test_integration_liquidationNoShortfall_insuranceUntouched() public {
        // Alice deposits 10k, obligation 9.5k — unhealthy but enough collateral to cover
        // margin ratio = 10000/9500 ≈ 1.053 < 1.1 threshold → unhealthy
        // seizureTarget = 9500 + penalty → collateral sufficient → totalSeized >= obligation
        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);
        hub.setObligation(alice, 9_500e18);

        assertFalse(hub.isHealthy(alice));

        uint256 insuranceBefore = insurancePool.totalReserves();

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        assertEq(hub.obligations(alice), 0);
        assertEq(insurancePool.totalReserves(), insuranceBefore); // Untouched
    }

    function test_integration_noInsurancePool_gracefulDegradation() public {
        // Remove insurance pool
        hub.setInsurancePool(address(0));

        // Alice deposits 5k, obligation 8k — shortfall with no insurance
        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 5_000e18);
        hub.setObligation(alice, 8_000e18);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        // No insurance pool → obligations cleared (original behavior preserved)
        // Protocol absorbs the loss — same as pre-insurance behavior
        assertEq(hub.obligations(alice), 0);
    }

    function testFuzz_integration_shortfallCoverage(uint256 collateral, uint256 obligation) public {
        collateral = bound(collateral, 1e18, 50_000e18);
        obligation = bound(obligation, collateral + 1e18, 100_000e18); // Ensure underwater

        usdc.mint(alice, collateral);
        vm.prank(alice);
        usdc.approve(address(hub), type(uint256).max);

        vm.prank(alice);
        hub.openMarginAccount();
        vm.prank(alice);
        hub.depositCollateral(address(usdc), collateral);
        hub.setObligation(alice, obligation);

        if (hub.isHealthy(alice)) return; // Skip if somehow healthy

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        // Obligations should be reduced by insurance coverage
        uint256 shortfall = obligation - collateral;
        uint256 insuranceCoverage = MeridianMath.min(shortfall, 200_000e18);
        if (shortfall <= insuranceCoverage) {
            assertEq(hub.obligations(alice), 0);
        } else {
            assertEq(hub.obligations(alice), shortfall - insuranceCoverage);
        }
    }
}
