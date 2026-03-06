// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAICreditEventDetector} from "../interfaces/IAICreditEventDetector.sol";
import {ICreditEventOracle} from "../interfaces/ICreditEventOracle.sol";
import {CreditEventOracle} from "../shield/CreditEventOracle.sol";

/// @title AICreditEventDetector
/// @notice AI-powered credit event detection with timelock/veto safety.
/// @dev Off-chain AI monitors market data and submits credit event reports on-chain.
///      High-confidence Impairment events auto-execute. Default events and low-confidence
///      reports go through a timelock so governance can veto false positives.
///
///      Safety features:
///      - Auto-execute threshold: only high-confidence Impairments skip timelock
///      - Timelock + veto: governance can block false positives
///      - Force-execute: governance can bypass timelock for emergencies
///      - Rate limiting: max N reports per vault per time window
///      - Two-step governance transfer
contract AICreditEventDetector is IAICreditEventDetector {
    // --- State ---
    CreditEventOracle public immutable ORACLE;

    mapping(uint256 => DetectionReport) private _reports;
    uint256 public nextReportId;
    mapping(uint256 => uint256) public reportTimelocks; // reportId => executeAfter timestamp

    mapping(address => bool) public isDetector;
    uint256 public minConfidenceForAutoReport;  // BPS (e.g., 9000 = 90%)
    uint256 public timelockDuration;            // seconds

    // Rate limiting
    uint256 public maxReportsPerWindow;
    uint256 public reportWindowSeconds;
    mapping(address vault => uint256[]) private _recentReportTimestamps;

    address public governance;
    address public pendingGovernance;

    // --- Events (admin) ---
    event GovernanceTransferStarted(address indexed previousGov, address indexed newGov);
    event GovernanceTransferred(address indexed previousGov, address indexed newGov);
    event MinConfidenceUpdated(uint256 newMinConfidence);
    event TimelockDurationUpdated(uint256 newDuration);
    event RateLimitUpdated(uint256 maxReports, uint256 windowSeconds);

    // --- Modifiers ---
    modifier onlyGovernance() {
        require(msg.sender == governance, "AICreditEventDetector: not governance");
        _;
    }

    modifier onlyDetector_() {
        require(isDetector[msg.sender], "AICreditEventDetector: not detector");
        _;
    }

    constructor(
        address oracle_,
        address governance_,
        uint256 minConfidence_,
        uint256 timelockDuration_,
        uint256 maxReportsPerWindow_,
        uint256 reportWindowSeconds_
    ) {
        require(oracle_ != address(0), "AICreditEventDetector: zero oracle");
        require(governance_ != address(0), "AICreditEventDetector: zero governance");
        require(timelockDuration_ > 0, "AICreditEventDetector: zero timelock");
        require(maxReportsPerWindow_ > 0, "AICreditEventDetector: zero max reports");
        require(reportWindowSeconds_ > 0, "AICreditEventDetector: zero window");

        ORACLE = CreditEventOracle(oracle_);
        governance = governance_;
        minConfidenceForAutoReport = minConfidence_;
        timelockDuration = timelockDuration_;
        maxReportsPerWindow = maxReportsPerWindow_;
        reportWindowSeconds = reportWindowSeconds_;
    }

    // --- Detector Functions ---

    /// @notice Submit an AI detection report
    function submitDetection(
        address vault,
        ICreditEventOracle.EventType eventType,
        uint256 lossEstimate,
        uint256 confidenceScore,
        bytes32 evidenceHash,
        bytes32 modelHash
    ) external override onlyDetector_ returns (uint256 reportId) {
        require(vault != address(0), "AICreditEventDetector: zero vault");
        require(eventType != ICreditEventOracle.EventType.None, "AICreditEventDetector: invalid event type");
        require(confidenceScore <= 10_000, "AICreditEventDetector: confidence > 10000");

        // Rate limit check
        _pruneAndCheckRateLimit(vault);

        reportId = nextReportId++;

        _reports[reportId] = DetectionReport({
            vault: vault,
            eventType: eventType,
            lossEstimate: lossEstimate,
            confidenceScore: confidenceScore,
            evidenceHash: evidenceHash,
            modelHash: modelHash,
            timestamp: block.timestamp,
            executed: false,
            vetoed: false
        });

        _recentReportTimestamps[vault].push(block.timestamp);

        emit DetectionSubmitted(reportId, vault, eventType, confidenceScore);

        // Auto-execute: high confidence Impairment only
        if (
            confidenceScore >= minConfidenceForAutoReport &&
            eventType == ICreditEventOracle.EventType.Impairment
        ) {
            ORACLE.reportCreditEvent(vault, eventType, lossEstimate);
            _reports[reportId].executed = true;
            emit DetectionAutoExecuted(reportId, vault);
        } else {
            // Queue with timelock
            reportTimelocks[reportId] = block.timestamp + timelockDuration;
            emit DetectionTimelocked(reportId, vault, block.timestamp + timelockDuration);
        }
    }

    // --- Timelock Execution ---

    /// @notice Execute a timelocked report (permissionless, after timelock expires)
    function executeTimelocked(uint256 reportId) external override {
        DetectionReport storage report = _reports[reportId];
        require(report.timestamp > 0, "AICreditEventDetector: no report");
        require(!report.executed, "AICreditEventDetector: already executed");
        require(!report.vetoed, "AICreditEventDetector: vetoed");
        require(
            block.timestamp >= reportTimelocks[reportId],
            "AICreditEventDetector: timelock active"
        );
        require(reportTimelocks[reportId] > 0, "AICreditEventDetector: no timelock");

        report.executed = true;
        ORACLE.reportCreditEvent(report.vault, report.eventType, report.lossEstimate);

        emit DetectionExecuted(reportId, report.vault);
    }

    // --- Governance ---

    /// @notice Veto a timelocked report
    function vetoReport(uint256 reportId) external override onlyGovernance {
        DetectionReport storage report = _reports[reportId];
        require(report.timestamp > 0, "AICreditEventDetector: no report");
        require(!report.executed, "AICreditEventDetector: already executed");
        require(!report.vetoed, "AICreditEventDetector: already vetoed");
        report.vetoed = true;
        emit DetectionVetoed(reportId, report.vault);
    }

    /// @notice Force-execute a report bypassing timelock (emergency)
    function forceExecute(uint256 reportId) external override onlyGovernance {
        DetectionReport storage report = _reports[reportId];
        require(report.timestamp > 0, "AICreditEventDetector: no report");
        require(!report.executed, "AICreditEventDetector: already executed");
        require(!report.vetoed, "AICreditEventDetector: vetoed");

        report.executed = true;
        ORACLE.reportCreditEvent(report.vault, report.eventType, report.lossEstimate);

        emit DetectionForceExecuted(reportId, report.vault);
    }

    // --- Views ---

    function getReport(uint256 reportId) external view override returns (DetectionReport memory) {
        return _reports[reportId];
    }

    function getPendingReports() external view override returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < nextReportId;) {
            DetectionReport memory r = _reports[i];
            if (!r.executed && !r.vetoed && r.timestamp > 0) {
                count++;
            }
            unchecked { ++i; }
        }

        uint256[] memory pending = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < nextReportId;) {
            DetectionReport memory r = _reports[i];
            if (!r.executed && !r.vetoed && r.timestamp > 0) {
                pending[idx++] = i;
            }
            unchecked { ++i; }
        }
        return pending;
    }

    function getTimelockRemaining(uint256 reportId) external view override returns (uint256) {
        uint256 executeAfter = reportTimelocks[reportId];
        if (executeAfter == 0 || block.timestamp >= executeAfter) return 0;
        return executeAfter - block.timestamp;
    }

    function getRecentReportCount(address vault) external view override returns (uint256) {
        uint256[] memory timestamps = _recentReportTimestamps[vault];
        uint256 cutoff = block.timestamp > reportWindowSeconds ? block.timestamp - reportWindowSeconds : 0;
        uint256 count;
        for (uint256 i = 0; i < timestamps.length;) {
            if (timestamps[i] >= cutoff) count++;
            unchecked { ++i; }
        }
        return count;
    }

    // --- Admin ---

    function setDetector(address detector, bool authorized) external onlyGovernance {
        require(detector != address(0), "AICreditEventDetector: zero address");
        isDetector[detector] = authorized;
        emit DetectorUpdated(detector, authorized);
    }

    function setMinConfidence(uint256 minConf) external onlyGovernance {
        require(minConf <= 10_000, "AICreditEventDetector: > 10000");
        minConfidenceForAutoReport = minConf;
        emit MinConfidenceUpdated(minConf);
    }

    function setTimelockDuration(uint256 duration) external onlyGovernance {
        require(duration > 0, "AICreditEventDetector: zero timelock");
        timelockDuration = duration;
        emit TimelockDurationUpdated(duration);
    }

    function setRateLimit(uint256 maxReports, uint256 windowSeconds) external onlyGovernance {
        require(maxReports > 0, "AICreditEventDetector: zero max reports");
        require(windowSeconds > 0, "AICreditEventDetector: zero window");
        maxReportsPerWindow = maxReports;
        reportWindowSeconds = windowSeconds;
        emit RateLimitUpdated(maxReports, windowSeconds);
    }

    // --- Governance Transfer (Two-Step) ---

    function transferGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "AICreditEventDetector: zero address");
        pendingGovernance = newGov;
        emit GovernanceTransferStarted(governance, newGov);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "AICreditEventDetector: not pending governance");
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    // --- Internal ---

    /// @dev Prune old timestamps and check rate limit
    function _pruneAndCheckRateLimit(address vault) internal {
        uint256[] storage timestamps = _recentReportTimestamps[vault];
        uint256 cutoff = block.timestamp > reportWindowSeconds ? block.timestamp - reportWindowSeconds : 0;

        // Prune old entries
        uint256 writeIdx;
        for (uint256 i = 0; i < timestamps.length;) {
            if (timestamps[i] >= cutoff) {
                if (writeIdx != i) {
                    timestamps[writeIdx] = timestamps[i];
                }
                writeIdx++;
            }
            unchecked { ++i; }
        }
        // Trim array
        while (timestamps.length > writeIdx) {
            timestamps.pop();
        }

        // Check limit
        if (timestamps.length >= maxReportsPerWindow) {
            emit RateLimitTripped(vault, timestamps.length);
            revert("AICreditEventDetector: rate limit");
        }
    }
}
