// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IAIKeeper {
    struct AccountPriority {
        address account;
        uint256 priorityScore;      // WAD-scaled (higher = more urgent)
        uint256 estimatedShortfall;  // WAD-scaled USD
        uint256 timestamp;
        bool flagged;
    }

    event AccountPriorityUpdated(address indexed account, uint256 priorityScore, uint256 estimatedShortfall, bool flagged);
    event AccountRemoved(address indexed account);
    event PrioritizedLiquidation(address indexed account, address indexed liquidator, uint256 priorityScore);
    event PrioritizedWaterfallExecuted(address indexed vault, uint256 poolsTriggered, uint256 poolsSettled, uint256 accountsLiquidated);
    event AIMonitorUpdated(address indexed monitor, bool authorized);

    function updateAccountPriority(
        address account,
        uint256 priorityScore,
        uint256 estimatedShortfall,
        bool flagged
    ) external;

    function batchUpdatePriorities(
        address[] calldata accounts,
        uint256[] calldata scores,
        uint256[] calldata shortfalls,
        bool[] calldata flags
    ) external;

    function removeAccount(address account) external;

    function liquidateTopN(uint256 n) external returns (uint256 liquidatedCount);
    function liquidateAllFlagged() external returns (uint256 liquidatedCount);
    function executePrioritizedWaterfall(
        address vault,
        uint256 recoveryRateWad,
        uint256 maxAccounts
    ) external returns (uint256 poolsTriggered, uint256 poolsSettled, uint256 accountsLiquidated);

    function getTopAccounts(uint256 n) external view returns (AccountPriority[] memory);
    function getFlaggedAccounts() external view returns (address[] memory);
    function getAccountPriority(address account) external view returns (AccountPriority memory);
    function getMonitoredAccountCount() external view returns (uint256);
}
