// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ICreditEventOracle} from "./ICreditEventOracle.sol";

interface IAICreditEventDetector {
    struct DetectionReport {
        address vault;
        ICreditEventOracle.EventType eventType;
        uint256 lossEstimate;
        uint256 confidenceScore;    // 0-10_000 BPS
        bytes32 evidenceHash;
        bytes32 modelHash;
        uint256 timestamp;
        bool executed;
        bool vetoed;
    }

    event DetectionSubmitted(uint256 indexed reportId, address indexed vault, ICreditEventOracle.EventType eventType, uint256 confidenceScore);
    event DetectionAutoExecuted(uint256 indexed reportId, address indexed vault);
    event DetectionTimelocked(uint256 indexed reportId, address indexed vault, uint256 executeAfter);
    event DetectionExecuted(uint256 indexed reportId, address indexed vault);
    event DetectionVetoed(uint256 indexed reportId, address indexed vault);
    event DetectionForceExecuted(uint256 indexed reportId, address indexed vault);
    event DetectorUpdated(address indexed detector, bool authorized);
    event RateLimitTripped(address indexed vault, uint256 reportsInWindow);

    function submitDetection(
        address vault,
        ICreditEventOracle.EventType eventType,
        uint256 lossEstimate,
        uint256 confidenceScore,
        bytes32 evidenceHash,
        bytes32 modelHash
    ) external returns (uint256 reportId);

    function executeTimelocked(uint256 reportId) external;
    function vetoReport(uint256 reportId) external;
    function forceExecute(uint256 reportId) external;

    function getReport(uint256 reportId) external view returns (DetectionReport memory);
    function getPendingReports() external view returns (uint256[] memory);
    function getTimelockRemaining(uint256 reportId) external view returns (uint256);
    function getRecentReportCount(address vault) external view returns (uint256);
}
