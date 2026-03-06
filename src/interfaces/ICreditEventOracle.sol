// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ICreditEventOracle {
    enum EventType {
        None,
        Impairment,
        Default
    }

    struct CreditEvent {
        EventType eventType;
        uint256 timestamp;
        uint256 lossAmount;
        address reporter;
    }

    event CreditEventReported(address indexed vault, EventType eventType, uint256 lossAmount);
    event ThresholdUpdated(address indexed vault, uint256 newThreshold);

    function reportCreditEvent(address vault, EventType eventType, uint256 lossAmount) external;
    function checkThreshold(address vault) external view returns (bool breached);
    function checkAndTrigger(address vault) external;
    function getLatestEvent(address vault) external view returns (CreditEvent memory);
    function hasActiveEvent(address vault) external view returns (bool);
}
