// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MeridianMath} from "../libraries/MeridianMath.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";
import {IAIRiskOracle} from "../interfaces/IAIRiskOracle.sol";

/// @title ShieldPricer
/// @notice Quotes indicative CDS spreads using public pool-level metrics.
/// @dev All inputs are Zone 1 (public aggregate data). No individual position
///      data is needed. The pricing model is a simplified credit spread curve:
///
///      spread = baseRate
///             + (1 - collateralRatio) * riskMultiplier
///             + utilizationSurcharge
///             + tenorAdjustment
///
///      All values in basis points (1 bps = 0.01%).
contract ShieldPricer {
    using MeridianMath for uint256;

    // --- Structs ---
    struct RiskMetrics {
        uint256 collateralRatio; // WAD-scaled (1e18 = 100% collateralized)
        uint256 utilization;     // WAD-scaled (outstanding protection / total capacity)
        uint256 poolTvl;         // Total value locked in the reference vault
        IForgeVault.PoolStatus poolStatus;
    }

    struct PricingParams {
        uint256 baseRateBps;       // Minimum spread in bps (e.g., 50 = 0.5%)
        uint256 riskMultiplierBps; // Multiplier for undercollateralization (e.g., 2000)
        uint256 utilizationKinkBps; // Utilization threshold for surcharge (e.g., 8000 = 80%)
        uint256 utilizationSurchargeBps; // Extra spread above kink (e.g., 500)
        uint256 tenorScalerBps;    // Annualized tenor adjustment (e.g., 100 per year)
        uint256 maxSpreadBps;      // Cap on total spread (e.g., 5000 = 50%)
    }

    // --- State ---
    PricingParams public defaultParams;
    mapping(address vault => PricingParams) public vaultOverrides;
    mapping(address vault => bool) public hasOverride;

    address public owner;

    /// @notice AI risk oracle for dynamic credit risk pricing
    IAIRiskOracle public riskOracle;
    /// @notice Multiplier for converting PD to collateral ratio reduction (WAD, default 5e18)
    uint256 public riskAdjustmentWad = 5e18;

    // --- Events ---
    event DefaultParamsUpdated(PricingParams params);
    event VaultOverrideSet(address indexed vault, PricingParams params);
    event RiskOracleUpdated(address indexed riskOracle);
    event RiskAdjustmentUpdated(uint256 newAdjustment);

    modifier onlyOwner() {
        require(msg.sender == owner, "ShieldPricer: not owner");
        _;
    }

    constructor(PricingParams memory defaultParams_) {
        owner = msg.sender;
        defaultParams = defaultParams_;
    }

    /// @notice Get indicative spread for a CDS on a vault
    /// @param vault The ForgeVault being referenced
    /// @param notionalAmount Size of protection (for size adjustment)
    /// @param tenorDays Duration of protection in days
    /// @return spreadBps The indicative annual spread in basis points
    function getIndicativeSpread(
        address vault,
        uint256 notionalAmount,
        uint256 tenorDays
    ) external view returns (uint256 spreadBps) {
        RiskMetrics memory metrics = getPoolRiskMetrics(vault);
        PricingParams memory params = _getParams(vault);

        spreadBps = _calculateSpread(metrics, params, notionalAmount, tenorDays);
    }

    /// @notice Get public risk metrics for a vault
    /// @param vault The ForgeVault to assess
    /// @return metrics Public aggregate risk data
    function getPoolRiskMetrics(address vault) public view returns (RiskMetrics memory metrics) {
        IForgeVault.PoolMetrics memory pool = IForgeVault(vault).getPoolMetrics();

        // Collateral ratio = (TVL - losses) / TVL, approximated as
        // totalDeposited / totalDeposited (simplified for MVP)
        // In production, this would factor in mark-to-market of underlying
        if (pool.totalDeposited > 0) {
            metrics.collateralRatio = MeridianMath.WAD; // 100% if no losses
        }

        // Overlay AI risk assessment if oracle is set and score is fresh
        if (address(riskOracle) != address(0)) {
            try riskOracle.getDefaultProbability(vault) returns (uint256 pd) {
                // Convert PD to collateral ratio reduction:
                // Higher PD → lower effective collateral ratio
                // adjustment = pd * riskAdjustmentWad (e.g., 2% PD * 5x = 10% reduction)
                uint256 adjustment = MeridianMath.wadMul(pd, riskAdjustmentWad);
                if (adjustment < metrics.collateralRatio) {
                    metrics.collateralRatio -= adjustment;
                } else {
                    metrics.collateralRatio = 0;
                }
            } catch {
                // Oracle unavailable or stale — fall through with existing ratio
            }
        }

        metrics.poolTvl = pool.totalDeposited;
        metrics.poolStatus = pool.status;
        metrics.utilization = 0; // Updated when CDS marketplace tracks outstanding protection
    }

    /// @notice Pure spread calculation for testing
    function calculateSpread(
        RiskMetrics memory metrics,
        PricingParams memory params,
        uint256 notionalAmount,
        uint256 tenorDays
    ) external pure returns (uint256) {
        return _calculateSpread(metrics, params, notionalAmount, tenorDays);
    }

    // --- Admin ---

    address public pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ShieldPricer: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "ShieldPricer: not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    function setDefaultParams(PricingParams calldata params_) external onlyOwner {
        defaultParams = params_;
        emit DefaultParamsUpdated(params_);
    }

    function setVaultOverride(address vault, PricingParams calldata params_) external onlyOwner {
        vaultOverrides[vault] = params_;
        hasOverride[vault] = true;
        emit VaultOverrideSet(vault, params_);
    }

    /// @notice Set the AI risk oracle for dynamic credit risk pricing
    function setRiskOracle(address riskOracle_) external onlyOwner {
        riskOracle = IAIRiskOracle(riskOracle_);
        emit RiskOracleUpdated(riskOracle_);
    }

    /// @notice Set the risk adjustment multiplier (WAD)
    function setRiskAdjustment(uint256 adjustment) external onlyOwner {
        riskAdjustmentWad = adjustment;
        emit RiskAdjustmentUpdated(adjustment);
    }

    // --- Internal ---

    function _calculateSpread(
        RiskMetrics memory metrics,
        PricingParams memory params,
        uint256 /* notionalAmount */,
        uint256 tenorDays
    ) internal pure returns (uint256 spreadBps) {
        // Component 1: Base rate
        spreadBps = params.baseRateBps;

        // Component 2: Undercollateralization risk
        // spread += (1 - collateralRatio) * riskMultiplier
        if (metrics.collateralRatio < MeridianMath.WAD) {
            uint256 deficit = MeridianMath.WAD - metrics.collateralRatio;
            spreadBps += MeridianMath.wadMul(deficit, params.riskMultiplierBps * MeridianMath.WAD / MeridianMath.BPS)
                * MeridianMath.BPS / MeridianMath.WAD;
        }

        // Component 3: Utilization surcharge (above kink)
        uint256 utilizationBps = (metrics.utilization * MeridianMath.BPS) / MeridianMath.WAD;
        if (utilizationBps > params.utilizationKinkBps) {
            spreadBps += params.utilizationSurchargeBps;
        }

        // Component 4: Tenor adjustment (longer = more expensive)
        // Linear scaling: tenorScaler * (days / 365)
        if (tenorDays > 0) {
            spreadBps += (params.tenorScalerBps * tenorDays) / 365;
        }

        // Component 5: Pool status penalty
        if (metrics.poolStatus == IForgeVault.PoolStatus.Impaired) {
            spreadBps += 1000; // +10% for impaired pools
        } else if (metrics.poolStatus == IForgeVault.PoolStatus.Defaulted) {
            spreadBps = params.maxSpreadBps; // Max spread for defaulted
        }

        // Cap at max spread
        if (spreadBps > params.maxSpreadBps) {
            spreadBps = params.maxSpreadBps;
        }
    }

    function _getParams(address vault) internal view returns (PricingParams memory) {
        if (hasOverride[vault]) {
            return vaultOverrides[vault];
        }
        return defaultParams;
    }
}
