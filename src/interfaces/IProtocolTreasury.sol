// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IProtocolTreasury {
    event FundsWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    function withdraw(address token, address recipient, uint256 amount) external;
    function balanceOf(address token) external view returns (uint256);
}
