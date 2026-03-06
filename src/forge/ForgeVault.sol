// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";
import {ITrancheToken} from "../interfaces/ITrancheToken.sol";
import {WaterfallDistributor} from "../libraries/WaterfallDistributor.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title ForgeVault
/// @notice Holds underlying yield-bearing assets and manages structured credit waterfall.
/// @dev Implements the "Minter-Knows" pattern:
///      - Maintains plaintext mirrors of share counts (Zone 2)
///      - TrancheTokens (eERC in production) hold encrypted balances (Zone 3)
///      - Waterfall math uses plaintext mirrors exclusively
///
///      Yield distribution is pull-based (MasterChef pattern):
///      - yieldPerShare accumulator updated on each waterfall
///      - Users call claimYield() to pull their share
///
///      Convention: tranche indices are 0=Senior, 1=Mezzanine, 2=Equity
contract ForgeVault is IForgeVault, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    // --- Constants ---
    uint8 public constant NUM_TRANCHES = 3;
    uint8 public constant SENIOR = 0;
    uint8 public constant MEZZANINE = 1;
    uint8 public constant EQUITY = 2;

    // --- Dynamic Tranche Ratio Bounds ---
    uint256 public constant MIN_SENIOR_PCT = 50;
    uint256 public constant MAX_SENIOR_PCT = 85;
    uint256 public constant MIN_MEZZ_PCT = 10;
    uint256 public constant MAX_MEZZ_PCT = 35;
    uint256 public constant MIN_EQUITY_PCT = 5;
    uint256 public constant MAX_EQUITY_PCT = 20;

    // --- Immutables ---
    address public override originator;
    IERC20 public underlyingAsset;

    // --- Tranche State ---
    ITrancheToken[3] public trancheTokens;
    TrancheParams[3] public trancheParamsArray;

    /// @notice Zone 2: Plaintext mirror of per-user shares (synced via transfer hook)
    mapping(uint8 trancheId => mapping(address user => uint256 shares)) private _shares;

    /// @notice Zone 2: Total shares per tranche
    uint256[3] public totalShares;

    /// @notice Zone 2: Total value deposited per tranche
    uint256[3] public totalDeposited;

    // --- Yield Accumulator (MasterChef Pattern) ---

    /// @notice Cumulative yield per share for each tranche (WAD-scaled)
    uint256[3] public yieldPerShare;

    /// @notice Per-user checkpoint of yieldPerShare at last claim/invest/withdraw
    mapping(uint8 trancheId => mapping(address user => uint256 checkpoint)) private _yieldCheckpoint;

    /// @notice Per-user unclaimed yield that was snapshotted before a shares change
    mapping(uint8 trancheId => mapping(address user => uint256 pending)) private _pendingYield;

    // --- Pool Aggregate State (Zone 1: Public) ---
    uint256 public totalPoolDeposited;
    uint256 public totalYieldReceived;
    uint256 public totalYieldDistributed;
    uint256 public totalYieldClaimed;
    uint256 public lastDistribution;
    PoolStatus public override poolStatus;

    /// @notice Minimum time between waterfall triggers (prevents MEV spam)
    uint256 public distributionInterval;

    // --- Protocol Fee ---
    address public treasury;
    address public protocolAdmin;
    uint256 public protocolFeeBps;
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1000; // 10%
    uint256 public totalProtocolFeesCollected;

    // --- Modifiers ---
    modifier onlyOriginator() {
        require(msg.sender == originator, "ForgeVault: not originator");
        _;
    }

    modifier onlyActive() {
        require(poolStatus == PoolStatus.Active, "ForgeVault: pool not active");
        _;
    }

    modifier validTranche(uint8 trancheId) {
        require(trancheId < NUM_TRANCHES, "ForgeVault: invalid tranche");
        _;
    }

    // --- Constructor ---
    constructor(
        address originator_,
        address underlyingAsset_,
        address[3] memory trancheTokenAddresses,
        TrancheParams[3] memory params,
        uint256 distributionInterval_,
        address treasury_,
        address protocolAdmin_,
        uint256 protocolFeeBps_
    ) {
        require(originator_ != address(0), "ForgeVault: zero originator");
        require(underlyingAsset_ != address(0), "ForgeVault: zero asset");
        require(treasury_ != address(0), "ForgeVault: zero treasury");
        require(protocolAdmin_ != address(0), "ForgeVault: zero protocol admin");
        require(protocolFeeBps_ <= MAX_PROTOCOL_FEE_BPS, "ForgeVault: fee exceeds max");

        originator = originator_;
        underlyingAsset = IERC20(underlyingAsset_);
        distributionInterval = distributionInterval_;
        treasury = treasury_;
        protocolAdmin = protocolAdmin_;
        protocolFeeBps = protocolFeeBps_;

        uint256 totalAllocation;
        for (uint8 i = 0; i < NUM_TRANCHES;) {
            require(trancheTokenAddresses[i] != address(0), "ForgeVault: zero tranche token");
            trancheTokens[i] = ITrancheToken(trancheTokenAddresses[i]);
            trancheParamsArray[i] = params[i];
            trancheParamsArray[i].token = trancheTokenAddresses[i];
            totalAllocation += params[i].allocationPct;
            unchecked { ++i; }
        }
        require(totalAllocation == 100, "ForgeVault: allocation must sum to 100");

        poolStatus = PoolStatus.Active;
        lastDistribution = block.timestamp;
    }

    // --- Investor Functions ---

    /// @notice Invest in a tranche by depositing underlying asset
    /// @param trancheId 0=Senior, 1=Mezzanine, 2=Equity
    /// @param amount Amount of underlying asset to invest
    function invest(uint8 trancheId, uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        onlyActive
        validTranche(trancheId)
    {
        require(amount > 0, "ForgeVault: zero amount");

        // Settle any pending yield before changing shares
        _settleYield(trancheId, msg.sender);

        // Transfer underlying asset from investor
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Update plaintext mirrors (Zone 2)
        _shares[trancheId][msg.sender] += amount;
        totalShares[trancheId] += amount;
        totalDeposited[trancheId] += amount;
        totalPoolDeposited += amount;

        // Mint tranche tokens (1:1 with investment amount)
        trancheTokens[trancheId].mint(msg.sender, amount);

        emit Invested(msg.sender, trancheId, amount);
    }

    /// @notice Invest on behalf of a beneficiary (for router/composability)
    /// @param trancheId 0=Senior, 1=Mezzanine, 2=Equity
    /// @param amount Amount of underlying asset to invest
    /// @param beneficiary Address that receives shares and tranche tokens
    function investFor(uint8 trancheId, uint256 amount, address beneficiary)
        external
        override
        nonReentrant
        whenNotPaused
        onlyActive
        validTranche(trancheId)
    {
        require(amount > 0, "ForgeVault: zero amount");
        require(beneficiary != address(0), "ForgeVault: zero beneficiary");

        _settleYield(trancheId, beneficiary);

        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        _shares[trancheId][beneficiary] += amount;
        totalShares[trancheId] += amount;
        totalDeposited[trancheId] += amount;
        totalPoolDeposited += amount;

        trancheTokens[trancheId].mint(beneficiary, amount);

        emit Invested(beneficiary, trancheId, amount);
    }

    /// @notice Claim accrued yield for a tranche
    /// @param trancheId 0=Senior, 1=Mezzanine, 2=Equity
    /// @return claimed Amount of yield claimed
    function claimYield(uint8 trancheId)
        external
        override
        nonReentrant
        validTranche(trancheId)
        returns (uint256 claimed)
    {
        _settleYield(trancheId, msg.sender);

        claimed = _pendingYield[trancheId][msg.sender];
        if (claimed == 0) return 0;

        _pendingYield[trancheId][msg.sender] = 0;
        totalYieldClaimed += claimed;

        // Transfer yield in underlying asset
        underlyingAsset.safeTransfer(msg.sender, claimed);

        emit YieldClaimed(msg.sender, trancheId, claimed);
    }

    /// @notice Withdraw from a tranche, burning tranche tokens
    /// @param trancheId 0=Senior, 1=Mezzanine, 2=Equity
    /// @param amount Amount to withdraw
    /// @dev Withdrawals blocked during Impaired/Defaulted to prevent race conditions
    ///      where sophisticated investors drain assets before loss allocation.
    function withdraw(uint8 trancheId, uint256 amount)
        external
        override
        nonReentrant
        validTranche(trancheId)
    {
        require(amount > 0, "ForgeVault: zero amount");
        require(
            poolStatus == PoolStatus.Active || poolStatus == PoolStatus.Matured,
            "ForgeVault: withdrawals disabled"
        );
        require(_shares[trancheId][msg.sender] >= amount, "ForgeVault: insufficient shares");

        // Settle any pending yield before changing shares
        _settleYield(trancheId, msg.sender);

        // Update plaintext mirrors
        _shares[trancheId][msg.sender] -= amount;
        totalShares[trancheId] -= amount;
        totalDeposited[trancheId] -= amount;
        totalPoolDeposited -= amount;

        // Burn tranche tokens
        trancheTokens[trancheId].burn(msg.sender, amount);

        // Transfer underlying back to investor
        underlyingAsset.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, trancheId, amount);
    }

    // --- Waterfall Distribution ---

    /// @notice Trigger waterfall distribution of available yield
    /// @dev Anyone can call this (public crank). Respects distributionInterval.
    function triggerWaterfall() external override nonReentrant whenNotPaused onlyActive {
        require(
            block.timestamp >= lastDistribution + distributionInterval,
            "ForgeVault: too soon"
        );

        // Calculate available yield (balance beyond what's been deposited and not yet distributed)
        uint256 currentBalance = underlyingAsset.balanceOf(address(this));
        uint256 obligated = totalPoolDeposited + _totalPendingYield();
        if (currentBalance <= obligated) return;

        uint256 availableYield = currentBalance - obligated;
        if (availableYield == 0) return;

        // Extract protocol fee BEFORE waterfall distribution
        if (protocolFeeBps > 0) {
            uint256 protocolFee = availableYield.bpsMul(protocolFeeBps);
            if (protocolFee > 0) {
                underlyingAsset.safeTransfer(treasury, protocolFee);
                totalProtocolFeesCollected += protocolFee;
                availableYield -= protocolFee;
                emit ProtocolFeeCollected(protocolFee);
            }
        }

        // Build tranche states for waterfall calculation
        WaterfallDistributor.TrancheState[3] memory states;
        for (uint8 i = 0; i < NUM_TRANCHES;) {
            states[i] = WaterfallDistributor.TrancheState({
                targetApr: trancheParamsArray[i].targetApr,
                totalShares: totalShares[i],
                depositValue: totalDeposited[i]
            });
            unchecked { ++i; }
        }

        // Calculate period in bps (time since last distribution / 1 year)
        uint256 timeDelta = block.timestamp - lastDistribution;
        uint256 periodBps = (timeDelta * MeridianMath.BPS) / 365 days;
        if (periodBps == 0) periodBps = 1; // minimum 1 bps

        // Execute waterfall
        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(availableYield, states, periodBps);

        // Update yieldPerShare accumulators
        for (uint8 i = 0; i < NUM_TRANCHES;) {
            if (result.amounts[i] > 0 && totalShares[i] > 0) {
                yieldPerShare[i] += WaterfallDistributor.calculateYieldPerShareDelta(
                    result.amounts[i], totalShares[i]
                );
            }
            unchecked { ++i; }
        }

        totalYieldReceived += availableYield;
        totalYieldDistributed += result.totalDistributed;
        lastDistribution = block.timestamp;

        emit YieldReceived(availableYield, block.timestamp);
        emit WaterfallDistributed(availableYield, result.amounts);
    }

    // --- Originator Functions ---

    /// @notice Set pool status (for credit events)
    /// @dev Enforces valid transitions:
    ///      Active -> Impaired, Active -> Matured, Active -> Defaulted
    ///      Impaired -> Defaulted, Matured -> Defaulted
    ///      No backwards transitions allowed.
    function setPoolStatus(PoolStatus newStatus) external onlyOriginator {
        PoolStatus oldStatus = poolStatus;
        require(newStatus != oldStatus, "ForgeVault: same status");
        require(
            (oldStatus == PoolStatus.Active && (newStatus == PoolStatus.Impaired || newStatus == PoolStatus.Matured || newStatus == PoolStatus.Defaulted)) ||
            (oldStatus == PoolStatus.Impaired && newStatus == PoolStatus.Defaulted) ||
            (oldStatus == PoolStatus.Matured && newStatus == PoolStatus.Defaulted),
            "ForgeVault: invalid status transition"
        );
        poolStatus = newStatus;
        emit PoolStatusChanged(oldStatus, newStatus);
    }

    /// @notice Adjust tranche allocation percentages for future investments
    /// @dev Only originator can call. Only affects guidance for NEW investments, not existing positions.
    ///      Bounds: Senior 50-85%, Mezzanine 10-35%, Equity 5-20%. Must sum to 100.
    /// @param newPcts Array of 3 percentages [senior, mezz, equity]
    function adjustTrancheRatios(uint256[3] calldata newPcts) external onlyOriginator onlyActive {
        require(newPcts[0] + newPcts[1] + newPcts[2] == 100, "ForgeVault: must sum to 100");
        require(
            newPcts[0] >= MIN_SENIOR_PCT && newPcts[0] <= MAX_SENIOR_PCT,
            "ForgeVault: senior out of bounds"
        );
        require(
            newPcts[1] >= MIN_MEZZ_PCT && newPcts[1] <= MAX_MEZZ_PCT,
            "ForgeVault: mezz out of bounds"
        );
        require(
            newPcts[2] >= MIN_EQUITY_PCT && newPcts[2] <= MAX_EQUITY_PCT,
            "ForgeVault: equity out of bounds"
        );

        uint256[3] memory oldPcts;
        for (uint8 i = 0; i < NUM_TRANCHES;) {
            oldPcts[i] = trancheParamsArray[i].allocationPct;
            trancheParamsArray[i].allocationPct = newPcts[i];
            unchecked { ++i; }
        }

        emit TrancheRatiosAdjusted(oldPcts, newPcts);
    }

    // --- Protocol Fee Admin ---

    /// @notice Set protocol fee (only protocol admin)
    /// @param newFeeBps New fee in basis points (max 1000 = 10%)
    function setProtocolFee(uint256 newFeeBps) external {
        require(msg.sender == protocolAdmin, "ForgeVault: not protocol admin");
        require(newFeeBps <= MAX_PROTOCOL_FEE_BPS, "ForgeVault: fee exceeds max");

        uint256 oldFeeBps = protocolFeeBps;
        protocolFeeBps = newFeeBps;
        emit ProtocolFeeUpdated(oldFeeBps, newFeeBps);
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == protocolAdmin, "ForgeVault: not protocol admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == protocolAdmin, "ForgeVault: not protocol admin");
        _unpause();
    }

    // --- Transfer Hook (called by TrancheToken) ---

    /// @notice Called by TrancheToken when shares are transferred on secondary market.
    /// @dev Keeps plaintext mirrors in sync. Must settle yield for BOTH parties.
    function onShareTransfer(address from, address to, uint256 amount) external nonReentrant {
        // Find which tranche this token belongs to
        uint8 trancheId = _getTrancheIdForToken(msg.sender);

        // Settle pending yield for both parties before updating mirrors
        _settleYield(trancheId, from);
        _settleYield(trancheId, to);

        // Update plaintext mirrors
        _shares[trancheId][from] -= amount;
        _shares[trancheId][to] += amount;
    }

    // --- View Functions ---

    function getPoolMetrics() external view override returns (PoolMetrics memory) {
        return PoolMetrics({
            totalDeposited: totalPoolDeposited,
            totalYieldReceived: totalYieldReceived,
            totalYieldDistributed: totalYieldDistributed,
            lastDistribution: lastDistribution,
            status: poolStatus
        });
    }

    function getTrancheParams(uint8 trancheId)
        external
        view
        override
        validTranche(trancheId)
        returns (TrancheParams memory)
    {
        return trancheParamsArray[trancheId];
    }

    function getClaimableYield(address investor, uint8 trancheId)
        external
        view
        override
        validTranche(trancheId)
        returns (uint256)
    {
        uint256 pending = _pendingYield[trancheId][investor];
        uint256 shares = _shares[trancheId][investor];
        if (shares == 0) return pending;

        uint256 newYield = WaterfallDistributor.calculateUserYield(
            shares, yieldPerShare[trancheId], _yieldCheckpoint[trancheId][investor]
        );
        return pending + newYield;
    }

    /// @notice Get a user's share count (Zone 2 data — not publicly exposed in production)
    /// @dev In production with eERC, this function would be restricted to internal use only.
    ///      Exposed here for testing purposes.
    function getShares(address user, uint8 trancheId) external view returns (uint256) {
        return _shares[trancheId][user];
    }

    // --- Internal Functions ---

    /// @notice Settle pending yield for a user before any share change
    function _settleYield(uint8 trancheId, address user) internal {
        uint256 shares = _shares[trancheId][user];
        if (shares > 0) {
            uint256 newYield = WaterfallDistributor.calculateUserYield(
                shares, yieldPerShare[trancheId], _yieldCheckpoint[trancheId][user]
            );
            _pendingYield[trancheId][user] += newYield;
        }
        _yieldCheckpoint[trancheId][user] = yieldPerShare[trancheId];
    }

    /// @notice Identify which tranche a token address belongs to
    function _getTrancheIdForToken(address token) internal view returns (uint8) {
        for (uint8 i = 0; i < NUM_TRANCHES;) {
            if (address(trancheTokens[i]) == token) return i;
            unchecked { ++i; }
        }
        revert("ForgeVault: unknown tranche token");
    }

    /// @notice Calculate total pending yield across all users and tranches
    /// @dev Tracks the difference between distributed and claimed yield globally.
    function _totalPendingYield() internal view returns (uint256 total) {
        return totalYieldDistributed - totalYieldClaimed;
    }

    // --- Access Control Transfers (Two-Step) ---

    address public pendingOriginator;
    address public pendingProtocolAdmin;

    event OriginatorTransferStarted(address indexed previousOriginator, address indexed newOriginator);
    event OriginatorTransferred(address indexed previousOriginator, address indexed newOriginator);
    event ProtocolAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event ProtocolAdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    function transferOriginator(address newOriginator) external onlyOriginator {
        require(newOriginator != address(0), "ForgeVault: zero address");
        pendingOriginator = newOriginator;
        emit OriginatorTransferStarted(originator, newOriginator);
    }

    function acceptOriginator() external {
        require(msg.sender == pendingOriginator, "ForgeVault: not pending originator");
        emit OriginatorTransferred(originator, msg.sender);
        originator = msg.sender;
        pendingOriginator = address(0);
    }

    function transferProtocolAdmin(address newAdmin) external {
        require(msg.sender == protocolAdmin, "ForgeVault: not protocol admin");
        require(newAdmin != address(0), "ForgeVault: zero address");
        pendingProtocolAdmin = newAdmin;
        emit ProtocolAdminTransferStarted(protocolAdmin, newAdmin);
    }

    function acceptProtocolAdmin() external {
        require(msg.sender == pendingProtocolAdmin, "ForgeVault: not pending admin");
        emit ProtocolAdminTransferred(protocolAdmin, msg.sender);
        protocolAdmin = msg.sender;
        pendingProtocolAdmin = address(0);
    }

    function setTreasury(address newTreasury) external {
        require(msg.sender == protocolAdmin, "ForgeVault: not protocol admin");
        require(newTreasury != address(0), "ForgeVault: zero address");
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }
}
