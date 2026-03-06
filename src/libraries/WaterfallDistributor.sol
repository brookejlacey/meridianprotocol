// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MeridianMath} from "./MeridianMath.sol";

/// @title WaterfallDistributor
/// @notice Pure library for structured credit waterfall calculations.
/// @dev Implements payment priority (Senior → Mezzanine → Equity) and
///      loss absorption (Equity → Mezzanine → Senior).
///
///      All functions are pure — no storage reads, no side effects.
///      Designed for fuzz testing with arbitrary inputs.
///
///      Convention: tranche indices are 0=Senior, 1=Mezzanine, 2=Equity
library WaterfallDistributor {
    using MeridianMath for uint256;

    uint256 internal constant NUM_TRANCHES = 3;

    struct TrancheState {
        uint256 targetApr;      // Annual target yield in basis points (e.g., 500 = 5%)
        uint256 totalShares;    // Total shares outstanding for this tranche
        uint256 depositValue;   // Total value deposited (for coupon calculations)
    }

    struct DistributionResult {
        uint256[3] amounts;     // Amount distributed to each tranche
        uint256 totalDistributed;
    }

    struct LossResult {
        uint256[3] losses;      // Loss allocated to each tranche
        uint256 totalAbsorbed;
    }

    /// @notice Distribute yield through the waterfall: Senior first, then Mezz, then Equity.
    /// @param totalYield Total yield available for distribution
    /// @param tranches Current state of all three tranches
    /// @param periodBps Fraction of the annual period being distributed (in bps of a year).
    ///                  e.g., 192 bps ≈ 1 week (700/365*100), 10000 = full year
    /// @return result Distribution amounts per tranche
    /// @dev Senior and Mezzanine have capped returns (targetApr-based).
    ///      Equity receives all remaining yield after senior obligations are met.
    ///      If yield is insufficient, senior gets what's available, and lower tranches get nothing.
    function distributeYield(
        uint256 totalYield,
        TrancheState[3] memory tranches,
        uint256 periodBps
    ) internal pure returns (DistributionResult memory result) {
        uint256 remaining = totalYield;

        // Senior: min(remaining, seniorCouponOwed)
        {
            uint256 seniorOwed = _couponOwed(tranches[0], periodBps);
            uint256 seniorAmount = remaining.min(seniorOwed);
            result.amounts[0] = seniorAmount;
            remaining -= seniorAmount;
        }

        // Mezzanine: min(remaining, mezzCouponOwed)
        {
            uint256 mezzOwed = _couponOwed(tranches[1], periodBps);
            uint256 mezzAmount = remaining.min(mezzOwed);
            result.amounts[1] = mezzAmount;
            remaining -= mezzAmount;
        }

        // Equity: gets all remainder (excess spread)
        result.amounts[2] = remaining;

        result.totalDistributed = totalYield;
    }

    /// @notice Allocate losses in reverse waterfall: Equity first, then Mezz, then Senior.
    /// @param totalLoss Total loss to absorb
    /// @param trancheValues Current value of each tranche (total deposits still outstanding)
    /// @return result Loss amounts per tranche
    /// @dev Equity absorbs first. If equity is wiped out, mezzanine absorbs next.
    ///      If mezzanine is also wiped, senior takes the remaining loss.
    function allocateLoss(
        uint256 totalLoss,
        uint256[3] memory trancheValues
    ) internal pure returns (LossResult memory result) {
        uint256 remaining = totalLoss;

        // Equity absorbs first (index 2)
        {
            uint256 equityLoss = remaining.min(trancheValues[2]);
            result.losses[2] = equityLoss;
            remaining -= equityLoss;
        }

        // Mezzanine absorbs next (index 1)
        {
            uint256 mezzLoss = remaining.min(trancheValues[1]);
            result.losses[1] = mezzLoss;
            remaining -= mezzLoss;
        }

        // Senior absorbs last (index 0) — should only happen in severe default
        {
            uint256 seniorLoss = remaining.min(trancheValues[0]);
            result.losses[0] = seniorLoss;
            remaining -= seniorLoss;
        }

        result.totalAbsorbed = totalLoss - remaining;
    }

    /// @notice Calculate the yield-per-share delta for a given distribution amount
    /// @param distributionAmount Amount distributed to this tranche
    /// @param totalShares Total shares outstanding in this tranche
    /// @return delta The yieldPerShare increment (WAD-scaled)
    /// @dev Returns 0 if totalShares is 0 (no holders, no distribution)
    function calculateYieldPerShareDelta(
        uint256 distributionAmount,
        uint256 totalShares
    ) internal pure returns (uint256 delta) {
        if (totalShares == 0) return 0;
        delta = MeridianMath.wadDiv(distributionAmount, totalShares);
    }

    /// @notice Calculate what a user is owed based on yieldPerShare deltas
    /// @param shares User's share count
    /// @param currentYieldPerShare Current cumulative yieldPerShare
    /// @param lastCheckpointYieldPerShare User's last checkpoint yieldPerShare
    /// @return owed Amount of yield owed to the user
    function calculateUserYield(
        uint256 shares,
        uint256 currentYieldPerShare,
        uint256 lastCheckpointYieldPerShare
    ) internal pure returns (uint256 owed) {
        if (currentYieldPerShare <= lastCheckpointYieldPerShare) return 0;
        uint256 delta = currentYieldPerShare - lastCheckpointYieldPerShare;
        owed = MeridianMath.wadMul(shares, delta);
    }

    /// @notice Calculate the coupon owed for a tranche over a period
    /// @param tranche The tranche state
    /// @param periodBps Period as basis points of a year (10000 = full year)
    /// @return owed Coupon amount owed
    function _couponOwed(
        TrancheState memory tranche,
        uint256 periodBps
    ) private pure returns (uint256 owed) {
        if (tranche.totalShares == 0 || tranche.targetApr == 0) return 0;
        // owed = depositValue * targetApr/BPS * periodBps/BPS
        // Split to prevent triple-multiply overflow for large deposits
        owed = MeridianMath.bpsMul(
            MeridianMath.bpsMul(tranche.depositValue, tranche.targetApr),
            periodBps
        );
    }
}
