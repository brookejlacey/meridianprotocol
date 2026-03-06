// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface INexusVault {
    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event BalancesAttested(address indexed user, uint256 totalValue);
    event LiquidationExecuted(address indexed user, uint256 proceedsValue);

    function deposit(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function attestBalances() external;
    function executeLiquidation(address user) external;
    function getUserDeposit(address user, address asset) external view returns (uint256);
}
