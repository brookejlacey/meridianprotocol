// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {AIRiskOracle} from "../../src/ai/AIRiskOracle.sol";
import {IAIRiskOracle} from "../../src/interfaces/IAIRiskOracle.sol";
import {ShieldPricer} from "../../src/shield/ShieldPricer.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

/// @dev Mock vault that returns configurable pool metrics for ShieldPricer integration tests
contract MockVaultForPricer {
    IForgeVault.PoolMetrics public metrics;

    constructor() {
        metrics = IForgeVault.PoolMetrics({
            totalDeposited: 1_000_000e18,
            totalYieldReceived: 0,
            totalYieldDistributed: 0,
            lastDistribution: block.timestamp,
            status: IForgeVault.PoolStatus.Active
        });
    }

    function getPoolMetrics() external view returns (IForgeVault.PoolMetrics memory) {
        return metrics;
    }
}

contract AIRiskOracleTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant DAY = 1 days;

    AIRiskOracle oracle;
    address updater = makeAddr("updater");
    address alice = makeAddr("alice");
    address vault = makeAddr("vault");

    function setUp() public {
        oracle = new AIRiskOracle(DAY, 0.1e18); // 24h max age, 10% max PD change
        oracle.setUpdater(updater, true);
    }

    // --- Constructor ---

    function test_constructor() public view {
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.maxScoreAge(), DAY);
        assertEq(oracle.maxScoreChange(), 0.1e18);
    }

    function test_constructor_revert_zeroAge() public {
        vm.expectRevert("AIRiskOracle: zero max age");
        new AIRiskOracle(0, 0.1e18);
    }

    function test_constructor_revert_zeroChange() public {
        vm.expectRevert("AIRiskOracle: zero max change");
        new AIRiskOracle(DAY, 0);
    }

    // --- Updater Authorization ---

    function test_setUpdater() public {
        oracle.setUpdater(alice, true);
        assertTrue(oracle.isUpdater(alice));
        oracle.setUpdater(alice, false);
        assertFalse(oracle.isUpdater(alice));
    }

    function test_setUpdater_revert_notOwner() public {
        vm.prank(alice);
        vm.expectRevert("AIRiskOracle: not owner");
        oracle.setUpdater(alice, true);
    }

    // --- Score Updates ---

    function test_updateRiskScore_basic() public {
        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("model-v1"));

        IAIRiskOracle.RiskScore memory score = oracle.getRiskScore(vault);
        assertEq(score.creditScore, 750);
        assertEq(score.defaultProbability, 0.02e18);
        assertEq(uint8(score.tier), uint8(IAIRiskOracle.RiskTier.A));
        assertEq(score.reporter, updater);
        assertEq(score.modelHash, bytes32("model-v1"));
        assertEq(score.timestamp, block.timestamp);
    }

    function test_updateRiskScore_revert_notUpdater() public {
        vm.prank(alice);
        vm.expectRevert("AIRiskOracle: not updater");
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));
    }

    function test_updateRiskScore_revert_invalidCreditScore() public {
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: credit score > 1000");
        oracle.updateRiskScore(vault, 1001, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));
    }

    function test_updateRiskScore_revert_invalidPD() public {
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: PD > WAD");
        oracle.updateRiskScore(vault, 750, 1.1e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));
    }

    function test_updateRiskScore_revert_zeroAsset() public {
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: zero asset");
        oracle.updateRiskScore(address(0), 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));
    }

    // --- Circuit Breaker ---

    function test_circuitBreaker_trips() public {
        // First score: 2% PD
        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));

        // Second score: 15% PD (13% jump > 10% max)
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: circuit breaker");
        oracle.updateRiskScore(vault, 400, 0.15e18, IAIRiskOracle.RiskTier.BB, bytes32("v2"));
    }

    function test_circuitBreaker_allowsSmallChange() public {
        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));

        // Small change: 2% -> 8% (6% < 10% max)
        vm.prank(updater);
        oracle.updateRiskScore(vault, 600, 0.08e18, IAIRiskOracle.RiskTier.BBB, bytes32("v2"));

        assertEq(oracle.getRiskScore(vault).defaultProbability, 0.08e18);
    }

    function test_circuitBreaker_firstScoreNoLimit() public {
        // First score can be anything (no prior to compare against)
        vm.prank(updater);
        oracle.updateRiskScore(vault, 100, 0.5e18, IAIRiskOracle.RiskTier.CCC, bytes32("v1"));
        assertEq(oracle.getRiskScore(vault).defaultProbability, 0.5e18);
    }

    // --- Staleness ---

    function test_getDefaultProbability_fresh() public {
        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));

        uint256 pd = oracle.getDefaultProbability(vault);
        assertEq(pd, 0.02e18);
    }

    function test_getDefaultProbability_stale() public {
        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));

        vm.warp(block.timestamp + DAY + 1);

        vm.expectRevert("AIRiskOracle: stale score");
        oracle.getDefaultProbability(vault);
    }

    function test_getDefaultProbability_noScore() public {
        vm.expectRevert("AIRiskOracle: no score");
        oracle.getDefaultProbability(vault);
    }

    function test_isFresh() public {
        assertFalse(oracle.isFresh(vault));

        vm.prank(updater);
        oracle.updateRiskScore(vault, 750, 0.02e18, IAIRiskOracle.RiskTier.A, bytes32("v1"));
        assertTrue(oracle.isFresh(vault));

        vm.warp(block.timestamp + DAY + 1);
        assertFalse(oracle.isFresh(vault));
    }

    // --- Batch Update ---

    function test_batchUpdate() public {
        address vault2 = makeAddr("vault2");

        address[] memory assets = new address[](2);
        assets[0] = vault;
        assets[1] = vault2;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 800;
        scores[1] = 600;

        uint256[] memory pds = new uint256[](2);
        pds[0] = 0.01e18;
        pds[1] = 0.05e18;

        IAIRiskOracle.RiskTier[] memory tiers = new IAIRiskOracle.RiskTier[](2);
        tiers[0] = IAIRiskOracle.RiskTier.AA;
        tiers[1] = IAIRiskOracle.RiskTier.BBB;

        vm.prank(updater);
        oracle.batchUpdateRiskScores(assets, scores, pds, tiers, bytes32("v1"));

        assertEq(oracle.getRiskScore(vault).creditScore, 800);
        assertEq(oracle.getRiskScore(vault2).creditScore, 600);
    }

    // --- Score History ---

    function test_scoreHistory() public {
        vm.startPrank(updater);
        oracle.updateRiskScore(vault, 800, 0.01e18, IAIRiskOracle.RiskTier.AA, bytes32("v1"));
        oracle.updateRiskScore(vault, 750, 0.05e18, IAIRiskOracle.RiskTier.A, bytes32("v2"));
        vm.stopPrank();

        IAIRiskOracle.RiskScore[] memory history = oracle.getScoreHistory(vault);
        assertEq(history.length, 2);
        assertEq(history[0].creditScore, 800);
        assertEq(history[1].creditScore, 750);
    }

    // --- Admin ---

    function test_setMaxScoreAge() public {
        oracle.setMaxScoreAge(2 days);
        assertEq(oracle.maxScoreAge(), 2 days);
    }

    function test_setMaxScoreChange() public {
        oracle.setMaxScoreChange(0.2e18);
        assertEq(oracle.maxScoreChange(), 0.2e18);
    }

    function test_ownershipTransfer_twoStep() public {
        oracle.transferOwnership(alice);
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.pendingOwner(), alice);

        vm.prank(alice);
        oracle.acceptOwnership();
        assertEq(oracle.owner(), alice);
    }

    // --- ShieldPricer Integration ---

    function test_shieldPricer_with_riskOracle() public {
        // Deploy mock vault and pricer
        MockVaultForPricer mockVault = new MockVaultForPricer();
        ShieldPricer pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));

        // Get baseline spread (no oracle)
        uint256 baseSpread = pricer.getIndicativeSpread(address(mockVault), 1_000e18, 365);

        // Set up AI oracle with 5% PD
        pricer.setRiskOracle(address(oracle));
        vm.prank(updater);
        oracle.updateRiskScore(address(mockVault), 500, 0.05e18, IAIRiskOracle.RiskTier.BBB, bytes32("v1"));

        // Spread should increase (5% PD * 5x adjustment = 25% collateral reduction)
        uint256 aiSpread = pricer.getIndicativeSpread(address(mockVault), 1_000e18, 365);
        assertGt(aiSpread, baseSpread, "AI risk should increase spread");
    }

    function test_shieldPricer_without_riskOracle() public {
        MockVaultForPricer mockVault = new MockVaultForPricer();
        ShieldPricer pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));

        // No oracle set — should work fine with default behavior
        uint256 spread = pricer.getIndicativeSpread(address(mockVault), 1_000e18, 365);
        // Base 50 + tenor (100 * 365 / 365 = 100) = 150 bps
        assertEq(spread, 150, "Default spread without oracle");
    }

    function test_shieldPricer_staleOracle_fallback() public {
        MockVaultForPricer mockVault = new MockVaultForPricer();
        ShieldPricer pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));

        pricer.setRiskOracle(address(oracle));

        // Set score then let it go stale
        vm.prank(updater);
        oracle.updateRiskScore(address(mockVault), 500, 0.05e18, IAIRiskOracle.RiskTier.BBB, bytes32("v1"));
        vm.warp(block.timestamp + DAY + 1);

        // Stale oracle: falls back to default pricing (try/catch catches the revert)
        uint256 spread = pricer.getIndicativeSpread(address(mockVault), 1_000e18, 365);
        assertEq(spread, 150, "Stale oracle should fall back to default");
    }

    // --- Fuzz ---

    function testFuzz_updateRiskScore(uint256 creditScore, uint256 pd) public {
        creditScore = bound(creditScore, 0, 1000);
        pd = bound(pd, 0, 0.09e18); // Stay within circuit breaker for first score

        vm.prank(updater);
        oracle.updateRiskScore(vault, creditScore, pd, IAIRiskOracle.RiskTier.BBB, bytes32("fuzz"));

        IAIRiskOracle.RiskScore memory score = oracle.getRiskScore(vault);
        assertEq(score.creditScore, creditScore);
        assertEq(score.defaultProbability, pd);
    }
}
