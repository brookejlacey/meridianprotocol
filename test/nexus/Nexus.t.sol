// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Nexus contracts
import {CollateralOracle} from "../../src/nexus/CollateralOracle.sol";
import {NexusHub} from "../../src/nexus/NexusHub.sol";
import {NexusVault} from "../../src/nexus/NexusVault.sol";
import {MockTeleporter} from "../../src/mocks/MockTeleporter.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

// Libraries
import {MarginAccount} from "../../src/libraries/MarginAccount.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

// Interfaces
import {INexusHub} from "../../src/interfaces/INexusHub.sol";
import {INexusVault} from "../../src/interfaces/INexusVault.sol";

// ============================================================
// CollateralOracle Tests
// ============================================================

contract CollateralOracleTest is Test {
    CollateralOracle oracle;

    address usdc = makeAddr("usdc");
    address avax = makeAddr("avax");
    address seniorTranche = makeAddr("seniorTranche");

    function setUp() public {
        oracle = new CollateralOracle();

        // Register assets
        oracle.registerAsset(usdc, 1e18, 9500);         // $1, 95% weight
        oracle.registerAsset(avax, 25e18, 7000);         // $25, 70% weight
        oracle.registerAsset(seniorTranche, 1e18, 8500); // $1, 85% weight
    }

    function test_registerAsset() public view {
        assertTrue(oracle.isSupported(usdc));
        assertEq(oracle.prices(usdc), 1e18);
        assertEq(oracle.riskWeights(usdc), 9500);
    }

    function test_getPrice() public view {
        assertEq(oracle.getPrice(usdc), 1e18);
        assertEq(oracle.getPrice(avax), 25e18);
    }

    function test_getRiskWeight() public view {
        assertEq(oracle.getRiskWeight(usdc), 9500);
        assertEq(oracle.getRiskWeight(avax), 7000);
    }

    function test_getCollateralValue_usdc() public view {
        // 1000 USDC at $1, 95% weight = $950
        uint256 val = oracle.getCollateralValue(usdc, 1000e18);
        assertEq(val, 950e18);
    }

    function test_getCollateralValue_avax() public view {
        // 100 AVAX at $25, 70% weight = $1,750
        uint256 val = oracle.getCollateralValue(avax, 100e18);
        assertEq(val, 1750e18);
    }

    function test_getCollateralValue_seniorTranche() public view {
        // 10,000 Senior at $1, 85% weight = $8,500
        uint256 val = oracle.getCollateralValue(seniorTranche, 10_000e18);
        assertEq(val, 8500e18);
    }

    function test_getRawValue() public view {
        // 100 AVAX at $25 = $2,500 (no risk adjustment)
        uint256 val = oracle.getRawValue(avax, 100e18);
        assertEq(val, 2500e18);
    }

    function test_setPrice() public {
        oracle.setPrice(avax, 30e18);
        assertEq(oracle.getPrice(avax), 30e18);
    }

    function test_setRiskWeight() public {
        oracle.setRiskWeight(avax, 8000);
        assertEq(oracle.getRiskWeight(avax), 8000);
    }

    function test_registerAsset_revert_zeroAddress() public {
        vm.expectRevert("CollateralOracle: zero address");
        oracle.registerAsset(address(0), 1e18, 9500);
    }

    function test_registerAsset_revert_zeroPrice() public {
        vm.expectRevert("CollateralOracle: zero price");
        oracle.registerAsset(makeAddr("x"), 0, 9500);
    }

    function test_registerAsset_revert_weightTooHigh() public {
        vm.expectRevert("CollateralOracle: weight > 100%");
        oracle.registerAsset(makeAddr("x"), 1e18, 10001);
    }

    function test_getPrice_revert_unregistered() public {
        vm.expectRevert("CollateralOracle: not registered");
        oracle.getPrice(makeAddr("unknown"));
    }

    function test_batchRegister() public {
        address[] memory assets = new address[](2);
        uint256[] memory prices_ = new uint256[](2);
        uint256[] memory weights = new uint256[](2);

        assets[0] = makeAddr("token1");
        assets[1] = makeAddr("token2");
        prices_[0] = 5e18;
        prices_[1] = 10e18;
        weights[0] = 6000;
        weights[1] = 4000;

        oracle.registerAssets(assets, prices_, weights);

        assertTrue(oracle.isSupported(assets[0]));
        assertTrue(oracle.isSupported(assets[1]));
        assertEq(oracle.getPrice(assets[0]), 5e18);
        assertEq(oracle.getRiskWeight(assets[1]), 4000);
    }

    function test_onlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        oracle.registerAsset(makeAddr("x"), 1e18, 5000);
    }
}

// ============================================================
// MarginAccount Library Tests
// ============================================================

contract MarginAccountTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant THRESHOLD_110 = 11e17; // 110%

    function test_marginRatio_basic() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1500e18,
            borrowValue: 1000e18
        });
        uint256 ratio = MarginAccount.marginRatio(pos);
        assertEq(ratio, 15e17, "1500/1000 = 150%");
    }

    function test_marginRatio_noBorrow() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1000e18,
            borrowValue: 0
        });
        assertEq(MarginAccount.marginRatio(pos), type(uint256).max);
    }

    function test_marginRatio_undercollateralized() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 800e18,
            borrowValue: 1000e18
        });
        uint256 ratio = MarginAccount.marginRatio(pos);
        assertEq(ratio, 8e17, "800/1000 = 80%");
    }

    function test_isHealthy_healthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1200e18,
            borrowValue: 1000e18
        });
        assertTrue(MarginAccount.isHealthy(pos, THRESHOLD_110), "120% > 110%");
    }

    function test_isHealthy_atThreshold() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1100e18,
            borrowValue: 1000e18
        });
        // At exactly 110% — NOT healthy (must be strictly greater than threshold)
        assertFalse(MarginAccount.isHealthy(pos, THRESHOLD_110));
    }

    function test_isHealthy_unhealthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1050e18,
            borrowValue: 1000e18
        });
        assertFalse(MarginAccount.isHealthy(pos, THRESHOLD_110), "105% < 110%");
    }

    function test_isHealthy_noBorrow() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 0,
            borrowValue: 0
        });
        assertTrue(MarginAccount.isHealthy(pos, THRESHOLD_110), "No borrows = healthy");
    }

    function test_shortfall_healthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1200e18,
            borrowValue: 1000e18
        });
        assertEq(MarginAccount.shortfall(pos, THRESHOLD_110), 0, "No shortfall when healthy");
    }

    function test_shortfall_unhealthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1000e18,
            borrowValue: 1000e18
        });
        // Required = 1000 * 1.1 = 1100, shortfall = 1100 - 1000 = 100
        assertEq(MarginAccount.shortfall(pos, THRESHOLD_110), 100e18);
    }

    function test_liquidationPenalty() public pure {
        // 100 shortfall * 5% penalty = 5
        uint256 penalty = MarginAccount.liquidationPenalty(100e18, 500);
        assertEq(penalty, 5e18);
    }

    function test_maxWithdrawable_healthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1500e18,
            borrowValue: 1000e18
        });
        // Required = 1000 * 1.1 = 1100, max withdraw = 1500 - 1100 = 400
        assertEq(MarginAccount.maxWithdrawable(pos, THRESHOLD_110), 400e18);
    }

    function test_maxWithdrawable_noBorrow() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1000e18,
            borrowValue: 0
        });
        assertEq(MarginAccount.maxWithdrawable(pos, THRESHOLD_110), 1000e18);
    }

    function test_maxWithdrawable_unhealthy() public pure {
        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: 1000e18,
            borrowValue: 1000e18
        });
        assertEq(MarginAccount.maxWithdrawable(pos, THRESHOLD_110), 0);
    }

    function testFuzz_marginRatio_isConsistent(
        uint256 collateral,
        uint256 borrow
    ) public pure {
        collateral = bound(collateral, 1e18, 1e30);
        borrow = bound(borrow, 1e18, 1e30);

        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: collateral,
            borrowValue: borrow
        });

        uint256 ratio = MarginAccount.marginRatio(pos);

        // ratio * borrow / WAD should approximately equal collateral
        uint256 reconstructed = (ratio * borrow) / WAD;
        assertApproxEqRel(reconstructed, collateral, 1e14, "Ratio reconstruction");
    }

    function testFuzz_isHealthy_consistentWithRatio(
        uint256 collateral,
        uint256 borrow,
        uint256 threshold
    ) public pure {
        collateral = bound(collateral, 0, 1e30);
        borrow = bound(borrow, 1, 1e30);
        threshold = bound(threshold, WAD, 3 * WAD); // 100%-300%

        MarginAccount.Position memory pos = MarginAccount.Position({
            collateralValue: collateral,
            borrowValue: borrow
        });

        bool healthy = MarginAccount.isHealthy(pos, threshold);
        uint256 ratio = MarginAccount.marginRatio(pos);

        if (healthy) {
            assertGt(ratio, threshold, "Healthy means ratio > threshold");
        }
        // Note: ratio == threshold means NOT healthy (strict >)
    }
}

// ============================================================
// NexusHub Tests
// ============================================================

contract NexusHubTest is Test {
    NexusHub hub;
    CollateralOracle oracle;
    MockTeleporter teleporter;
    MockYieldSource usdc;
    MockYieldSource avax;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");

    bytes32 constant CCHAIN_ID = bytes32(uint256(43113));
    bytes32 constant L1_ID = bytes32(uint256(99999));

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
        avax = new MockYieldSource("Mock AVAX", "mAVAX", 18);

        // Register assets
        oracle.registerAsset(address(usdc), 1e18, 9500);  // $1, 95%
        oracle.registerAsset(address(avax), 25e18, 7000);  // $25, 70%

        // Fund users
        usdc.mint(alice, 100_000e18);
        usdc.mint(bob, 100_000e18);
        avax.mint(alice, 1_000e18);

        // Approve
        vm.prank(alice);
        usdc.approve(address(hub), type(uint256).max);
        vm.prank(alice);
        avax.approve(address(hub), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(hub), type(uint256).max);
    }

    // --- Account Management ---

    function test_openMarginAccount() public {
        vm.prank(alice);
        hub.openMarginAccount();
        assertTrue(hub.hasAccount(alice));
    }

    function test_openMarginAccount_revert_duplicate() public {
        vm.prank(alice);
        hub.openMarginAccount();

        vm.prank(alice);
        vm.expectRevert("NexusHub: account exists");
        hub.openMarginAccount();
    }

    // --- Deposit ---

    function test_depositCollateral() public {
        _openAccount(alice);

        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        assertEq(hub.localDeposits(alice, address(usdc)), 10_000e18);
        assertEq(usdc.balanceOf(address(hub)), 10_000e18);
    }

    function test_depositCollateral_multiAsset() public {
        _openAccount(alice);

        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);
        vm.prank(alice);
        hub.depositCollateral(address(avax), 100e18);

        // USDC: 10000 * $1 * 95% = $9,500
        // AVAX: 100 * $25 * 70% = $1,750
        // Total: $11,250
        uint256 totalValue = hub.getTotalCollateralValue(alice);
        assertEq(totalValue, 11_250e18);
    }

    function test_depositCollateral_revert_noAccount() public {
        vm.prank(alice);
        vm.expectRevert("NexusHub: no account");
        hub.depositCollateral(address(usdc), 1000e18);
    }

    function test_depositCollateral_revert_unsupported() public {
        _openAccount(alice);
        address unknownToken = makeAddr("unknown");

        vm.prank(alice);
        vm.expectRevert("NexusHub: unsupported asset");
        hub.depositCollateral(unknownToken, 1000e18);
    }

    // --- Withdraw ---

    function test_withdrawCollateral() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        hub.withdrawCollateral(address(usdc), 5_000e18);

        assertEq(hub.localDeposits(alice, address(usdc)), 5_000e18);
        assertEq(usdc.balanceOf(alice), before + 5_000e18);
    }

    function test_withdrawCollateral_revert_wouldBeUnhealthy() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        // Set obligation: $8000. Collateral = $9,500. Required = $8,800 (110%).
        // Withdrawing 1000 USDC reduces collateral to $8,550 < $8,800
        hub.setObligation(alice, 8_000e18);

        vm.prank(alice);
        vm.expectRevert("NexusHub: would be unhealthy");
        hub.withdrawCollateral(address(usdc), 1_000e18);
    }

    function test_withdrawCollateral_succeeds_ifStillHealthy() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        // $9,500 collateral, $5,000 obligation → 190% ratio
        hub.setObligation(alice, 5_000e18);

        // Withdraw 2000 USDC → $7,600 collateral / $5,000 = 152% > 110%
        vm.prank(alice);
        hub.withdrawCollateral(address(usdc), 2_000e18);

        assertEq(hub.localDeposits(alice, address(usdc)), 8_000e18);
    }

    // --- Margin Ratio ---

    function test_getMarginRatio_noBorrow() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        uint256 ratio = hub.getMarginRatio(alice);
        assertEq(ratio, type(uint256).max, "No borrows = max ratio");
    }

    function test_getMarginRatio_withObligation() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        // Collateral = $9,500, obligation = $5,000 → ratio = 190%
        hub.setObligation(alice, 5_000e18);
        uint256 ratio = hub.getMarginRatio(alice);
        assertEq(ratio, 19e17, "9500/5000 = 190%");
    }

    function test_isHealthy_healthy() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        hub.setObligation(alice, 5_000e18);
        assertTrue(hub.isHealthy(alice), "190% > 110%");
    }

    function test_isHealthy_unhealthy() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        // $9,500 collateral / $9,000 obligation = 105.6% < 110%
        hub.setObligation(alice, 9_000e18);
        assertFalse(hub.isHealthy(alice));
    }

    // --- Liquidation ---

    function test_triggerLiquidation() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        hub.setObligation(alice, 9_000e18);
        assertFalse(hub.isHealthy(alice));

        uint256 liquidatorBefore = usdc.balanceOf(liquidator);

        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        // Liquidator receives obligation + penalty (penalty-capped seizure, NOT all collateral)
        // Collateral value = 10000 * $1 * 95% = $9,500
        // Required = 9000 * 1.1 = $9,900, shortfall = $9,900 - $9,500 = $400
        // Penalty = $400 * 5% = $20
        // seizureTarget = $9,000 + $20 = $9,020 (USD value)
        // seizeAmt = $9,020 / $1 price = 9,020 tokens
        uint256 liquidatorAfter = usdc.balanceOf(liquidator);
        assertEq(liquidatorAfter - liquidatorBefore, 9_020e18, "Liquidator seizes obligation + penalty");

        // Obligations cleared
        assertEq(hub.obligations(alice), 0);
    }

    function test_triggerLiquidation_revert_healthy() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        hub.setObligation(alice, 1_000e18);

        vm.prank(liquidator);
        vm.expectRevert("NexusHub: account is healthy");
        hub.triggerLiquidation(alice);
    }

    function test_triggerLiquidation_revert_noAccount() public {
        vm.prank(liquidator);
        vm.expectRevert("NexusHub: no account");
        hub.triggerLiquidation(alice);
    }

    // --- Cross-Chain Attestation ---

    function test_receiveAttestation() public {
        _openAccount(alice);

        // Register a remote vault
        address remoteVault = makeAddr("remoteVault");
        hub.registerVault(L1_ID, remoteVault);

        // Simulate attestation message from remote vault
        bytes memory message = abi.encode(uint8(1), alice, uint256(5_000e18));

        vm.prank(address(teleporter));
        hub.receiveTeleporterMessage(L1_ID, remoteVault, message);

        assertEq(hub.crossChainCollateral(alice, L1_ID), 5_000e18);
    }

    function test_crossChainCollateral_addedToTotal() public {
        _openAccount(alice);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 10_000e18);

        // Register remote vault and receive attestation
        address remoteVault = makeAddr("remoteVault");
        hub.registerVault(L1_ID, remoteVault);

        bytes memory message = abi.encode(uint8(1), alice, uint256(5_000e18));
        vm.prank(address(teleporter));
        hub.receiveTeleporterMessage(L1_ID, remoteVault, message);

        // Total = local ($9,500) + cross-chain ($5,000) = $14,500
        uint256 total = hub.getTotalCollateralValue(alice);
        assertEq(total, 14_500e18);
    }

    function test_receiveAttestation_revert_notTeleporter() public {
        address remoteVault = makeAddr("remoteVault");
        hub.registerVault(L1_ID, remoteVault);

        bytes memory message = abi.encode(uint8(1), alice, uint256(5_000e18));

        vm.prank(makeAddr("random"));
        vm.expectRevert("NexusHub: not teleporter");
        hub.receiveTeleporterMessage(L1_ID, remoteVault, message);
    }

    function test_receiveAttestation_revert_unknownVault() public {
        bytes memory message = abi.encode(uint8(1), alice, uint256(5_000e18));

        vm.prank(address(teleporter));
        vm.expectRevert("NexusHub: unknown vault");
        hub.receiveTeleporterMessage(L1_ID, makeAddr("random"), message);
    }

    // --- Admin ---

    function test_setObligation() public {
        _openAccount(alice);
        hub.setObligation(alice, 5_000e18);
        assertEq(hub.obligations(alice), 5_000e18);
    }

    function test_registerVault() public {
        address remoteVault = makeAddr("remoteVault");
        hub.registerVault(L1_ID, remoteVault);
        assertEq(hub.registeredVaults(L1_ID), remoteVault);
    }

    // --- Helpers ---

    function _openAccount(address user) internal {
        vm.prank(user);
        hub.openMarginAccount();
    }
}

// ============================================================
// NexusVault Tests
// ============================================================

contract NexusVaultTest is Test {
    NexusVault vault;
    CollateralOracle oracle;
    MockTeleporter teleporter;
    MockYieldSource usdc;
    MockYieldSource avax;

    address alice = makeAddr("alice");
    address hubAddr = makeAddr("hub");

    bytes32 constant CCHAIN_ID = bytes32(uint256(43113));
    bytes32 constant L1_ID = bytes32(uint256(99999));

    function setUp() public {
        oracle = new CollateralOracle();
        teleporter = new MockTeleporter(L1_ID);

        vault = new NexusVault(
            address(oracle),
            address(teleporter),
            CCHAIN_ID,       // hub chain
            hubAddr,          // hub address
            5 minutes         // attestation interval
        );

        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);
        avax = new MockYieldSource("Mock AVAX", "mAVAX", 18);

        oracle.registerAsset(address(usdc), 1e18, 9500);
        oracle.registerAsset(address(avax), 25e18, 7000);

        usdc.mint(alice, 100_000e18);
        avax.mint(alice, 1_000e18);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        avax.approve(address(vault), type(uint256).max);
    }

    // --- Deposit ---

    function test_deposit() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        assertEq(vault.getUserDeposit(alice, address(usdc)), 10_000e18);
        assertEq(usdc.balanceOf(address(vault)), 10_000e18);
    }

    function test_deposit_multiAsset() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);
        vm.prank(alice);
        vault.deposit(address(avax), 100e18);

        uint256 totalValue = vault.getUserTotalValue(alice);
        // USDC: 10000 * 1 * 95% = $9,500
        // AVAX: 100 * 25 * 70% = $1,750
        assertEq(totalValue, 11_250e18);
    }

    function test_deposit_revert_unsupported() public {
        vm.prank(alice);
        vm.expectRevert("NexusVault: unsupported asset");
        vault.deposit(makeAddr("unknown"), 1000e18);
    }

    function test_deposit_revert_zero() public {
        vm.prank(alice);
        vm.expectRevert("NexusVault: zero amount");
        vault.deposit(address(usdc), 0);
    }

    // --- Withdraw ---

    function test_withdraw() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(address(usdc), 5_000e18);

        assertEq(vault.getUserDeposit(alice, address(usdc)), 5_000e18);
        assertEq(usdc.balanceOf(alice), before + 5_000e18);
    }

    function test_withdraw_full() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        vm.prank(alice);
        vault.withdraw(address(usdc), 10_000e18);

        assertEq(vault.getUserDeposit(alice, address(usdc)), 0);
    }

    function test_withdraw_revert_insufficient() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1_000e18);

        vm.prank(alice);
        vm.expectRevert("NexusVault: insufficient balance");
        vault.withdraw(address(usdc), 2_000e18);
    }

    // --- Attestation ---

    function test_attestBalances() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        // Warp past initial attestation interval
        vm.warp(block.timestamp + 5 minutes);

        vm.prank(alice);
        vault.attestBalances();

        // Check teleporter received a message
        assertEq(teleporter.messageCount(), 1);
    }

    function test_attestBalances_revert_tooSoon() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        vm.warp(block.timestamp + 5 minutes);

        vm.prank(alice);
        vault.attestBalances();

        // Second attestation too soon
        vm.prank(alice);
        vm.expectRevert("NexusVault: too soon");
        vault.attestBalances();
    }

    function test_attestBalances_afterInterval() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        vm.warp(block.timestamp + 5 minutes);

        vm.prank(alice);
        vault.attestBalances();

        vm.warp(block.timestamp + 5 minutes);

        vm.prank(alice);
        vault.attestBalances();

        assertEq(teleporter.messageCount(), 2);
    }

    // --- Liquidation ---

    function test_executeLiquidation_byOwner() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        address owner = vault.owner();
        uint256 ownerBefore = usdc.balanceOf(owner);

        vault.executeLiquidation(alice);

        assertEq(vault.getUserDeposit(alice, address(usdc)), 0);
        assertEq(usdc.balanceOf(owner), ownerBefore + 10_000e18);
    }

    function test_executeLiquidation_revert_unauthorized() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 10_000e18);

        vm.prank(makeAddr("random"));
        vm.expectRevert("NexusVault: not authorized");
        vault.executeLiquidation(alice);
    }

    // --- View ---

    function test_getUserAssets() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1_000e18);
        vm.prank(alice);
        vault.deposit(address(avax), 10e18);

        address[] memory assets = vault.getUserAssets(alice);
        assertEq(assets.length, 2);
    }
}

// ============================================================
// Cross-Chain Integration Test
// ============================================================

contract NexusCrossChainTest is Test {
    // Simulates C-Chain
    NexusHub hub;
    CollateralOracle hubOracle;

    // Simulates L1
    NexusVault remoteVault;
    CollateralOracle vaultOracle;

    // Shared teleporter (simulates both chains on one)
    MockTeleporter teleporter;

    MockYieldSource usdc;

    address alice = makeAddr("alice");
    address liquidator = makeAddr("liquidator");

    bytes32 constant CCHAIN_ID = bytes32(uint256(43113));
    bytes32 constant L1_ID = bytes32(uint256(99999));

    function setUp() public {
        usdc = new MockYieldSource("Mock USDC", "mUSDC", 18);

        // Both oracles know about USDC
        hubOracle = new CollateralOracle();
        hubOracle.registerAsset(address(usdc), 1e18, 9500);

        vaultOracle = new CollateralOracle();
        vaultOracle.registerAsset(address(usdc), 1e18, 9500);

        // Teleporter (simulates cross-chain)
        teleporter = new MockTeleporter(L1_ID);

        // Deploy Hub (C-Chain)
        hub = new NexusHub(
            address(hubOracle),
            address(teleporter),
            11e17, // 110% threshold
            500    // 5% penalty
        );

        // Deploy remote vault (L1)
        remoteVault = new NexusVault(
            address(vaultOracle),
            address(teleporter),
            CCHAIN_ID,
            address(hub),
            0 // no attestation interval for testing
        );

        // Register the remote vault on the Hub
        hub.registerVault(L1_ID, address(remoteVault));

        // Fund alice
        usdc.mint(alice, 100_000e18);
        vm.prank(alice);
        usdc.approve(address(remoteVault), type(uint256).max);
    }

    /// @notice Full cross-chain flow: deposit on L1 → attest → Hub recognizes collateral
    function test_crossChain_depositAndAttest() public {
        // 1. Alice opens account on Hub
        vm.prank(alice);
        hub.openMarginAccount();

        // 2. Alice deposits on remote L1 vault
        vm.prank(alice);
        remoteVault.deposit(address(usdc), 20_000e18);

        // 3. Alice attests her balances
        vm.prank(alice);
        remoteVault.attestBalances();

        // 4. Teleporter delivers the attestation message to Hub
        teleporter.deliverMessage(0);

        // 5. Hub should now recognize Alice's cross-chain collateral
        // 20,000 USDC * $1 * 95% = $19,000
        assertEq(hub.crossChainCollateral(alice, L1_ID), 19_000e18);

        uint256 total = hub.getTotalCollateralValue(alice);
        assertEq(total, 19_000e18);
    }

    /// @notice Full flow: deposit → attest → set obligation → verify health
    function test_crossChain_marginHealth() public {
        vm.prank(alice);
        hub.openMarginAccount();

        vm.prank(alice);
        remoteVault.deposit(address(usdc), 20_000e18);

        vm.prank(alice);
        remoteVault.attestBalances();
        teleporter.deliverMessage(0);

        // Set obligation — $15,000
        hub.setObligation(alice, 15_000e18);

        // $19,000 / $15,000 = 126.7% > 110% → healthy
        assertTrue(hub.isHealthy(alice));
        assertApproxEqRel(hub.getMarginRatio(alice), 1267e15, 1e15);
    }

    /// @notice Full liquidation flow via price drop
    function test_crossChain_liquidationViaOracleUpdate() public {
        vm.prank(alice);
        hub.openMarginAccount();

        vm.prank(alice);
        remoteVault.deposit(address(usdc), 20_000e18);

        vm.prank(alice);
        remoteVault.attestBalances();
        teleporter.deliverMessage(0);

        // $19,000 collateral, $15,000 obligation → healthy at 126.7%
        hub.setObligation(alice, 15_000e18);
        assertTrue(hub.isHealthy(alice));

        // Price drops: USDC depegs to $0.80
        hubOracle.setPrice(address(usdc), 8e17);

        // Now need to re-attest with new oracle values
        // But cross-chain collateral was already attested as $19,000
        // The Hub uses local oracle for local deposits and cross-chain values are pre-computed
        // For this test, simulate local deposits instead

        // Give alice some local USDC on Hub too
        usdc.mint(alice, 20_000e18);
        vm.prank(alice);
        usdc.approve(address(hub), type(uint256).max);
        vm.prank(alice);
        hub.depositCollateral(address(usdc), 20_000e18);

        // Local collateral: 20000 * $0.80 * 95% = $15,200
        // Cross-chain: $19,000 (pre-attested, doesn't change with Hub oracle)
        // Total: $34,200, obligation: $15,000 → still healthy

        // Increase obligation to make it unhealthy locally
        hub.setObligation(alice, 32_000e18);

        // $34,200 / $32,000 = 106.9% < 110% → unhealthy
        assertFalse(hub.isHealthy(alice));

        // Liquidator seizes local collateral
        uint256 liqBefore = usdc.balanceOf(liquidator);
        vm.prank(liquidator);
        hub.triggerLiquidation(alice);

        assertEq(usdc.balanceOf(liquidator) - liqBefore, 20_000e18, "Liquidator gets local USDC");
        assertEq(hub.obligations(alice), 0, "Obligations cleared");
    }
}
