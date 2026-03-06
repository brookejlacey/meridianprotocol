// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {CDSContract} from "./CDSContract.sol";
import {ICDSContract} from "../interfaces/ICDSContract.sol";

/// @title ShieldFactory
/// @notice Creates and registers CDSContract instances.
/// @dev Tracks all CDS contracts by ID, by reference asset (ForgeVault), and by participant.
contract ShieldFactory {
    // --- State ---
    uint256 public cdsCount;
    mapping(uint256 id => address cds) public cdsContracts;
    mapping(address referenceAsset => uint256[] cdsIds) public cdsByReferenceAsset;
    mapping(address participant => uint256[] cdsIds) public cdsByParticipant;

    // --- Events ---
    event CDSCreated(
        uint256 indexed cdsId,
        address indexed cds,
        address indexed referenceAsset,
        address creator,
        uint256 protectionAmount,
        uint256 premiumRate,
        uint256 maturity
    );

    // --- Structs ---
    struct CreateCDSParams {
        address referenceAsset;    // ForgeVault being insured
        uint256 protectionAmount;  // Notional
        uint256 premiumRate;       // Annual spread in bps
        uint256 maturity;          // Expiry timestamp
        address collateralToken;   // Token used for collateral/premiums
        address oracle;            // CreditEventOracle address
        uint256 paymentInterval;   // Premium payment interval (e.g., 30 days)
    }

    /// @notice Create a new CDS contract
    /// @param params CDS creation parameters
    /// @return cdsAddress The deployed CDSContract address
    function createCDS(CreateCDSParams calldata params) external returns (address cdsAddress) {
        require(params.protectionAmount > 0, "ShieldFactory: zero notional");
        require(params.premiumRate > 0 && params.premiumRate <= 10_000, "ShieldFactory: invalid premium rate");
        require(params.maturity > block.timestamp, "ShieldFactory: maturity in past");
        require(params.maturity <= block.timestamp + 10 * 365 days, "ShieldFactory: maturity too far");
        require(params.paymentInterval > 0, "ShieldFactory: zero interval");

        uint256 cdsId = cdsCount++;

        ICDSContract.CDSTerms memory terms = ICDSContract.CDSTerms({
            referenceAsset: params.referenceAsset,
            protectionAmount: params.protectionAmount,
            premiumRate: params.premiumRate,
            maturity: params.maturity,
            collateralToken: params.collateralToken
        });

        CDSContract cds = new CDSContract(
            terms,
            params.oracle,
            params.paymentInterval,
            address(this)
        );

        cdsAddress = address(cds);
        cdsContracts[cdsId] = cdsAddress;
        cdsByReferenceAsset[params.referenceAsset].push(cdsId);
        cdsByParticipant[msg.sender].push(cdsId);

        emit CDSCreated(
            cdsId,
            cdsAddress,
            params.referenceAsset,
            msg.sender,
            params.protectionAmount,
            params.premiumRate,
            params.maturity
        );
    }

    /// @notice Get all CDS IDs referencing a specific vault
    function getCDSForVault(address referenceAsset) external view returns (uint256[] memory) {
        return cdsByReferenceAsset[referenceAsset];
    }

    /// @notice Get all CDS IDs for a participant
    function getParticipantCDS(address participant) external view returns (uint256[] memory) {
        return cdsByParticipant[participant];
    }

    /// @notice Get CDS contract address by ID
    function getCDS(uint256 cdsId) external view returns (address) {
        return cdsContracts[cdsId];
    }
}
