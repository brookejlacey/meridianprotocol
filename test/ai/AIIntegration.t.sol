// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {AIRiskOracle} from "../../src/ai/AIRiskOracle.sol";
import {AICreditEventDetector} from "../../src/ai/AICreditEventDetector.sol";
import {IAIRiskOracle} from "../../src/interfaces/IAIRiskOracle.sol";
import {ICreditEventOracle} from "../../src/interfaces/ICreditEventOracle.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {ShieldPricer} from "../../src/shield/ShieldPricer.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";

/// @dev Mock vault for integration tests
contract IntegrationMockVault {
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

contract AIIntegrationTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant DAY = 1 days;

    AIRiskOracle riskOracle;
    AICreditEventDetector detector;
    CreditEventOracle creditOracle;
    ShieldPricer pricer;
    IntegrationMockVault vault;

    address updater = makeAddr("updater");
    address aiDetector = makeAddr("aiDetector");
    address gov = makeAddr("governance");

    function setUp() public {
        vault = new IntegrationMockVault();

        // Deploy AIRiskOracle
        riskOracle = new AIRiskOracle(DAY, 0.5e18);
        riskOracle.setUpdater(updater, true);

        // Deploy CreditEventOracle + Detector
        creditOracle = new CreditEventOracle();
        detector = new AICreditEventDetector(
            address(creditOracle),
            gov,
            9000,
            6 hours,
            5,
            1 hours
        );
        creditOracle.setReporter(address(detector), true);
        vm.prank(gov);
        detector.setDetector(aiDetector, true);

        // Deploy ShieldPricer with AI oracle
        pricer = new ShieldPricer(ShieldPricer.PricingParams({
            baseRateBps: 50,
            riskMultiplierBps: 2000,
            utilizationKinkBps: 8000,
            utilizationSurchargeBps: 500,
            tenorScalerBps: 100,
            maxSpreadBps: 5000
        }));
        pricer.setRiskOracle(address(riskOracle));
    }

    // --- AIRiskOracle -> ShieldPricer ---

    function test_integration_riskScore_affectsPricing() public {
        // Baseline spread (no risk score)
        uint256 baseSpread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);

        // Set risk score: 10% PD
        vm.prank(updater);
        riskOracle.updateRiskScore(
            address(vault), 400, 0.1e18,
            IAIRiskOracle.RiskTier.BB, bytes32("v1")
        );

        // Spread should be higher now
        uint256 riskSpread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);
        assertGt(riskSpread, baseSpread, "Risk score should increase CDS spread");

        // Update to better score: 1% PD
        vm.prank(updater);
        riskOracle.updateRiskScore(
            address(vault), 800, 0.01e18,
            IAIRiskOracle.RiskTier.AA, bytes32("v2")
        );

        uint256 improvedSpread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);
        assertLt(improvedSpread, riskSpread, "Better score should reduce spread");
    }

    // --- AICreditEventDetector -> CreditEventOracle ---

    function test_integration_detector_triggersOracle() public {
        assertFalse(creditOracle.hasActiveEvent(address(vault)));

        // AI detects impairment with high confidence
        vm.prank(aiDetector);
        detector.submitDetection(
            address(vault),
            ICreditEventOracle.EventType.Impairment,
            50_000e18,
            9500,
            bytes32("evidence-hash"),
            bytes32("model-v1")
        );

        // Should auto-execute (high confidence Impairment)
        assertTrue(creditOracle.hasActiveEvent(address(vault)), "Oracle should have event");

        ICreditEventOracle.CreditEvent memory evt = creditOracle.getLatestEvent(address(vault));
        assertEq(uint8(evt.eventType), uint8(ICreditEventOracle.EventType.Impairment));
        assertEq(evt.lossAmount, 50_000e18);
    }

    // --- Timelock + Veto Safety ---

    function test_integration_timelockVeto_preventsExecution() public {
        // AI detects Default (always timelocked)
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            address(vault),
            ICreditEventOracle.EventType.Default,
            500_000e18,
            9500,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        // Oracle should NOT have event yet
        assertFalse(creditOracle.hasActiveEvent(address(vault)));

        // Governance vetos the false positive
        vm.prank(gov);
        detector.vetoReport(reportId);

        // Even after timelock, execution fails
        vm.warp(block.timestamp + 7 hours);
        vm.expectRevert("AICreditEventDetector: vetoed");
        detector.executeTimelocked(reportId);

        // Oracle still clean
        assertFalse(creditOracle.hasActiveEvent(address(vault)));
    }

    // --- Multi-Component Sequence ---

    function test_integration_multiComponent_sequence() public {
        // Step 1: AI sets risk score
        vm.prank(updater);
        riskOracle.updateRiskScore(
            address(vault), 300, 0.15e18,
            IAIRiskOracle.RiskTier.B, bytes32("v1")
        );

        // Step 2: CDS spread reflects risk
        uint256 spread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);
        assertGt(spread, 150, "Spread should be elevated due to AI risk score");

        // Step 3: AI detects credit event
        vm.prank(aiDetector);
        detector.submitDetection(
            address(vault),
            ICreditEventOracle.EventType.Impairment,
            200_000e18,
            9500,
            bytes32("evidence"),
            bytes32("v1")
        );

        // Step 4: Oracle has event
        assertTrue(creditOracle.hasActiveEvent(address(vault)));

        // Step 5: Verify circuit breaker still works
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: circuit breaker");
        riskOracle.updateRiskScore(
            address(vault), 50, 0.95e18, // 80% jump > 50% max
            IAIRiskOracle.RiskTier.Default, bytes32("v2")
        );
    }

    // --- Circuit Breaker Safety ---

    function test_integration_circuitBreaker_protectsProtocol() public {
        // Normal score
        vm.prank(updater);
        riskOracle.updateRiskScore(
            address(vault), 700, 0.03e18,
            IAIRiskOracle.RiskTier.A, bytes32("v1")
        );

        uint256 normalSpread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);

        // Compromised AI tries to crash spreads
        vm.prank(updater);
        vm.expectRevert("AIRiskOracle: circuit breaker");
        riskOracle.updateRiskScore(
            address(vault), 0, 1e18,
            IAIRiskOracle.RiskTier.Default, bytes32("hacked")
        );

        // Spread unchanged
        uint256 currentSpread = pricer.getIndicativeSpread(address(vault), 1_000e18, 365);
        assertEq(currentSpread, normalSpread, "Spread should be unchanged after circuit breaker");
    }
}
