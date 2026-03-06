// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IInsurancePool {
    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed depositor, uint256 amount);
    event ShortfallCovered(address indexed user, uint256 requested, uint256 covered);
    event PremiumCollected(address indexed from, uint256 amount);
    event PremiumRateUpdated(uint256 oldRate, uint256 newRate);
    event NexusHubUpdated(address oldHub, address newHub);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function coverShortfall(address user, uint256 shortfall) external returns (uint256 covered);
    function collectPremium(address from, uint256 borrowAmount) external;
    function getReserves() external view returns (uint256);
    function getEffectiveBalance(address depositor) external view returns (uint256);

    // --- Pausable ---
    function pause() external;
    function unpause() external;
}
