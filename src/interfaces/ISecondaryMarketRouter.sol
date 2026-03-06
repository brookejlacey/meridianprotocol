// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ISecondaryMarketRouter {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    struct SwapAndReinvestParams {
        address tokenIn;
        uint256 amountIn;
        uint256 minUnderlying;
        address vault;
        uint8 trancheId;
    }

    struct SwapAndHedgeParams {
        address tokenIn;
        uint256 amountIn;
        uint256 minUnderlying;
        address vault;
        uint8 trancheId;
        address cds;
        uint256 maxPremium;
    }

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event SwapAndReinvested(
        address indexed user,
        address tokenIn,
        address vault,
        uint8 trancheId,
        uint256 amountSwapped,
        uint256 amountReinvested
    );

    function swap(SwapParams calldata params) external returns (uint256 amountOut);
    function swapAndReinvest(SwapAndReinvestParams calldata params) external returns (uint256 invested);
    function swapAndHedge(SwapAndHedgeParams calldata params) external returns (uint256 invested);
    function quoteSwap(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

    // --- Pausable ---
    function pause() external;
    function unpause() external;
}
