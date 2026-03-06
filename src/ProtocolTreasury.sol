// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";

/// @title ProtocolTreasury
/// @notice Simple receiver for protocol fees. Owner can withdraw funds.
/// @dev Protocol contracts push fees via safeTransfer. No deposit function needed.
contract ProtocolTreasury is IProtocolTreasury, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Withdraw tokens from treasury
    /// @param token ERC20 token address
    /// @param recipient Withdrawal recipient
    /// @param amount Amount to withdraw
    function withdraw(address token, address recipient, uint256 amount)
        external
        override
        onlyOwner
        nonReentrant
    {
        require(recipient != address(0), "ProtocolTreasury: zero recipient");
        require(amount > 0, "ProtocolTreasury: zero amount");

        IERC20(token).safeTransfer(recipient, amount);
        emit FundsWithdrawn(token, recipient, amount);
    }

    /// @notice Check balance of any token held by treasury
    function balanceOf(address token) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
