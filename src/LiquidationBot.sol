// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICreditEventOracle} from "./interfaces/ICreditEventOracle.sol";
import {ICDSPool} from "./interfaces/ICDSPool.sol";
import {CDSPoolFactory} from "./shield/CDSPoolFactory.sol";
import {CreditEventOracle} from "./shield/CreditEventOracle.sol";
import {NexusHub} from "./nexus/NexusHub.sol";

/// @title LiquidationBot
/// @notice Automated keeper that monitors and executes the protocol's liquidation waterfall.
/// @dev Provides public keeper functions that anyone can call. The protocol incentivizes
///      keepers by sending liquidation proceeds to msg.sender (in NexusHub).
///
///      Waterfall sequence:
///      1. Oracle detects threshold breach → reportCreditEvent or checkAndTrigger
///      2. CDS pools trigger → triggerCreditEvent on affected pools
///      3. CDS pools settle → distribute payouts to protection buyers
///      4. Unhealthy margin accounts liquidated → seize collateral
///
///      All functions are permissionless — anyone can be a keeper.
contract LiquidationBot is ReentrancyGuard {
    CreditEventOracle public immutable ORACLE;
    CDSPoolFactory public immutable POOL_FACTORY;
    NexusHub public immutable NEXUS_HUB;

    event OracleCheckExecuted(address indexed vault, bool eventTriggered);
    event PoolTriggered(address indexed pool);
    event PoolSettled(address indexed pool, uint256 recoveryRate);
    event PoolExpired(address indexed pool);
    event AccountLiquidated(address indexed user, address indexed liquidator);
    event WaterfallExecuted(address indexed vault, uint256 poolsTriggered, uint256 poolsSettled, uint256 accountsLiquidated);

    constructor(address oracle_, address poolFactory_, address nexusHub_) {
        require(oracle_ != address(0), "LiquidationBot: zero oracle");
        require(poolFactory_ != address(0), "LiquidationBot: zero factory");
        require(nexusHub_ != address(0), "LiquidationBot: zero hub");

        ORACLE = CreditEventOracle(oracle_);
        POOL_FACTORY = CDSPoolFactory(poolFactory_);
        NEXUS_HUB = NexusHub(nexusHub_);
    }

    // ========== Individual Keeper Functions ==========

    /// @notice Check oracle threshold for a vault and trigger if breached
    /// @param vault The ForgeVault to check
    /// @return triggered Whether a credit event was triggered
    function checkAndTriggerOracle(address vault) external returns (bool triggered) {
        try ORACLE.checkAndTrigger(vault) {
            triggered = ORACLE.hasActiveEvent(vault);
        } catch {
            triggered = false;
        }
        emit OracleCheckExecuted(vault, triggered);
    }

    /// @notice Trigger credit event on a specific CDS pool
    /// @param pool The CDSPool address
    function triggerPool(address pool) external {
        ICDSPool(pool).triggerCreditEvent();
        emit PoolTriggered(pool);
    }

    /// @notice Settle a triggered CDS pool with a recovery rate (via factory)
    /// @param poolId The pool ID in the factory
    /// @param recoveryRateWad Recovery rate in WAD (0 = total loss, 1e18 = full recovery)
    function settlePool(uint256 poolId, uint256 recoveryRateWad) external {
        address pool = POOL_FACTORY.getPool(poolId);
        POOL_FACTORY.settlePool(poolId, recoveryRateWad);
        emit PoolSettled(pool, recoveryRateWad);
    }

    /// @notice Expire a matured CDS pool
    /// @param pool The CDSPool address
    function expirePool(address pool) external {
        ICDSPool(pool).expire();
        emit PoolExpired(pool);
    }

    /// @notice Liquidate an unhealthy NexusHub margin account
    /// @param user The account to liquidate
    function liquidateAccount(address user) external {
        NEXUS_HUB.triggerLiquidation(user);
        emit AccountLiquidated(user, msg.sender);
    }

    // ========== Batch Keeper Functions ==========

    /// @notice Trigger credit events on all CDS pools for a vault
    /// @param vault The ForgeVault with a credit event
    /// @return triggeredCount Number of pools triggered
    function triggerAllPoolsForVault(address vault) external returns (uint256 triggeredCount) {
        require(ORACLE.hasActiveEvent(vault), "LiquidationBot: no credit event");

        uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
        for (uint256 i = 0; i < poolIds.length; i++) {
            address pool = POOL_FACTORY.getPool(poolIds[i]);
            try ICDSPool(pool).triggerCreditEvent() {
                triggeredCount++;
                emit PoolTriggered(pool);
            } catch {
                // Pool may already be triggered or not active
            }
        }
    }

    /// @notice Settle all triggered pools for a vault (via factory)
    /// @param vault The vault reference
    /// @param recoveryRateWad Recovery rate for settlement
    /// @return settledCount Number of pools settled
    function settleAllPoolsForVault(address vault, uint256 recoveryRateWad)
        external
        returns (uint256 settledCount)
    {
        uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
        for (uint256 i = 0; i < poolIds.length; i++) {
            address pool = POOL_FACTORY.getPool(poolIds[i]);
            try POOL_FACTORY.settlePool(poolIds[i], recoveryRateWad) {
                settledCount++;
                emit PoolSettled(pool, recoveryRateWad);
            } catch {
                // Pool may not be triggered or caller not factory owner
            }
        }
    }

    /// @notice Expire all matured pools for a vault
    /// @param vault The vault reference
    /// @return expiredCount Number of pools expired
    function expireAllPoolsForVault(address vault) external returns (uint256 expiredCount) {
        uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
        for (uint256 i = 0; i < poolIds.length; i++) {
            address pool = POOL_FACTORY.getPool(poolIds[i]);
            try ICDSPool(pool).expire() {
                expiredCount++;
                emit PoolExpired(pool);
            } catch {
                // Pool may not be matured yet
            }
        }
    }

    /// @notice Liquidate multiple unhealthy accounts
    /// @param users Array of accounts to attempt to liquidate
    /// @return liquidatedCount Number of accounts successfully liquidated
    function liquidateAccounts(address[] calldata users) external returns (uint256 liquidatedCount) {
        for (uint256 i = 0; i < users.length; i++) {
            try NEXUS_HUB.triggerLiquidation(users[i]) {
                liquidatedCount++;
                emit AccountLiquidated(users[i], msg.sender);
            } catch {
                // Account may be healthy or not exist
            }
        }
    }

    /// @notice Execute the full liquidation waterfall for a vault
    /// @dev Checks oracle → triggers pools → settles → liquidates accounts.
    ///      This is the "one button" nuclear option.
    /// @param vault The ForgeVault
    /// @param recoveryRateWad Recovery rate for settlement
    /// @param accounts Margin accounts to check for liquidation
    function executeWaterfall(
        address vault,
        uint256 recoveryRateWad,
        address[] calldata accounts
    ) external nonReentrant {
        // Step 1: Check oracle
        bool hasEvent = ORACLE.hasActiveEvent(vault);

        // Step 2: Trigger all pools
        uint256 poolsTriggered;
        uint256 poolsSettled;
        if (hasEvent) {
            uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
            for (uint256 i = 0; i < poolIds.length; i++) {
                address pool = POOL_FACTORY.getPool(poolIds[i]);

                // Try trigger
                try ICDSPool(pool).triggerCreditEvent() {
                    poolsTriggered++;
                    emit PoolTriggered(pool);
                } catch {}

                // Try settle via factory
                try POOL_FACTORY.settlePool(poolIds[i], recoveryRateWad) {
                    poolsSettled++;
                    emit PoolSettled(pool, recoveryRateWad);
                } catch {}
            }
        }

        // Step 3: Liquidate unhealthy accounts
        uint256 accountsLiquidated;
        for (uint256 i = 0; i < accounts.length; i++) {
            try NEXUS_HUB.triggerLiquidation(accounts[i]) {
                accountsLiquidated++;
                emit AccountLiquidated(accounts[i], msg.sender);
            } catch {}
        }

        emit WaterfallExecuted(vault, poolsTriggered, poolsSettled, accountsLiquidated);
    }

    // ========== View Functions ==========

    /// @notice Check if a vault has triggered pools that need settling
    /// @param vault The ForgeVault
    /// @return triggeredPools Array of triggered pool addresses
    function getTriggeredPools(address vault) external view returns (address[] memory triggeredPools) {
        uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
        address[] memory temp = new address[](poolIds.length);
        uint256 count;

        for (uint256 i = 0; i < poolIds.length; i++) {
            address pool = POOL_FACTORY.getPool(poolIds[i]);
            if (ICDSPool(pool).getPoolStatus() == ICDSPool.PoolStatus.Triggered) {
                temp[count++] = pool;
            }
        }

        triggeredPools = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            triggeredPools[i] = temp[i];
        }
    }

    /// @notice Check if a vault has matured pools that can be expired
    /// @param vault The ForgeVault
    /// @return expirablePools Array of expirable pool addresses
    function getExpirablePools(address vault) external view returns (address[] memory expirablePools) {
        uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
        address[] memory temp = new address[](poolIds.length);
        uint256 count;

        for (uint256 i = 0; i < poolIds.length; i++) {
            address pool = POOL_FACTORY.getPool(poolIds[i]);
            ICDSPool.PoolTerms memory terms = ICDSPool(pool).getPoolTerms();
            if (
                ICDSPool(pool).getPoolStatus() == ICDSPool.PoolStatus.Active &&
                block.timestamp >= terms.maturity
            ) {
                temp[count++] = pool;
            }
        }

        expirablePools = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            expirablePools[i] = temp[i];
        }
    }
}
