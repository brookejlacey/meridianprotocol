// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ICDSPool} from "./interfaces/ICDSPool.sol";
import {CDSPoolFactory} from "./shield/CDSPoolFactory.sol";
import {MeridianMath} from "./libraries/MeridianMath.sol";

/// @title PoolRouter
/// @notice Routes protection purchases across multiple CDS AMM pools for optimal pricing.
/// @dev Like 1inch but for credit protection. Splits large orders across pools
///      to get the best blended spread, minimizing slippage.
///
///      Algorithm (greedy fill):
///      1. Query all active pools for a reference asset
///      2. Quote each pool for the full remaining notional
///      3. Fill from cheapest to most expensive
///      4. Return aggregated positions across pools
contract PoolRouter is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    CDSPoolFactory public immutable FACTORY;
    address public pauseAdmin;

    struct FillResult {
        address pool;
        uint256 notional;
        uint256 premium;
        uint256 positionId;
    }

    struct RouteQuote {
        address[] pools;
        uint256[] notionals;
        uint256[] premiums;
        uint256 totalPremium;
        uint256 totalNotional;
    }

    event ProtectionRouted(
        address indexed buyer,
        address indexed referenceAsset,
        uint256 totalNotional,
        uint256 totalPremium,
        uint256 poolsUsed
    );

    constructor(address factory_, address pauseAdmin_) {
        require(factory_ != address(0), "PoolRouter: zero factory");
        require(pauseAdmin_ != address(0), "PoolRouter: zero pause admin");
        FACTORY = CDSPoolFactory(factory_);
        pauseAdmin = pauseAdmin_;
    }

    /// @notice Buy protection routed across multiple pools for best pricing
    /// @param referenceAsset The vault being insured
    /// @param totalNotional Total protection amount desired
    /// @param maxTotalPremium Maximum total premium willing to pay
    /// @return results Array of fill results from each pool
    function buyProtectionRouted(
        address referenceAsset,
        uint256 totalNotional,
        uint256 maxTotalPremium
    ) external nonReentrant whenNotPaused returns (FillResult[] memory results) {
        require(totalNotional > 0, "PoolRouter: zero notional");

        // Get all pool IDs for this reference asset
        uint256[] memory poolIds = FACTORY.getPoolsForVault(referenceAsset);
        require(poolIds.length > 0, "PoolRouter: no pools");

        // Build sorted pool list by current spread (cheapest first)
        address[] memory sortedPools = _sortPoolsBySpread(poolIds);

        // Greedy fill from cheapest to most expensive
        results = new FillResult[](sortedPools.length);
        uint256 remaining = totalNotional;
        uint256 totalPremium;
        uint256 fillCount;

        for (uint256 i = 0; i < sortedPools.length && remaining > 0; i++) {
            ICDSPool pool = ICDSPool(sortedPools[i]);

            // Skip non-active pools
            if (pool.getPoolStatus() != ICDSPool.PoolStatus.Active) continue;

            // Determine how much this pool can fill
            uint256 fillAmount = _maxFillable(pool, remaining);
            if (fillAmount == 0) continue;

            // Quote premium
            uint256 premium = pool.quoteProtection(fillAmount);
            if (premium == 0) continue;
            if (totalPremium + premium > maxTotalPremium) {
                // Try a smaller fill that fits within budget
                fillAmount = _binarySearchFill(pool, remaining, maxTotalPremium - totalPremium);
                if (fillAmount == 0) continue;
                premium = pool.quoteProtection(fillAmount);
            }

            // Pull premium from buyer and approve pool
            address collateral = pool.getPoolTerms().collateralToken;
            IERC20(collateral).safeTransferFrom(msg.sender, address(this), premium);
            IERC20(collateral).approve(sortedPools[i], premium);

            // Buy protection (beneficiary = original caller, not the router)
            uint256 posId = pool.buyProtectionFor(fillAmount, premium, msg.sender);

            // Reset approval to zero (safety: don't leave leftover approvals)
            IERC20(collateral).approve(sortedPools[i], 0);

            results[fillCount] = FillResult({
                pool: sortedPools[i],
                notional: fillAmount,
                premium: premium,
                positionId: posId
            });

            remaining -= fillAmount;
            totalPremium += premium;
            fillCount++;
        }

        require(remaining == 0, "PoolRouter: insufficient capacity");
        require(totalPremium <= maxTotalPremium, "PoolRouter: premium exceeded");

        // Trim results array
        assembly {
            mstore(results, fillCount)
        }

        emit ProtectionRouted(msg.sender, referenceAsset, totalNotional, totalPremium, fillCount);
    }

    /// @notice Quote the total premium for a routed protection purchase (view)
    /// @param referenceAsset The vault being insured
    /// @param totalNotional Total protection amount desired
    /// @return quote Detailed quote with per-pool breakdown
    function quoteRouted(
        address referenceAsset,
        uint256 totalNotional
    ) external view returns (RouteQuote memory quote) {
        uint256[] memory poolIds = FACTORY.getPoolsForVault(referenceAsset);
        if (poolIds.length == 0) return quote;

        address[] memory sortedPools = _sortPoolsBySpread(poolIds);

        quote.pools = new address[](sortedPools.length);
        quote.notionals = new uint256[](sortedPools.length);
        quote.premiums = new uint256[](sortedPools.length);

        uint256 remaining = totalNotional;
        uint256 fillCount;

        for (uint256 i = 0; i < sortedPools.length && remaining > 0; i++) {
            ICDSPool pool = ICDSPool(sortedPools[i]);
            if (pool.getPoolStatus() != ICDSPool.PoolStatus.Active) continue;

            uint256 fillAmount = _maxFillable(pool, remaining);
            if (fillAmount == 0) continue;

            uint256 premium = pool.quoteProtection(fillAmount);
            if (premium == 0) continue;

            quote.pools[fillCount] = sortedPools[i];
            quote.notionals[fillCount] = fillAmount;
            quote.premiums[fillCount] = premium;
            quote.totalPremium += premium;
            quote.totalNotional += fillAmount;

            remaining -= fillAmount;
            fillCount++;
        }

        // Trim arrays
        assembly {
            mstore(mload(quote), fillCount)
            mstore(mload(add(quote, 0x20)), fillCount)
            mstore(mload(add(quote, 0x40)), fillCount)
        }
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == pauseAdmin, "PoolRouter: not pause admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == pauseAdmin, "PoolRouter: not pause admin");
        _unpause();
    }

    // --- Pause Admin Transfer (Two-Step) ---

    address public pendingPauseAdmin;

    event PauseAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event PauseAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    function transferPauseAdmin(address newAdmin) external {
        require(msg.sender == pauseAdmin, "PoolRouter: not pause admin");
        require(newAdmin != address(0), "PoolRouter: zero address");
        pendingPauseAdmin = newAdmin;
        emit PauseAdminTransferStarted(pauseAdmin, newAdmin);
    }

    function acceptPauseAdmin() external {
        require(msg.sender == pendingPauseAdmin, "PoolRouter: not pending admin");
        emit PauseAdminTransferred(pauseAdmin, msg.sender);
        pauseAdmin = msg.sender;
        pendingPauseAdmin = address(0);
    }

    // --- Internal ---

    /// @dev Sort pools by current spread (ascending). Simple insertion sort (fine for small N).
    function _sortPoolsBySpread(uint256[] memory poolIds) internal view returns (address[] memory sorted) {
        uint256 len = poolIds.length;
        sorted = new address[](len);
        uint256[] memory spreads = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            sorted[i] = FACTORY.getPool(poolIds[i]);
            try ICDSPool(sorted[i]).currentSpread() returns (uint256 s) {
                spreads[i] = s;
            } catch {
                spreads[i] = type(uint256).max;
            }
        }

        // Insertion sort
        for (uint256 i = 1; i < len; i++) {
            uint256 keySpread = spreads[i];
            address keyAddr = sorted[i];
            int256 j = int256(i) - 1;
            while (j >= 0 && spreads[uint256(j)] > keySpread) {
                spreads[uint256(j) + 1] = spreads[uint256(j)];
                sorted[uint256(j) + 1] = sorted[uint256(j)];
                j--;
            }
            spreads[uint256(j + 1)] = keySpread;
            sorted[uint256(j + 1)] = keyAddr;
        }
    }

    /// @dev Calculate max notional a pool can fill (95% utilization cap)
    function _maxFillable(ICDSPool pool, uint256 desired) internal view returns (uint256) {
        uint256 totalAssets = pool.totalAssets();
        uint256 currentProtection = pool.totalProtectionSold();
        uint256 maxProtection = totalAssets * 95 / 100; // 95% cap

        if (currentProtection >= maxProtection) return 0;
        uint256 available = maxProtection - currentProtection;
        return available < desired ? available : desired;
    }

    /// @dev Binary search for the max fillable amount within a premium budget
    function _binarySearchFill(
        ICDSPool pool,
        uint256 maxNotional,
        uint256 budgetLeft
    ) internal view returns (uint256) {
        uint256 lo = 0;
        uint256 hi = _maxFillable(pool, maxNotional);
        if (hi == 0) return 0;

        // 8 iterations gives ~0.4% precision
        for (uint256 iter = 0; iter < 8; iter++) {
            uint256 mid = (lo + hi + 1) / 2;
            if (mid == 0) break;
            try pool.quoteProtection(mid) returns (uint256 premium) {
                if (premium <= budgetLeft) {
                    lo = mid;
                } else {
                    hi = mid - 1;
                }
            } catch {
                hi = mid - 1;
            }
        }
        return lo;
    }
}
