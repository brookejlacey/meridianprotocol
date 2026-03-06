// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title PremiumEngine
/// @notice Library for CDS premium calculation and accrual tracking.
/// @dev Premiums accrue linearly based on notional * annualSpread * time.
///      All amounts in underlying token units (18 decimals).
///      Premiums are paid periodically by the buyer to the seller.
library PremiumEngine {
    using MeridianMath for uint256;

    uint256 internal constant YEAR = 365 days;

    struct PremiumState {
        uint256 notional;          // Protection notional amount
        uint256 annualSpreadBps;   // Annual premium rate in basis points
        uint256 startTime;         // When protection began
        uint256 maturity;          // When protection expires
        uint256 lastPaymentTime;   // Last premium payment timestamp
        uint256 totalPaid;         // Total premiums paid to date
    }

    /// @notice Calculate total premium for a CDS over its full duration
    /// @param notional Protection amount
    /// @param annualSpreadBps Annual spread in basis points
    /// @param durationDays Protection duration in days
    /// @return totalPremium Total premium owed over the duration
    function calculateTotalPremium(
        uint256 notional,
        uint256 annualSpreadBps,
        uint256 durationDays
    ) internal pure returns (uint256 totalPremium) {
        // premium = notional * spread/BPS * days/365
        totalPremium = (notional * annualSpreadBps * durationDays) / (MeridianMath.BPS * 365);
    }

    /// @notice Calculate premium accrued since last payment
    /// @param state Current premium state
    /// @param currentTime Current block timestamp
    /// @return accrued Premium amount accrued since lastPaymentTime
    function accruedPremium(
        PremiumState memory state,
        uint256 currentTime
    ) internal pure returns (uint256 accrued) {
        if (currentTime <= state.lastPaymentTime) return 0;

        // Cap at maturity
        uint256 endTime = currentTime < state.maturity ? currentTime : state.maturity;
        if (endTime <= state.lastPaymentTime) return 0;

        uint256 elapsed = endTime - state.lastPaymentTime;

        // accrued = notional * spreadBps / BPS * elapsed / YEAR
        accrued = (state.notional * state.annualSpreadBps * elapsed) / (MeridianMath.BPS * YEAR);
    }

    /// @notice Calculate the upfront premium deposit required from the buyer
    /// @dev Buyer must deposit enough premium to cover the first payment period
    /// @param notional Protection amount
    /// @param annualSpreadBps Annual spread in bps
    /// @param paymentIntervalDays Days between premium payments
    /// @return deposit Required upfront deposit
    function requiredDeposit(
        uint256 notional,
        uint256 annualSpreadBps,
        uint256 paymentIntervalDays
    ) internal pure returns (uint256 deposit) {
        // Require 1 full payment period upfront
        deposit = calculateTotalPremium(notional, annualSpreadBps, paymentIntervalDays);
    }

    /// @notice Calculate premium per day (for streaming/display)
    /// @param notional Protection amount
    /// @param annualSpreadBps Annual spread in bps
    /// @return dailyPremium Premium per day
    function dailyPremium(
        uint256 notional,
        uint256 annualSpreadBps
    ) internal pure returns (uint256) {
        return (notional * annualSpreadBps) / (MeridianMath.BPS * 365);
    }

    /// @notice Check if a premium payment is overdue
    /// @param state Current premium state
    /// @param currentTime Current timestamp
    /// @param paymentInterval Maximum time between payments
    /// @return overdue True if payment is overdue
    function isPaymentOverdue(
        PremiumState memory state,
        uint256 currentTime,
        uint256 paymentInterval
    ) internal pure returns (bool overdue) {
        return currentTime > state.lastPaymentTime + paymentInterval;
    }

    /// @notice Calculate remaining premium from current time to maturity
    /// @param state Current premium state
    /// @param currentTime Current timestamp
    /// @return remaining Premium still owed (seconds-precise, no day truncation)
    function remainingPremium(
        PremiumState memory state,
        uint256 currentTime
    ) internal pure returns (uint256 remaining) {
        if (currentTime >= state.maturity) return 0;
        uint256 remainingSeconds = state.maturity - currentTime;
        // premium = notional * spreadBps / BPS * remainingSeconds / YEAR
        remaining = (state.notional * state.annualSpreadBps * remainingSeconds) / (MeridianMath.BPS * YEAR);
    }
}
