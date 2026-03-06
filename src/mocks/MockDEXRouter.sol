// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title MockDEXRouter
/// @notice Simulates a DEX router for testing SecondaryMarketRouter.
/// @dev Swaps at configurable rates. Must hold output tokens to pay out.
///      In production, replaced by Uniswap V3 / TraderJoe router.
contract MockDEXRouter {
    using SafeERC20 for IERC20;

    /// @notice Exchange rate: WAD-scaled (1e18 = 1:1)
    mapping(address => mapping(address => uint256)) public rates;

    /// @notice Fee in basis points (e.g., 30 = 0.3%)
    uint256 public feeBps;

    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(uint256 feeBps_) {
        feeBps = feeBps_;
    }

    /// @notice Set exchange rate between two tokens
    function setRate(address tokenIn, address tokenOut, uint256 rateWad) external {
        rates[tokenIn][tokenOut] = rateWad;
    }

    /// @notice Swap exact input for output
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        require(rates[tokenIn][tokenOut] > 0, "MockDEX: no rate set");
        require(amountIn > 0, "MockDEX: zero input");

        uint256 grossOut = MeridianMath.wadMul(amountIn, rates[tokenIn][tokenOut]);
        uint256 fee = MeridianMath.bpsMul(grossOut, feeBps);
        amountOut = grossOut - fee;

        require(amountOut >= minAmountOut, "MockDEX: slippage");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Quote swap output (view)
    function quoteSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (rates[tokenIn][tokenOut] == 0) return 0;
        uint256 grossOut = MeridianMath.wadMul(amountIn, rates[tokenIn][tokenOut]);
        uint256 fee = MeridianMath.bpsMul(grossOut, feeBps);
        amountOut = grossOut - fee;
    }
}
