// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ICDSPool} from "../interfaces/ICDSPool.sol";
import {ICreditEventOracle} from "../interfaces/ICreditEventOracle.sol";
import {BondingCurve} from "../libraries/BondingCurve.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title CDSPool
/// @notice Automated Market Maker for Credit Default Swaps.
/// @dev LPs deposit collateral to sell protection. Buyers purchase protection
///      at a price determined by a utilization-based bonding curve. Premium
///      payments stream to LPs proportionally via share appreciation.
///
///      Pricing: spread = baseSpread + slope * u^2 / (1 - u)
///      Higher utilization → higher spreads → natural equilibrium.
///
///      LP shares work like ERC4626: totalAssets() increases as premiums
///      accrue, so each share is worth more over time.
///
///      Settlement: on credit event, the pool pays out protection claims.
///      LPs bear the loss. Recovery rate determines partial payouts.
contract CDSPool is ICDSPool, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    // --- Constants ---
    uint256 internal constant WAD = 1e18;
    uint256 internal constant YEAR = 365 days;
    uint256 public constant MAX_ACTIVE_POSITIONS = 200;

    // --- State ---
    PoolStatus public status;
    PoolTerms public terms;
    IERC20 public collateralToken;
    ICreditEventOracle public oracle;
    address public factory;

    // --- Protocol Fee ---
    address public treasury;
    address public protocolAdmin;
    uint256 public protocolFeeBps;
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 5000; // 50%
    uint256 public totalProtocolFeesCollected;

    // LP accounting (ERC4626-style)
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    // Pool liquidity tracking
    uint256 public totalDeposits;          // Raw LP deposits
    uint256 public totalPremiumsEarned;    // Cumulative premiums accrued to pool
    uint256 public totalProtectionSold;    // Outstanding notional protection

    // Protection positions
    uint256 public nextPositionId;
    mapping(uint256 => ProtectionPosition) public positions;
    uint256[] public activePositionIds;

    // Premium tracking
    uint256 public lastAccrualTime;
    mapping(uint256 posId => uint256 accrued) public positionPremiumAccrued;

    // Settlement claims (pull-based pattern to prevent griefing)
    mapping(address => uint256) public settlementClaims;

    // LP deposit cooldown to prevent flash-deposit spread manipulation (M-18)
    uint256 public constant LP_COOLDOWN = 1 hours;
    mapping(address => uint256) public lastDepositTime;

    // --- Modifiers ---
    modifier onlyActive() {
        require(status == PoolStatus.Active, "CDSPool: not active");
        _;
    }

    constructor(
        PoolTerms memory terms_,
        address factory_,
        address treasury_,
        address protocolAdmin_,
        uint256 protocolFeeBps_
    ) {
        require(terms_.referenceAsset != address(0), "CDSPool: zero ref asset");
        require(terms_.collateralToken != address(0), "CDSPool: zero collateral");
        require(terms_.oracle != address(0), "CDSPool: zero oracle");
        require(terms_.maturity > block.timestamp, "CDSPool: maturity passed");
        require(terms_.baseSpreadWad > 0, "CDSPool: zero base spread");
        require(terms_.slopeWad > 0, "CDSPool: zero slope");
        require(treasury_ != address(0), "CDSPool: zero treasury");
        require(protocolAdmin_ != address(0), "CDSPool: zero protocol admin");
        require(protocolFeeBps_ <= MAX_PROTOCOL_FEE_BPS, "CDSPool: fee exceeds max");

        terms = terms_;
        collateralToken = IERC20(terms_.collateralToken);
        oracle = ICreditEventOracle(terms_.oracle);
        factory = factory_;
        treasury = treasury_;
        protocolAdmin = protocolAdmin_;
        protocolFeeBps = protocolFeeBps_;
        status = PoolStatus.Active;
        lastAccrualTime = block.timestamp;
    }

    // ========== LP Functions ==========

    /// @notice Deposit collateral to provide protection liquidity
    /// @param amount Amount of collateral to deposit
    /// @return sharesOut LP shares minted
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        onlyActive
        returns (uint256 sharesOut)
    {
        require(amount > 0, "CDSPool: zero deposit");

        // Accrue premiums before changing pool state
        _accruePremiums();

        // Calculate shares: first depositor gets 1:1 (min 1e6 to prevent inflation attack)
        uint256 assets = totalAssets();
        if (totalShares == 0 || assets == 0) {
            require(amount >= 1e6, "CDSPool: min initial deposit 1e6");
            sharesOut = amount;
        } else {
            sharesOut = MeridianMath.wadDiv(amount, MeridianMath.wadDiv(assets, totalShares));
        }

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposits += amount;
        totalShares += sharesOut;
        shares[msg.sender] += sharesOut;
        lastDepositTime[msg.sender] = block.timestamp;

        emit LiquidityDeposited(msg.sender, amount, sharesOut);
    }

    /// @notice Withdraw collateral by burning LP shares
    /// @param sharesToBurn Number of LP shares to redeem
    /// @return amountOut Collateral returned
    function withdraw(uint256 sharesToBurn)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        require(sharesToBurn > 0, "CDSPool: zero shares");
        require(shares[msg.sender] >= sharesToBurn, "CDSPool: insufficient shares");
        require(
            status == PoolStatus.Active || status == PoolStatus.Expired || status == PoolStatus.Settled,
            "CDSPool: cannot withdraw"
        );
        require(
            block.timestamp >= lastDepositTime[msg.sender] + LP_COOLDOWN,
            "CDSPool: deposit cooldown"
        );

        // Accrue premiums before changing pool state
        if (status == PoolStatus.Active) _accruePremiums();

        // Calculate proportional share of total assets
        amountOut = MeridianMath.wadMul(
            MeridianMath.wadDiv(sharesToBurn, totalShares),
            totalAssets()
        );

        // Check that withdrawal doesn't make pool undercollateralized
        if (status == PoolStatus.Active) {
            uint256 assetsAfter = totalAssets() - amountOut;
            require(
                assetsAfter >= totalProtectionSold,
                "CDSPool: withdrawal would undercollateralize"
            );
        }

        shares[msg.sender] -= sharesToBurn;
        totalShares -= sharesToBurn;

        // Proportionally reduce deposits and premiums based on pool composition
        uint256 assets = totalAssets();
        if (assets > 0) {
            uint256 depositPortion = (amountOut * totalDeposits) / assets;
            uint256 premiumPortion = amountOut > depositPortion ? amountOut - depositPortion : 0;
            totalDeposits = totalDeposits > depositPortion ? totalDeposits - depositPortion : 0;
            totalPremiumsEarned = totalPremiumsEarned > premiumPortion
                ? totalPremiumsEarned - premiumPortion : 0;
        }

        collateralToken.safeTransfer(msg.sender, amountOut);
        emit LiquidityWithdrawn(msg.sender, sharesToBurn, amountOut);
    }

    // ========== Protection Buyer Functions ==========

    /// @notice Buy protection from the pool at the bonding curve price
    /// @param notional Protection amount
    /// @param maxPremium Maximum premium willing to pay (slippage protection)
    /// @return positionId ID of the new protection position
    function buyProtection(uint256 notional, uint256 maxPremium)
        external
        override
        nonReentrant
        whenNotPaused
        onlyActive
        returns (uint256 positionId)
    {
        require(notional > 0, "CDSPool: zero notional");
        require(block.timestamp < terms.maturity, "CDSPool: matured");

        // Accrue premiums first
        _accruePremiums();

        uint256 tenorSeconds = terms.maturity - block.timestamp;

        // Quote premium via bonding curve integration
        uint256 premium = BondingCurve.quotePremium(
            notional,
            totalAssets(),
            totalProtectionSold,
            terms.baseSpreadWad,
            terms.slopeWad,
            tenorSeconds
        );
        require(premium <= maxPremium, "CDSPool: premium exceeds max");
        require(premium > 0, "CDSPool: zero premium");

        // Calculate effective average spread for this purchase
        // spread = (premium / notional) * (YEAR / tenor)
        // Split into two operations to avoid overflow on premium * YEAR
        uint256 avgSpread = MeridianMath.wadDiv(premium, notional) * YEAR / tenorSeconds;

        // Pull premium from buyer
        collateralToken.safeTransferFrom(msg.sender, address(this), premium);

        // Create position (bounded to prevent gas DoS in loops)
        require(activePositionIds.length < MAX_ACTIVE_POSITIONS, "CDSPool: max positions reached");
        positionId = nextPositionId++;
        positions[positionId] = ProtectionPosition({
            buyer: msg.sender,
            notional: notional,
            premiumPaid: premium,
            spreadWad: avgSpread,
            startTime: block.timestamp,
            active: true
        });
        activePositionIds.push(positionId);
        totalProtectionSold += notional;

        emit ProtectionBought(msg.sender, positionId, notional, premium, avgSpread);
    }

    /// @notice Close an active protection position early (forfeit remaining premium)
    /// @param positionId Position to close
    /// @return refund Unearned premium returned to buyer
    function closeProtection(uint256 positionId)
        external
        override
        nonReentrant
        onlyActive
        returns (uint256 refund)
    {
        ProtectionPosition storage pos = positions[positionId];
        require(pos.buyer == msg.sender, "CDSPool: not position owner");
        require(pos.active, "CDSPool: position not active");

        // Accrue premiums first
        _accruePremiums();

        // Calculate unearned premium (time remaining / total time * premium)
        uint256 elapsed = block.timestamp - pos.startTime;
        uint256 totalTenor = terms.maturity - pos.startTime;
        uint256 earnedPremium = totalTenor > 0
            ? pos.premiumPaid * elapsed / totalTenor
            : pos.premiumPaid;
        refund = pos.premiumPaid > earnedPremium ? pos.premiumPaid - earnedPremium : 0;

        // Close position
        pos.active = false;
        totalProtectionSold -= pos.notional;

        // The earned premium stays in the pool (already counted via accrual)
        // Return unearned premium to buyer
        if (refund > 0) {
            collateralToken.safeTransfer(msg.sender, refund);
        }

        // Remove from active list
        _removeActivePosition(positionId);

        emit ProtectionClosed(msg.sender, positionId, refund);
    }

    // ========== Lifecycle Functions ==========

    /// @notice Accrue outstanding premiums from all active positions into pool assets
    /// @dev Called automatically before state-changing operations. Anyone can call manually.
    function accrueAllPremiums() external override whenNotPaused {
        _accruePremiums();
    }

    /// @notice Trigger a credit event via oracle
    function triggerCreditEvent()
        external
        override
        nonReentrant
        onlyActive
    {
        require(
            oracle.hasActiveEvent(terms.referenceAsset),
            "CDSPool: no credit event"
        );
        status = PoolStatus.Triggered;
        _accruePremiums();
        emit CreditEventTriggered(block.timestamp);
    }

    /// @notice Settle the pool after credit event — pay out protection buyers
    /// @param recoveryRateWad Recovery rate in WAD (1e18 = 100% recovery = no loss,
    ///        0 = total loss, 0.4e18 = 60% loss)
    function settle(uint256 recoveryRateWad)
        external
        override
        nonReentrant
    {
        require(status == PoolStatus.Triggered, "CDSPool: not triggered");
        require(recoveryRateWad <= WAD, "CDSPool: invalid recovery");
        require(msg.sender == factory, "CDSPool: only factory can settle");

        status = PoolStatus.Settled;

        // Loss rate = 1 - recovery rate
        uint256 lossRateWad = WAD - recoveryRateWad;
        uint256 totalPayout;

        // Record settlement claims (pull-based to prevent griefing by malicious buyers)
        for (uint256 i = 0; i < activePositionIds.length;) {
            uint256 posId = activePositionIds[i];
            ProtectionPosition storage pos = positions[posId];
            if (!pos.active) { unchecked { ++i; } continue; }

            // Payout = notional * lossRate, capped at LP deposits (not earned premiums)
            uint256 payout = MeridianMath.wadMul(pos.notional, lossRateWad);
            uint256 available = totalDeposits > totalPayout ? totalDeposits - totalPayout : 0;
            payout = payout.min(available);

            if (payout > 0) {
                settlementClaims[pos.buyer] += payout;
                totalPayout += payout;
            }
            pos.active = false;
            unchecked { ++i; }
        }

        delete activePositionIds;
        totalProtectionSold = 0;

        // Reduce deposits by the total payout (LPs bear the loss)
        totalDeposits = totalDeposits > totalPayout
            ? totalDeposits - totalPayout : 0;

        emit PoolSettled(totalPayout, recoveryRateWad);
    }

    /// @notice Expire the pool at maturity — all protection lapses
    function expire() external override nonReentrant {
        require(status == PoolStatus.Active, "CDSPool: not active");
        require(block.timestamp >= terms.maturity, "CDSPool: not matured");

        // Final premium accrual
        _accruePremiums();

        status = PoolStatus.Expired;

        // Close all positions (protection has lapsed) and clear the array
        for (uint256 i = 0; i < activePositionIds.length;) {
            uint256 posId = activePositionIds[i];
            positions[posId].active = false;
            unchecked { ++i; }
        }
        delete activePositionIds;
        totalProtectionSold = 0;

        emit PoolExpired(block.timestamp);
    }

    /// @notice Claim settlement payout after a credit event (pull-based)
    /// @return amount Amount claimed
    function claimSettlement() external nonReentrant returns (uint256 amount) {
        amount = settlementClaims[msg.sender];
        require(amount > 0, "CDSPool: nothing to claim");
        settlementClaims[msg.sender] = 0;
        collateralToken.safeTransfer(msg.sender, amount);
        emit SettlementClaimed(msg.sender, amount);
    }

    /// @notice Buy protection on behalf of a beneficiary (for router/composability)
    /// @param notional Protection amount
    /// @param maxPremium Maximum premium willing to pay
    /// @param beneficiary Address that owns the position and receives settlement payouts
    /// @return positionId ID of the new protection position
    function buyProtectionFor(uint256 notional, uint256 maxPremium, address beneficiary)
        external
        nonReentrant
        whenNotPaused
        onlyActive
        returns (uint256 positionId)
    {
        require(notional > 0, "CDSPool: zero notional");
        require(beneficiary != address(0), "CDSPool: zero beneficiary");
        require(block.timestamp < terms.maturity, "CDSPool: matured");

        _accruePremiums();

        uint256 tenorSeconds = terms.maturity - block.timestamp;

        uint256 premium = BondingCurve.quotePremium(
            notional, totalAssets(), totalProtectionSold,
            terms.baseSpreadWad, terms.slopeWad, tenorSeconds
        );
        require(premium <= maxPremium, "CDSPool: premium exceeds max");
        require(premium > 0, "CDSPool: zero premium");

        uint256 avgSpread = MeridianMath.wadDiv(premium, notional) * YEAR / tenorSeconds;

        collateralToken.safeTransferFrom(msg.sender, address(this), premium);

        require(activePositionIds.length < MAX_ACTIVE_POSITIONS, "CDSPool: max positions reached");
        positionId = nextPositionId++;
        positions[positionId] = ProtectionPosition({
            buyer: beneficiary,
            notional: notional,
            premiumPaid: premium,
            spreadWad: avgSpread,
            startTime: block.timestamp,
            active: true
        });
        activePositionIds.push(positionId);
        totalProtectionSold += notional;

        emit ProtectionBought(beneficiary, positionId, notional, premium, avgSpread);
    }

    // ========== View Functions ==========

    /// @notice Current instantaneous annual spread
    function currentSpread() external view override returns (uint256) {
        uint256 util = utilizationRate();
        return BondingCurve.getSpread(terms.baseSpreadWad, terms.slopeWad, util);
    }

    /// @notice Quote premium for buying protection
    /// @param notional Protection amount
    /// @return premium Cost of protection
    function quoteProtection(uint256 notional)
        external
        view
        override
        returns (uint256 premium)
    {
        if (block.timestamp >= terms.maturity) return 0;
        uint256 tenorSeconds = terms.maturity - block.timestamp;
        premium = BondingCurve.quotePremium(
            notional,
            totalAssets(),
            totalProtectionSold,
            terms.baseSpreadWad,
            terms.slopeWad,
            tenorSeconds
        );
    }

    /// @notice Total pool assets (deposits + earned premiums)
    function totalAssets() public view override returns (uint256) {
        return totalDeposits + totalPremiumsEarned;
    }

    /// @notice Current utilization ratio
    function utilizationRate() public view override returns (uint256) {
        return BondingCurve.utilization(totalProtectionSold, totalAssets());
    }

    /// @notice Get protection position details
    function getPosition(uint256 positionId)
        external
        view
        override
        returns (ProtectionPosition memory)
    {
        return positions[positionId];
    }

    /// @notice Get pool terms
    function getPoolTerms() external view override returns (PoolTerms memory) {
        return terms;
    }

    /// @notice Get pool status
    function getPoolStatus() external view override returns (PoolStatus) {
        return status;
    }

    /// @notice Get number of active positions
    function activePositionCount() external view returns (uint256) {
        return activePositionIds.length;
    }

    /// @notice Get share balance for an LP
    function sharesOf(address lp) external view returns (uint256) {
        return shares[lp];
    }

    /// @notice Convert shares to underlying assets
    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        if (totalShares == 0) return shareAmount;
        return MeridianMath.wadMul(
            MeridianMath.wadDiv(shareAmount, totalShares),
            totalAssets()
        );
    }

    /// @notice Convert underlying amount to shares
    function convertToShares(uint256 amount) external view returns (uint256) {
        if (totalShares == 0 || totalAssets() == 0) return amount;
        return MeridianMath.wadDiv(amount, MeridianMath.wadDiv(totalAssets(), totalShares));
    }

    // ========== Protocol Fee Admin ==========

    /// @notice Set protocol fee (only protocol admin)
    /// @param newFeeBps New fee in basis points (max 5000 = 50%)
    function setProtocolFee(uint256 newFeeBps) external {
        require(msg.sender == protocolAdmin, "CDSPool: not protocol admin");
        require(newFeeBps <= MAX_PROTOCOL_FEE_BPS, "CDSPool: fee exceeds max");

        uint256 oldFeeBps = protocolFeeBps;
        protocolFeeBps = newFeeBps;
        emit ProtocolFeeUpdated(oldFeeBps, newFeeBps);
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == protocolAdmin, "CDSPool: not protocol admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == protocolAdmin, "CDSPool: not protocol admin");
        _unpause();
    }

    // --- Access Control Transfers (Two-Step) ---

    address public pendingProtocolAdmin;

    event ProtocolAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event ProtocolAdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    function transferProtocolAdmin(address newAdmin) external {
        require(msg.sender == protocolAdmin, "CDSPool: not protocol admin");
        require(newAdmin != address(0), "CDSPool: zero address");
        pendingProtocolAdmin = newAdmin;
        emit ProtocolAdminTransferStarted(protocolAdmin, newAdmin);
    }

    function acceptProtocolAdmin() external {
        require(msg.sender == pendingProtocolAdmin, "CDSPool: not pending admin");
        emit ProtocolAdminTransferred(protocolAdmin, msg.sender);
        protocolAdmin = msg.sender;
        pendingProtocolAdmin = address(0);
    }

    function setTreasury(address newTreasury) external {
        require(msg.sender == protocolAdmin, "CDSPool: not protocol admin");
        require(newTreasury != address(0), "CDSPool: zero address");
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    // ========== Internal ==========

    /// @dev Accrue premiums from all active positions based on elapsed time
    function _accruePremiums() internal {
        uint256 currentTime = block.timestamp < terms.maturity ? block.timestamp : terms.maturity;
        if (currentTime <= lastAccrualTime) return;

        uint256 elapsed = currentTime - lastAccrualTime;
        uint256 totalAccrued;

        for (uint256 i = 0; i < activePositionIds.length;) {
            uint256 posId = activePositionIds[i];
            ProtectionPosition storage pos = positions[posId];
            if (!pos.active) { unchecked { ++i; } continue; }

            // Premium accrual = notional * spread * elapsed / YEAR
            uint256 accrued = MeridianMath.wadMul(pos.notional, pos.spreadWad);
            unchecked { accrued = accrued * elapsed / YEAR; }

            // Hard cap: total accrued for this position can never exceed premiumPaid
            uint256 alreadyAccrued = positionPremiumAccrued[posId];
            uint256 remaining = pos.premiumPaid > alreadyAccrued
                ? pos.premiumPaid - alreadyAccrued : 0;
            accrued = accrued.min(remaining);

            positionPremiumAccrued[posId] += accrued;
            totalAccrued += accrued;
            unchecked { ++i; }
        }

        if (totalAccrued > 0) {
            // Extract protocol fee BEFORE adding to LP earnings
            uint256 protocolFee = 0;
            if (protocolFeeBps > 0) {
                protocolFee = totalAccrued.bpsMul(protocolFeeBps);
                if (protocolFee > 0) {
                    collateralToken.safeTransfer(treasury, protocolFee);
                    totalProtocolFeesCollected += protocolFee;
                    emit ProtocolFeeCollected(protocolFee);
                }
            }
            totalPremiumsEarned += (totalAccrued - protocolFee);
            emit PremiumsAccrued(totalAccrued - protocolFee, currentTime);
        }
        lastAccrualTime = currentTime;
    }

    /// @dev Remove a position ID from the active list
    function _removeActivePosition(uint256 positionId) internal {
        uint256 len = activePositionIds.length;
        for (uint256 i = 0; i < len;) {
            if (activePositionIds[i] == positionId) {
                activePositionIds[i] = activePositionIds[len - 1];
                activePositionIds.pop();
                return;
            }
            unchecked { ++i; }
        }
    }
}
