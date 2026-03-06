// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ISecondaryMarketRouter} from "./interfaces/ISecondaryMarketRouter.sol";
import {IForgeVault} from "./interfaces/IForgeVault.sol";
import {ICDSContract} from "./interfaces/ICDSContract.sol";

/// @title SecondaryMarketRouter
/// @notice Wraps DEX swaps with protocol composability for tranche tokens.
/// @dev Stateless router — user is the direct owner of all positions.
///      Token flow: user approves router -> router pulls tokens -> swaps on DEX ->
///      optionally reinvests/hedges -> returns tokens to user.
///
///      Composability patterns:
///      1. swap(): pure DEX swap (tranche token <-> tranche token, or tranche <-> underlying)
///      2. swapAndReinvest(): sell tranche token -> get underlying -> invest in different tranche/vault
///      3. swapAndHedge(): sell tranche token -> get underlying -> invest + buy CDS protection
contract SecondaryMarketRouter is ISecondaryMarketRouter, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice DEX router interface (MockDEXRouter in testing, Uniswap/TraderJoe in production)
    address public immutable dex;
    address public pauseAdmin;

    constructor(address dex_, address pauseAdmin_) {
        require(dex_ != address(0), "SecondaryMarketRouter: zero dex");
        require(pauseAdmin_ != address(0), "SecondaryMarketRouter: zero pause admin");
        dex = dex_;
        pauseAdmin = pauseAdmin_;
    }

    /// @notice Simple swap via DEX
    function swap(SwapParams calldata p) external override nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(p.amountIn > 0, "SecondaryMarketRouter: zero amount");

        IERC20(p.tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);
        IERC20(p.tokenIn).approve(dex, p.amountIn);

        // Call DEX swap: swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient)
        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,address)",
                p.tokenIn, p.tokenOut, p.amountIn, p.minAmountOut, msg.sender
            )
        );
        require(success, "SecondaryMarketRouter: swap failed");
        amountOut = abi.decode(data, (uint256));

        IERC20(p.tokenIn).approve(dex, 0);

        emit SwapExecuted(msg.sender, p.tokenIn, p.tokenOut, p.amountIn, amountOut);
    }

    /// @notice Sell tranche token on DEX, reinvest underlying into a different tranche
    function swapAndReinvest(SwapAndReinvestParams calldata p) external override nonReentrant whenNotPaused returns (uint256 invested) {
        require(p.amountIn > 0, "SecondaryMarketRouter: zero amount");
        require(p.vault != address(0), "SecondaryMarketRouter: zero vault");

        address underlying = address(IForgeVault(p.vault).underlyingAsset());

        // Pull tranche tokens and swap to underlying via DEX
        IERC20(p.tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);
        IERC20(p.tokenIn).approve(dex, p.amountIn);

        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,address)",
                p.tokenIn, underlying, p.amountIn, p.minUnderlying, address(this)
            )
        );
        require(success, "SecondaryMarketRouter: swap failed");
        invested = abi.decode(data, (uint256));

        IERC20(p.tokenIn).approve(dex, 0);

        // Reinvest underlying into target tranche (user is beneficiary)
        IERC20(underlying).approve(p.vault, invested);
        IForgeVault(p.vault).investFor(p.trancheId, invested, msg.sender);
        IERC20(underlying).approve(p.vault, 0);

        emit SwapAndReinvested(msg.sender, p.tokenIn, p.vault, p.trancheId, p.amountIn, invested);
    }

    /// @notice Sell tranche token on DEX, reinvest + buy CDS hedge
    function swapAndHedge(SwapAndHedgeParams calldata p) external override nonReentrant whenNotPaused returns (uint256 invested) {
        require(p.amountIn > 0, "SecondaryMarketRouter: zero amount");
        require(p.vault != address(0), "SecondaryMarketRouter: zero vault");
        require(p.cds != address(0), "SecondaryMarketRouter: zero cds");

        address underlying = address(IForgeVault(p.vault).underlyingAsset());

        // Pull tranche tokens and swap to underlying
        IERC20(p.tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);
        IERC20(p.tokenIn).approve(dex, p.amountIn);

        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "swap(address,address,uint256,uint256,address)",
                p.tokenIn, underlying, p.amountIn, p.minUnderlying, address(this)
            )
        );
        require(success, "SecondaryMarketRouter: swap failed");
        uint256 underlyingReceived = abi.decode(data, (uint256));

        IERC20(p.tokenIn).approve(dex, 0);

        // Split: invest the main amount, reserve maxPremium for hedge
        require(underlyingReceived > p.maxPremium, "SecondaryMarketRouter: insufficient for hedge");
        invested = underlyingReceived - p.maxPremium;

        // Invest
        IERC20(underlying).approve(p.vault, invested);
        IForgeVault(p.vault).investFor(p.trancheId, invested, msg.sender);
        IERC20(underlying).approve(p.vault, 0);

        // Hedge
        require(
            ICDSContract(p.cds).getStatus() == ICDSContract.CDSStatus.Active,
            "SecondaryMarketRouter: CDS not active"
        );
        ICDSContract.CDSTerms memory terms = ICDSContract(p.cds).getTerms();
        IERC20(underlying).approve(p.cds, p.maxPremium);
        ICDSContract(p.cds).buyProtectionFor(terms.protectionAmount, p.maxPremium, msg.sender);
        IERC20(underlying).approve(p.cds, 0);

        // Return unused premium
        uint256 remaining = IERC20(underlying).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(underlying).safeTransfer(msg.sender, remaining);
        }
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == pauseAdmin, "SecondaryMarketRouter: not pause admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == pauseAdmin, "SecondaryMarketRouter: not pause admin");
        _unpause();
    }

    // --- Pause Admin Transfer (Two-Step) ---

    address public pendingPauseAdmin;

    event PauseAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event PauseAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    function transferPauseAdmin(address newAdmin) external {
        require(msg.sender == pauseAdmin, "SecondaryMarketRouter: not pause admin");
        require(newAdmin != address(0), "SecondaryMarketRouter: zero address");
        pendingPauseAdmin = newAdmin;
        emit PauseAdminTransferStarted(pauseAdmin, newAdmin);
    }

    function acceptPauseAdmin() external {
        require(msg.sender == pendingPauseAdmin, "SecondaryMarketRouter: not pending admin");
        emit PauseAdminTransferred(pauseAdmin, msg.sender);
        pauseAdmin = msg.sender;
        pendingPauseAdmin = address(0);
    }

    /// @notice Quote a swap (view)
    function quoteSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        (bool success, bytes memory data) = dex.staticcall(
            abi.encodeWithSignature("quoteSwap(address,address,uint256)", tokenIn, tokenOut, amountIn)
        );
        if (success && data.length >= 32) {
            amountOut = abi.decode(data, (uint256));
        }
    }
}
