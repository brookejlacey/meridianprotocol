// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {AICreditEventDetector} from "../../src/ai/AICreditEventDetector.sol";
import {IAICreditEventDetector} from "../../src/interfaces/IAICreditEventDetector.sol";
import {ICreditEventOracle} from "../../src/interfaces/ICreditEventOracle.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";

contract AICreditEventDetectorTest is Test {
    uint256 constant HOUR = 1 hours;
    uint256 constant DAY = 1 days;

    CreditEventOracle oracle;
    AICreditEventDetector detector;

    address gov = makeAddr("governance");
    address aiDetector = makeAddr("aiDetector");
    address alice = makeAddr("alice");
    address vault = makeAddr("vault");

    function setUp() public {
        oracle = new CreditEventOracle();
        detector = new AICreditEventDetector(
            address(oracle),
            gov,
            9000,   // 90% min confidence for auto-report
            6 hours, // 6h timelock
            3,       // max 3 reports per window
            1 hours  // 1h rate limit window
        );

        // Register detector as reporter on oracle
        oracle.setReporter(address(detector), true);

        // Authorize AI detector
        vm.prank(gov);
        detector.setDetector(aiDetector, true);
    }

    // --- Constructor ---

    function test_constructor() public view {
        assertEq(address(detector.ORACLE()), address(oracle));
        assertEq(detector.governance(), gov);
        assertEq(detector.minConfidenceForAutoReport(), 9000);
        assertEq(detector.timelockDuration(), 6 hours);
        assertEq(detector.maxReportsPerWindow(), 3);
        assertEq(detector.reportWindowSeconds(), 1 hours);
    }

    function test_constructor_revert_zeroOracle() public {
        vm.expectRevert("AICreditEventDetector: zero oracle");
        new AICreditEventDetector(address(0), gov, 9000, 6 hours, 3, 1 hours);
    }

    // --- Auto-Execute: High Confidence Impairment ---

    function test_submitDetection_autoExecute_highConfidence() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            9500, // 95% confidence (>= 90% threshold)
            bytes32("evidence-hash"),
            bytes32("model-v1")
        );

        // Report should be auto-executed
        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertTrue(report.executed, "Should be auto-executed");
        assertEq(report.confidenceScore, 9500);

        // Oracle should have the event
        assertTrue(oracle.hasActiveEvent(vault), "Oracle should have active event");
    }

    // --- Timelock: Low Confidence ---

    function test_submitDetection_timelocked_lowConfidence() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000, // 70% < 90% threshold
            bytes32("evidence"),
            bytes32("model-v1")
        );

        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertFalse(report.executed, "Should NOT be auto-executed");
        assertFalse(oracle.hasActiveEvent(vault), "Oracle should NOT have event yet");

        // Should have timelock set
        uint256 remaining = detector.getTimelockRemaining(reportId);
        assertGt(remaining, 0, "Should have timelock remaining");
    }

    // --- Timelock: Default Always Timelocked ---

    function test_submitDetection_timelocked_default() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Default,
            500e18,
            9500, // Even high confidence Default events are timelocked
            bytes32("evidence"),
            bytes32("model-v1")
        );

        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertFalse(report.executed, "Default should NOT auto-execute");
    }

    // --- Execute Timelocked ---

    function test_executeTimelocked_afterDelay() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        // Warp past timelock
        vm.warp(block.timestamp + 6 hours + 1);

        // Anyone can execute after timelock
        detector.executeTimelocked(reportId);

        assertTrue(oracle.hasActiveEvent(vault), "Oracle should have event after timelock");
        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertTrue(report.executed);
    }

    function test_executeTimelocked_revert_tooEarly() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        // Try to execute before timelock expires
        vm.warp(block.timestamp + 3 hours);
        vm.expectRevert("AICreditEventDetector: timelock active");
        detector.executeTimelocked(reportId);
    }

    function test_executeTimelocked_revert_vetoed() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        // Governance vetos
        vm.prank(gov);
        detector.vetoReport(reportId);

        // Warp past timelock
        vm.warp(block.timestamp + 6 hours + 1);

        // Should fail because vetoed
        vm.expectRevert("AICreditEventDetector: vetoed");
        detector.executeTimelocked(reportId);
    }

    // --- Veto ---

    function test_vetoReport() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        vm.prank(gov);
        detector.vetoReport(reportId);

        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertTrue(report.vetoed);
    }

    function test_vetoReport_revert_notGov() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            100e18,
            7000,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        vm.prank(alice);
        vm.expectRevert("AICreditEventDetector: not governance");
        detector.vetoReport(reportId);
    }

    // --- Force Execute ---

    function test_forceExecute() public {
        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Default,
            500e18,
            9500,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        // Governance force-executes immediately (no waiting for timelock)
        vm.prank(gov);
        detector.forceExecute(reportId);

        assertTrue(oracle.hasActiveEvent(vault));
        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertTrue(report.executed);
    }

    // --- Rate Limiting ---

    function test_rateLimit_trips() public {
        vm.startPrank(aiDetector);

        // Submit 3 reports (should succeed)
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 10e18, 9500, bytes32("e1"), bytes32("m1"));

        // Clear event so we can report again
        vm.stopPrank();
        oracle.clearEvent(vault);
        vm.startPrank(aiDetector);

        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 20e18, 9500, bytes32("e2"), bytes32("m1"));

        vm.stopPrank();
        oracle.clearEvent(vault);
        vm.startPrank(aiDetector);

        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 30e18, 9500, bytes32("e3"), bytes32("m1"));

        vm.stopPrank();
        oracle.clearEvent(vault);

        // 4th report should hit rate limit
        vm.prank(aiDetector);
        vm.expectRevert("AICreditEventDetector: rate limit");
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 40e18, 9500, bytes32("e4"), bytes32("m1"));
    }

    function test_rateLimit_windowReset() public {
        vm.startPrank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 10e18, 9500, bytes32("e1"), bytes32("m1"));
        vm.stopPrank();
        oracle.clearEvent(vault);

        vm.startPrank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 20e18, 9500, bytes32("e2"), bytes32("m1"));
        vm.stopPrank();
        oracle.clearEvent(vault);

        vm.startPrank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 30e18, 9500, bytes32("e3"), bytes32("m1"));
        vm.stopPrank();
        oracle.clearEvent(vault);

        // Warp past rate limit window
        vm.warp(block.timestamp + HOUR + 1);

        // Should succeed after window reset
        vm.prank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 40e18, 9500, bytes32("e4"), bytes32("m1"));
    }

    // --- Unauthorized ---

    function test_submitDetection_revert_notDetector() public {
        vm.prank(alice);
        vm.expectRevert("AICreditEventDetector: not detector");
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 100e18, 9500, bytes32("e1"), bytes32("m1"));
    }

    // --- Pending Reports ---

    function test_getPendingReports() public {
        vm.prank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Impairment, 100e18, 7000, bytes32("e1"), bytes32("m1"));
        vm.prank(aiDetector);
        detector.submitDetection(vault, ICreditEventOracle.EventType.Default, 200e18, 7000, bytes32("e2"), bytes32("m1"));

        uint256[] memory pending = detector.getPendingReports();
        assertEq(pending.length, 2);
    }

    // --- Governance Transfer ---

    function test_governanceTransfer_twoStep() public {
        vm.prank(gov);
        detector.transferGovernance(alice);
        assertEq(detector.governance(), gov);

        vm.prank(alice);
        detector.acceptGovernance();
        assertEq(detector.governance(), alice);
    }

    // --- Fuzz ---

    function testFuzz_submitDetection(uint256 confidence, uint256 lossEstimate) public {
        confidence = bound(confidence, 0, 10_000);
        lossEstimate = bound(lossEstimate, 0, 1_000_000e18);

        vm.prank(aiDetector);
        uint256 reportId = detector.submitDetection(
            vault,
            ICreditEventOracle.EventType.Impairment,
            lossEstimate,
            confidence,
            bytes32("evidence"),
            bytes32("model-v1")
        );

        IAICreditEventDetector.DetectionReport memory report = detector.getReport(reportId);
        assertEq(report.confidenceScore, confidence);
        assertEq(report.lossEstimate, lossEstimate);

        // If high confidence, should be auto-executed
        if (confidence >= 9000) {
            assertTrue(report.executed);
        } else {
            assertFalse(report.executed);
        }
    }
}
