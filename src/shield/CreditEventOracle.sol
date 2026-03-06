// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ICreditEventOracle} from "../interfaces/ICreditEventOracle.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";

/// @title CreditEventOracle
/// @notice MVP credit event detection — admin-triggered with auto-threshold monitoring.
/// @dev Phase 2 simplified oracle:
///      - Admin can manually report credit events
///      - Configurable health thresholds per vault
///      - Anyone can call checkAndTrigger() to auto-detect breaches
///
///      Future upgrade path: multi-oracle consensus, dispute period, governance override.
contract CreditEventOracle is ICreditEventOracle, Ownable2Step {
    // --- State ---

    /// @notice Health threshold per vault (WAD-scaled). Below this → impairment.
    /// E.g., 0.9e18 = trigger if collateral ratio drops below 90%
    mapping(address vault => uint256 threshold) public thresholds;

    /// @notice Default threshold per vault (WAD-scaled). Below this → default.
    /// E.g., 0.5e18 = trigger default if ratio drops below 50%
    mapping(address vault => uint256 defaultThreshold) public defaultThresholds;

    /// @notice Event history per vault
    mapping(address vault => CreditEvent[]) private _eventHistory;

    /// @notice Latest event per vault
    mapping(address vault => CreditEvent) private _latestEvent;

    /// @notice Whether a vault currently has an active credit event
    mapping(address vault => bool) public hasActiveEvent;

    /// @notice Authorized reporters (beyond admin)
    mapping(address => bool) public isReporter;

    // --- Events ---
    event ReporterUpdated(address indexed reporter, bool authorized);
    event CreditEventCleared(address indexed vault);

    // --- Modifiers ---
    modifier onlyReporter() {
        require(msg.sender == owner() || isReporter[msg.sender], "CreditEventOracle: not authorized");
        _;
    }

    constructor() Ownable(msg.sender) {}

    // --- Core Functions ---

    /// @notice Manually report a credit event on a vault
    /// @param vault The ForgeVault experiencing the event
    /// @param eventType Type of credit event (Impairment or Default)
    /// @param lossAmount Estimated loss amount (can be 0 for Impairment)
    function reportCreditEvent(
        address vault,
        EventType eventType,
        uint256 lossAmount
    ) external override onlyReporter {
        require(vault != address(0), "CreditEventOracle: zero vault");
        require(eventType != EventType.None, "CreditEventOracle: invalid event type");

        CreditEvent memory evt = CreditEvent({
            eventType: eventType,
            timestamp: block.timestamp,
            lossAmount: lossAmount,
            reporter: msg.sender
        });

        _eventHistory[vault].push(evt);
        _latestEvent[vault] = evt;
        hasActiveEvent[vault] = true;

        emit CreditEventReported(vault, eventType, lossAmount);
    }

    /// @notice Check if a vault has breached its health threshold
    /// @param vault The ForgeVault to check
    /// @return breached True if the vault's health is below threshold
    function checkThreshold(address vault) external view override returns (bool breached) {
        uint256 threshold_ = thresholds[vault];
        if (threshold_ == 0) return false; // No threshold configured

        IForgeVault.PoolMetrics memory metrics = IForgeVault(vault).getPoolMetrics();

        // Check pool status directly
        if (metrics.status == IForgeVault.PoolStatus.Defaulted) return true;
        if (metrics.status == IForgeVault.PoolStatus.Impaired) return true;

        return false;
    }

    /// @notice Check threshold and auto-trigger credit event if breached
    /// @param vault The ForgeVault to check
    /// @dev Anyone can call this — permissionless threshold monitoring
    function checkAndTrigger(address vault) external {
        require(!hasActiveEvent[vault], "CreditEventOracle: event already active");
        require(thresholds[vault] > 0, "CreditEventOracle: no threshold set");

        IForgeVault.PoolMetrics memory metrics = IForgeVault(vault).getPoolMetrics();

        EventType eventType = EventType.None;

        if (metrics.status == IForgeVault.PoolStatus.Defaulted) {
            eventType = EventType.Default;
        } else if (metrics.status == IForgeVault.PoolStatus.Impaired) {
            eventType = EventType.Impairment;
        }

        require(eventType != EventType.None, "CreditEventOracle: no breach detected");

        CreditEvent memory evt = CreditEvent({
            eventType: eventType,
            timestamp: block.timestamp,
            lossAmount: 0, // Auto-triggered events don't specify loss amount
            reporter: msg.sender
        });

        _eventHistory[vault].push(evt);
        _latestEvent[vault] = evt;
        hasActiveEvent[vault] = true;

        emit CreditEventReported(vault, eventType, 0);
    }

    /// @notice Get the latest credit event for a vault
    function getLatestEvent(address vault) external view override returns (CreditEvent memory) {
        return _latestEvent[vault];
    }

    /// @notice Get full event history for a vault
    function getEventHistory(address vault) external view returns (CreditEvent[] memory) {
        return _eventHistory[vault];
    }

    /// @notice Get number of events for a vault
    function getEventCount(address vault) external view returns (uint256) {
        return _eventHistory[vault].length;
    }

    // --- Admin Functions ---

    /// @notice Set health threshold for a vault
    /// @param vault The vault address
    /// @param threshold_ WAD-scaled threshold (e.g., 0.9e18 = 90%)
    function setThreshold(address vault, uint256 threshold_) external onlyOwner {
        thresholds[vault] = threshold_;
        emit ThresholdUpdated(vault, threshold_);
    }

    /// @notice Set default threshold for a vault
    function setDefaultThreshold(address vault, uint256 threshold_) external onlyOwner {
        defaultThresholds[vault] = threshold_;
    }

    /// @notice Authorize or revoke a reporter
    function setReporter(address reporter, bool authorized) external onlyOwner {
        isReporter[reporter] = authorized;
        emit ReporterUpdated(reporter, authorized);
    }

    /// @notice Clear active event for a vault (after resolution)
    function clearEvent(address vault) external onlyOwner {
        hasActiveEvent[vault] = false;
        emit CreditEventCleared(vault);
    }
}
