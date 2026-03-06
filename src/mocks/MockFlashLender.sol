// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashBorrower, IFlashLender} from "../interfaces/IFlashLender.sol";

/// @title MockFlashLender
/// @notice Simple flash loan provider for testnet. Zero fee for MVP.
/// @dev Lends from its own balance. Fund it with tokens before use.
contract MockFlashLender is IFlashLender {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_BPS = 0; // 0% fee for testnet

    event FlashLoan(address indexed borrower, address indexed token, uint256 amount);

    /// @notice Execute a flash loan
    /// @param token The token to borrow
    /// @param amount Amount to borrow
    /// @param data Arbitrary data passed to the borrower callback
    function flashLoan(address token, uint256 amount, bytes calldata data) external override {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        require(balanceBefore >= amount, "FlashLender: insufficient balance");

        uint256 fee = (amount * FEE_BPS) / 10_000;

        // Transfer tokens to borrower
        IERC20(token).safeTransfer(msg.sender, amount);

        // Call borrower
        IFlashBorrower(msg.sender).onFlashLoan(token, amount, fee, data);

        // Verify repayment
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "FlashLender: not repaid");

        emit FlashLoan(msg.sender, token, amount);
    }
}
