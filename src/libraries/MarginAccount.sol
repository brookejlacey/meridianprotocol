// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MeridianMath} from "./MeridianMath.sol";

/// @title MarginAccount
/// @notice Library for margin calculation math.
/// @dev All values are 18-decimal WAD. Margin ratio = collateral / borrow.
///      A ratio > liquidationThreshold means the account is healthy.
///      A ratio <= liquidationThreshold means the account is liquidatable.
///
///      Liquidation penalty is applied as a percentage of the shortfall.
library MarginAccount {
    using MeridianMath for uint256;

    /// @notice Aggregated position data for margin calculation
    struct Position {
        uint256 collateralValue; // Total risk-adjusted collateral value (USD, 18 dec)
        uint256 borrowValue;     // Total borrow/obligation value (USD, 18 dec)
    }

    /// @notice Calculate margin ratio (WAD-scaled)
    /// @param position The aggregated position
    /// @return ratio Collateral / borrow in WAD (1e18 = 100%). Returns type(uint256).max if no borrows.
    function marginRatio(Position memory position) internal pure returns (uint256 ratio) {
        if (position.borrowValue == 0) return type(uint256).max;
        ratio = MeridianMath.wadDiv(position.collateralValue, position.borrowValue);
    }

    /// @notice Check if a position is healthy
    /// @param position The aggregated position
    /// @param liquidationThreshold WAD-scaled threshold (e.g., 1.1e18 = 110%)
    /// @return healthy True if margin ratio > threshold (or no borrows)
    function isHealthy(
        Position memory position,
        uint256 liquidationThreshold
    ) internal pure returns (bool healthy) {
        if (position.borrowValue == 0) return true;
        return marginRatio(position) > liquidationThreshold;
    }

    /// @notice Calculate the shortfall amount (how much collateral is missing)
    /// @param position The aggregated position
    /// @param liquidationThreshold WAD-scaled threshold
    /// @return shortfall Amount of collateral value below threshold. 0 if healthy.
    function shortfall(
        Position memory position,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (position.borrowValue == 0) return 0;
        uint256 required = MeridianMath.wadMul(position.borrowValue, liquidationThreshold);
        if (position.collateralValue >= required) return 0;
        unchecked { return required - position.collateralValue; }
    }

    /// @notice Calculate liquidation penalty
    /// @param shortfallAmount The collateral shortfall
    /// @param penaltyBps Penalty in basis points (e.g., 500 = 5%)
    /// @return penalty Penalty amount in USD value
    function liquidationPenalty(
        uint256 shortfallAmount,
        uint256 penaltyBps
    ) internal pure returns (uint256 penalty) {
        penalty = MeridianMath.bpsMul(shortfallAmount, penaltyBps);
    }

    /// @notice Calculate maximum withdrawable collateral value that keeps position healthy
    /// @param position The aggregated position
    /// @param liquidationThreshold WAD-scaled threshold
    /// @return maxWithdraw Maximum value that can be withdrawn
    function maxWithdrawable(
        Position memory position,
        uint256 liquidationThreshold
    ) internal pure returns (uint256 maxWithdraw) {
        if (position.borrowValue == 0) return position.collateralValue;
        uint256 required = MeridianMath.wadMul(position.borrowValue, liquidationThreshold);
        if (position.collateralValue <= required) return 0;
        unchecked { return position.collateralValue - required; }
    }
}
