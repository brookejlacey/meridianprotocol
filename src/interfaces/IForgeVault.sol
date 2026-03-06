// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IForgeVault {
    // --- Enums ---
    enum PoolStatus {
        Active,
        Impaired,
        Defaulted,
        Matured
    }

    // --- Structs ---
    struct TrancheParams {
        uint256 targetApr; // basis points (e.g., 500 = 5%)
        uint256 allocationPct; // percentage of pool (e.g., 70 = 70%)
        address token; // tranche token address
    }

    struct PoolMetrics {
        uint256 totalDeposited;
        uint256 totalYieldReceived;
        uint256 totalYieldDistributed;
        uint256 lastDistribution;
        PoolStatus status;
    }

    // --- Events ---
    event Invested(address indexed investor, uint8 indexed trancheId, uint256 amount);
    event YieldReceived(uint256 amount, uint256 timestamp);
    event WaterfallDistributed(uint256 totalYield, uint256[3] trancheAmounts);
    event YieldClaimed(address indexed investor, uint8 indexed trancheId, uint256 amount);
    event Withdrawn(address indexed investor, uint8 indexed trancheId, uint256 amount);
    event PoolStatusChanged(PoolStatus oldStatus, PoolStatus newStatus);
    event TrancheRatiosAdjusted(uint256[3] oldPcts, uint256[3] newPcts);
    event ProtocolFeeCollected(uint256 amount);
    event ProtocolFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    // --- Core Functions ---
    function invest(uint8 trancheId, uint256 amount) external;
    function investFor(uint8 trancheId, uint256 amount, address beneficiary) external;
    function claimYield(uint8 trancheId) external returns (uint256);
    function withdraw(uint8 trancheId, uint256 amount) external;
    function triggerWaterfall() external;

    // --- View Functions ---
    function getPoolMetrics() external view returns (PoolMetrics memory);
    function getTrancheParams(uint8 trancheId) external view returns (TrancheParams memory);
    function getClaimableYield(address investor, uint8 trancheId) external view returns (uint256);
    function originator() external view returns (address);
    function poolStatus() external view returns (PoolStatus);
    function underlyingAsset() external view returns (IERC20);
    function adjustTrancheRatios(uint256[3] calldata newPcts) external;

    // --- Protocol Fee Functions ---
    function treasury() external view returns (address);
    function protocolFeeBps() external view returns (uint256);
    function totalProtocolFeesCollected() external view returns (uint256);
    function setProtocolFee(uint256 newFeeBps) external;

    // --- Pausable Functions ---
    function pause() external;
    function unpause() external;
}
