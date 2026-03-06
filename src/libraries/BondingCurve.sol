// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MeridianMath} from "./MeridianMath.sol";

/// @title BondingCurve
/// @notice Utilization-based spread pricing for CDS AMM pools.
/// @dev Spread model: spread = baseSpread + slope * u^2 / (1 - u)
///      where u = utilization (WAD-scaled, 0 to <1e18).
///
///      Properties:
///      - At 0% utilization: spread = baseSpread
///      - At 50% utilization: spread = baseSpread + slope * 0.5
///      - At 80% utilization: spread = baseSpread + slope * 3.2
///      - At 90% utilization: spread = baseSpread + slope * 8.1
///      - Asymptotic at 100%: protection can never fully deplete the pool
///
///      This is analogous to Aave/Compound interest rate models but applied
///      to credit default swap pricing. Higher pool utilization = more expensive
///      protection, creating natural supply/demand equilibrium.
library BondingCurve {
    using MeridianMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant MAX_UTILIZATION = 95e16; // 95% cap

    /// @notice Calculate the instantaneous annual spread at a given utilization
    /// @param baseSpreadWad Base annual spread in WAD (e.g., 0.02e18 = 2%)
    /// @param slopeWad Slope parameter in WAD — controls curve steepness
    /// @param utilizationWad Current utilization in WAD (0 to <1e18)
    /// @return spreadWad Annual spread in WAD
    function getSpread(
        uint256 baseSpreadWad,
        uint256 slopeWad,
        uint256 utilizationWad
    ) internal pure returns (uint256 spreadWad) {
        if (utilizationWad == 0) return baseSpreadWad;
        if (utilizationWad >= WAD) utilizationWad = MAX_UTILIZATION;

        // spread = base + slope * u^2 / (1 - u)
        uint256 uSquared = MeridianMath.wadMul(utilizationWad, utilizationWad);
        uint256 oneMinusU = WAD - utilizationWad;
        uint256 curveComponent = MeridianMath.wadDiv(uSquared, oneMinusU);
        spreadWad = baseSpreadWad + MeridianMath.wadMul(slopeWad, curveComponent);
    }

    /// @notice Calculate the premium cost to buy `notional` protection from a pool
    /// @dev Integrates along the bonding curve from current utilization to new utilization.
    ///      Uses trapezoidal approximation with N=10 steps for accuracy.
    /// @param notional Protection amount to purchase
    /// @param totalLiquidity Total pool liquidity (LP deposits + accrued premiums)
    /// @param totalProtection Current outstanding protection sold
    /// @param baseSpreadWad Base annual spread in WAD
    /// @param slopeWad Slope parameter in WAD
    /// @param tenorSeconds Duration of the protection in seconds
    /// @return premium Total premium cost for this protection purchase
    function quotePremium(
        uint256 notional,
        uint256 totalLiquidity,
        uint256 totalProtection,
        uint256 baseSpreadWad,
        uint256 slopeWad,
        uint256 tenorSeconds
    ) internal pure returns (uint256 premium) {
        require(totalLiquidity > 0, "BondingCurve: no liquidity");
        require(
            totalProtection + notional <= MeridianMath.wadMul(totalLiquidity, MAX_UTILIZATION),
            "BondingCurve: exceeds max utilization"
        );

        // Integrate spread over the utilization change using trapezoidal rule (N=10)
        // For tiny notionals (< 10 wei), reduce to single step to prevent underflow
        uint256 steps = 10;
        uint256 stepSize = notional / steps;
        if (stepSize == 0) {
            steps = 1;
            stepSize = notional;
        }

        uint256 totalSpread;
        uint256 currentProtection = totalProtection;

        for (uint256 i = 0; i < steps;) {
            uint256 chunk;
            unchecked {
                chunk = (i == steps - 1) ? notional - (stepSize * (steps - 1)) : stepSize;
            }
            if (chunk == 0) { unchecked { ++i; } continue; }

            // Utilization at midpoint of this chunk
            uint256 midProtection;
            unchecked { midProtection = currentProtection + chunk / 2; }
            uint256 util = MeridianMath.wadDiv(midProtection, totalLiquidity);
            if (util > MAX_UTILIZATION) util = MAX_UTILIZATION;

            uint256 spreadAtMid = getSpread(baseSpreadWad, slopeWad, util);

            // Premium for this chunk = chunk * spread * tenor / YEAR
            uint256 chunkPremium = MeridianMath.wadMul(chunk, spreadAtMid);
            unchecked {
                chunkPremium = chunkPremium * tenorSeconds / YEAR;
                totalSpread += chunkPremium;
                currentProtection += chunk;
                ++i;
            }
        }

        premium = totalSpread;
    }

    /// @notice Calculate utilization ratio
    /// @param totalProtection Outstanding protection sold
    /// @param totalLiquidity Total pool liquidity
    /// @return utilizationWad Utilization in WAD
    function utilization(
        uint256 totalProtection,
        uint256 totalLiquidity
    ) internal pure returns (uint256 utilizationWad) {
        if (totalLiquidity == 0) return 0;
        utilizationWad = MeridianMath.wadDiv(totalProtection, totalLiquidity);
        if (utilizationWad > WAD) utilizationWad = WAD;
    }
}
