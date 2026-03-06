// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IHedgeRouter {
    struct InvestAndHedgeParams {
        address vault;        // ForgeVault address
        uint8 trancheId;      // 0=Senior, 1=Mezzanine, 2=Equity
        uint256 investAmount; // Amount to invest in vault
        address cds;          // Existing CDS to buy protection on
        uint256 maxPremium;   // Maximum premium willing to pay
    }

    struct CreateAndHedgeParams {
        address vault;
        uint8 trancheId;
        uint256 investAmount;
        uint256 protectionAmount;
        uint256 premiumRate;
        uint256 maturity;
        address oracle;
        uint256 paymentInterval;
        uint256 maxPremium;
    }

    event HedgeExecuted(
        address indexed user,
        address indexed vault,
        uint8 trancheId,
        uint256 investAmount,
        address cds
    );

    event HedgeCreated(
        address indexed user,
        address indexed vault,
        uint8 trancheId,
        uint256 investAmount,
        address cds
    );

    function investAndHedge(InvestAndHedgeParams calldata params) external;
    function createAndHedge(CreateAndHedgeParams calldata params) external;
    function quoteHedge(address vault, uint256 investAmount, uint256 tenorDays)
        external view returns (uint256 spreadBps, uint256 estimatedPremium);

    // --- Pausable ---
    function pause() external;
    function unpause() external;
}
