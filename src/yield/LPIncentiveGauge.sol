// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CDSPool} from "../shield/CDSPool.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title LPIncentiveGauge
/// @notice External liquidity mining gauge for CDSPool LPs.
/// @dev Reads LP shares from CDSPool (no pool modifications needed).
///      Distributes reward tokens using a Synthetix StakingRewards-style
///      reward-per-share accumulator. Time-weighted, proportional to LP share holdings.
///
///      SECURITY NOTE: This gauge reads live pool balances. LPs MUST call checkpoint()
///      on the gauge after every pool deposit/withdraw to get accurate time-weighted
///      rewards. Without checkpoint calls, flash-deposit attacks can steal rewards.
///      For production, integrate gauge.checkpoint(user) calls into CDSPool deposit/withdraw.
///
///      Flow:
///      1. Governance calls notifyRewardAmount(reward, duration) to fund the gauge
///      2. LPs accrue rewards proportional to their pool shares over time
///      3. LPs call claimReward() to collect accrued rewards
contract LPIncentiveGauge is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    CDSPool public immutable POOL;
    IERC20 public immutable REWARD_TOKEN;
    address public governance;

    uint256 public rewardRate;              // Reward tokens per second (WAD-scaled)
    uint256 public rewardPerShareStored;    // Accumulated reward per share (WAD)
    uint256 public lastUpdateTime;
    uint256 public periodFinish;            // When current reward period ends

    mapping(address => uint256) public userRewardPerSharePaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward, uint256 duration);
    event RewardPaid(address indexed user, uint256 reward);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);

    modifier onlyGovernance() {
        require(msg.sender == governance, "LPIncentiveGauge: not governance");
        _;
    }

    modifier updateReward(address account) {
        rewardPerShareStored = rewardPerShare();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerSharePaid[account] = rewardPerShareStored;
        }
        _;
    }

    constructor(address pool_, address rewardToken_, address governance_) {
        require(pool_ != address(0), "LPIncentiveGauge: zero pool");
        require(rewardToken_ != address(0), "LPIncentiveGauge: zero reward");
        require(governance_ != address(0), "LPIncentiveGauge: zero governance");

        POOL = CDSPool(pool_);
        REWARD_TOKEN = IERC20(rewardToken_);
        governance = governance_;
    }

    // --- Governance ---

    /// @notice Fund the gauge with reward tokens over a duration
    /// @param reward Amount of reward tokens to distribute
    /// @param duration Distribution period in seconds
    function notifyRewardAmount(uint256 reward, uint256 duration)
        external
        onlyGovernance
        whenNotPaused
        updateReward(address(0))
    {
        require(reward > 0, "LPIncentiveGauge: zero reward");
        require(duration > 0, "LPIncentiveGauge: zero duration");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / duration;
        }

        // Prevent dust rewards that truncate to zero rate
        require(rewardRate > 0, "LPIncentiveGauge: reward too small for duration");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;

        REWARD_TOKEN.safeTransferFrom(msg.sender, address(this), reward);

        emit RewardAdded(reward, duration);
    }

    address public pendingGovernance;

    event GovernanceTransferStarted(address indexed previousGov, address indexed newGov);

    function transferGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "LPIncentiveGauge: zero address");
        pendingGovernance = newGov;
        emit GovernanceTransferStarted(governance, newGov);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "LPIncentiveGauge: not pending governance");
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    // --- User Functions ---

    /// @notice Claim accumulated rewards
    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            REWARD_TOKEN.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Update reward state for an account without claiming
    function checkpoint(address account) external updateReward(account) {}

    // --- View ---

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerShare() public view returns (uint256) {
        uint256 supply = POOL.totalShares();
        if (supply == 0) {
            return rewardPerShareStored;
        }

        uint256 timeDelta = lastTimeRewardApplicable() - lastUpdateTime;
        uint256 rewardDelta = timeDelta * rewardRate;

        return rewardPerShareStored + MeridianMath.wadDiv(rewardDelta, supply);
    }

    function earned(address account) public view returns (uint256) {
        uint256 shares = POOL.sharesOf(account);
        uint256 delta = rewardPerShare() - userRewardPerSharePaid[account];
        return rewards[account] + MeridianMath.wadMul(shares, delta);
    }

    // --- Pausable ---

    function pause() external onlyGovernance {
        _pause();
    }

    function unpause() external onlyGovernance {
        _unpause();
    }
}
