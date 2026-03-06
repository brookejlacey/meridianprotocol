// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Interface matching WaterfallDistributor library structs
interface IWaterfallDistributor {
    struct TrancheState {
        uint256 targetApr;      // Annual target yield in basis points
        uint256 totalShares;    // Total shares outstanding
        uint256 depositValue;   // Total value deposited
    }

    struct DistributionResult {
        uint256[3] amounts;         // Amount distributed to each tranche
        uint256 totalDistributed;
    }

    struct LossResult {
        uint256[3] losses;          // Loss allocated to each tranche
        uint256 totalAbsorbed;
    }
}
