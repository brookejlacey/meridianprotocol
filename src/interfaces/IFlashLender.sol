// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title IFlashBorrower
/// @notice Interface for flash loan receivers
interface IFlashBorrower {
    function onFlashLoan(address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

/// @title IFlashLender
/// @notice Interface for flash loan providers (Aave, Balancer, or custom)
interface IFlashLender {
    function flashLoan(address token, uint256 amount, bytes calldata data) external;
}
