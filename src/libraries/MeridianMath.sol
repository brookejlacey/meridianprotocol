// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title MeridianMath
/// @notice Fixed-point math utilities for waterfall calculations and yield distribution
/// @dev Uses 18-decimal fixed-point representation (WAD = 1e18).
///      Hot-path functions use unchecked math where overflow is impossible.
library MeridianMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000; // basis points denominator

    /// @notice Multiply two WAD-denominated values
    /// @dev Checked multiplication prevents silent overflow; division by constant is safe
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    /// @notice Divide two WAD-denominated values
    /// @dev Checked multiplication prevents silent overflow; requires b > 0
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "MeridianMath: div by zero");
        return (a * WAD) / b;
    }

    /// @notice Convert basis points to WAD
    function bpsToWad(uint256 bps) internal pure returns (uint256) {
        return (bps * WAD) / BPS;
    }

    /// @notice Calculate percentage of an amount (basis points)
    function bpsMul(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS;
    }

    /// @notice Return the minimum of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Return the maximum of two values
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Subtract with floor at zero (no underflow)
    function subFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : 0;
        }
    }
}
