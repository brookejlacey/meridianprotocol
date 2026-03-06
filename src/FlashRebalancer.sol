// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IForgeVault} from "./interfaces/IForgeVault.sol";
import {IFlashBorrower, IFlashLender} from "./interfaces/IFlashLender.sol";

/// @title FlashRebalancer
/// @notice Atomic cross-tranche position rebalancing using flash loans.
/// @dev Flow: flash borrow → withdraw from source tranche → invest in target tranche → repay.
///      This lets a Senior holder rotate to Equity (or vice versa) in a single atomic tx.
///      No separate approval needed — the user only needs to approve this contract for
///      their tranche tokens (for the burn during withdraw).
///
///      Example: Alice has 100k in Senior (5% APR), wants to move to Equity (15% APR).
///      1. Flash borrow 100k underlying
///      2. Invest 100k in Equity tranche (user gets equity tokens)
///      3. Withdraw 100k from Senior tranche (burns senior tokens, gets underlying back)
///      4. Repay flash loan
///      Result: Alice atomically moved from Senior → Equity
contract FlashRebalancer is IFlashBorrower, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    IFlashLender public immutable FLASH_LENDER;
    address public pauseAdmin;

    // Transient state for flash loan callback
    struct RebalanceParams {
        address vault;
        address user;
        uint8 fromTranche;
        uint8 toTranche;
        uint256 amount;
    }
    RebalanceParams private _pending;
    bool private _inFlashLoan;

    event Rebalanced(
        address indexed user,
        address indexed vault,
        uint8 fromTranche,
        uint8 toTranche,
        uint256 amount
    );

    constructor(address flashLender_, address pauseAdmin_) {
        require(flashLender_ != address(0), "FlashRebalancer: zero lender");
        require(pauseAdmin_ != address(0), "FlashRebalancer: zero pause admin");
        FLASH_LENDER = IFlashLender(flashLender_);
        pauseAdmin = pauseAdmin_;
    }

    /// @notice Rebalance a position from one tranche to another atomically
    /// @param vault The ForgeVault address
    /// @param fromTranche Source tranche ID (0=Senior, 1=Mezz, 2=Equity)
    /// @param toTranche Target tranche ID
    /// @param amount Amount to move
    /// @dev User must have approved this contract to spend their tranche tokens
    ///      (for the withdraw/burn step) AND approved the vault to spend underlying
    ///      (ForgeVault.invest pulls from msg.sender which is this contract).
    function rebalance(
        address vault,
        uint8 fromTranche,
        uint8 toTranche,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(vault != address(0), "FlashRebalancer: zero vault");
        require(fromTranche != toTranche, "FlashRebalancer: same tranche");
        require(amount > 0, "FlashRebalancer: zero amount");
        require(fromTranche < 3 && toTranche < 3, "FlashRebalancer: invalid tranche");

        address underlying = address(IForgeVault(vault).underlyingAsset());

        // Store params for callback
        _pending = RebalanceParams({
            vault: vault,
            user: msg.sender,
            fromTranche: fromTranche,
            toTranche: toTranche,
            amount: amount
        });
        _inFlashLoan = true;

        // Initiate flash loan
        FLASH_LENDER.flashLoan(underlying, amount, "");

        // Clear flag after flash loan completes
        _inFlashLoan = false;
    }

    /// @notice Flash loan callback — executes the rebalance
    /// @dev Called by the flash lender during flashLoan execution
    function onFlashLoan(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == address(FLASH_LENDER), "FlashRebalancer: not lender");
        require(_inFlashLoan, "FlashRebalancer: not in flash loan");

        RebalanceParams memory p = _pending;
        require(p.vault != address(0), "FlashRebalancer: no pending");

        IForgeVault vault = IForgeVault(p.vault);

        // Step 1: Approve vault to pull underlying from us, then invest in target tranche
        IERC20(token).approve(p.vault, amount);
        vault.investFor(p.toTranche, amount, p.user);

        // Step 2: Withdraw from source tranche (user must have approved us for their tranche tokens)
        //         We need the tranche token to transfer from user to us, then call withdraw.
        //         But ForgeVault.withdraw() checks msg.sender's shares, so user needs to
        //         have their tranche tokens transferred to us first.
        IForgeVault.TrancheParams memory trancheParams = vault.getTrancheParams(p.fromTranche);
        IERC20(trancheParams.token).safeTransferFrom(p.user, address(this), amount);

        // Now we hold the tranche tokens. But withdraw checks _shares[msg.sender].
        // Since the transfer hook updated the plaintext mirrors, our address now has shares.
        uint256 balBefore = IERC20(token).balanceOf(address(this));
        vault.withdraw(p.fromTranche, amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
        require(received >= amount, "FlashRebalancer: tranche ratio mismatch");

        // Step 3: Repay flash loan
        uint256 repayment = amount + fee;
        IERC20(token).approve(address(FLASH_LENDER), repayment);
        IERC20(token).safeTransfer(address(FLASH_LENDER), repayment);

        // Clear pending
        delete _pending;

        emit Rebalanced(p.user, p.vault, p.fromTranche, p.toTranche, amount);
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == pauseAdmin, "FlashRebalancer: not pause admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == pauseAdmin, "FlashRebalancer: not pause admin");
        _unpause();
    }

    // --- Pause Admin Transfer (Two-Step) ---

    address public pendingPauseAdmin;

    event PauseAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event PauseAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    function transferPauseAdmin(address newAdmin) external {
        require(msg.sender == pauseAdmin, "FlashRebalancer: not pause admin");
        require(newAdmin != address(0), "FlashRebalancer: zero address");
        pendingPauseAdmin = newAdmin;
        emit PauseAdminTransferStarted(pauseAdmin, newAdmin);
    }

    function acceptPauseAdmin() external {
        require(msg.sender == pendingPauseAdmin, "FlashRebalancer: not pending admin");
        emit PauseAdminTransferred(pauseAdmin, msg.sender);
        pauseAdmin = msg.sender;
        pendingPauseAdmin = address(0);
    }
}
