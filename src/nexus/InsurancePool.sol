// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IInsurancePool} from "../interfaces/IInsurancePool.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title InsurancePool
/// @notice Backstop for NexusHub liquidation shortfalls.
/// @dev Holds reserve token (USDC) deposits. When liquidation proceeds are insufficient
///      to cover obligations, NexusHub calls coverShortfall() to absorb the difference.
///      Depositors share losses pro-rata if the pool absorbs shortfalls.
///      Funded by direct deposits + insurance premiums (% of obligations).
contract InsurancePool is IInsurancePool, ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    IERC20 public immutable reserveToken;
    address public nexusHub;

    uint256 public totalReserves;
    uint256 public totalCovered;
    uint256 public totalPremiumsCollected;
    uint256 public premiumRateBps;

    mapping(address => uint256) public deposits;
    uint256 public totalDeposited;

    constructor(
        address reserveToken_,
        address nexusHub_,
        uint256 premiumRateBps_
    ) Ownable(msg.sender) {
        require(reserveToken_ != address(0), "InsurancePool: zero token");
        require(premiumRateBps_ <= 1000, "InsurancePool: rate > 10%");
        reserveToken = IERC20(reserveToken_);
        nexusHub = nexusHub_;
        premiumRateBps = premiumRateBps_;
    }

    modifier onlyNexusHub() {
        require(msg.sender == nexusHub, "InsurancePool: not hub");
        _;
    }

    /// @notice Deposit reserves into the insurance pool
    function deposit(uint256 amount) external override nonReentrant whenNotPaused {
        require(amount > 0, "InsurancePool: zero amount");
        reserveToken.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposited += amount;
        totalReserves += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw reserves (pro-rata share — may be less if shortfalls absorbed)
    /// @dev The deposit record is reduced proportionally to the fraction of effective
    ///      balance withdrawn, keeping totalReserves/totalDeposited ratio consistent
    ///      for remaining depositors.
    function withdraw(uint256 amount) external override nonReentrant {
        require(amount > 0, "InsurancePool: zero amount");
        require(deposits[msg.sender] >= amount, "InsurancePool: insufficient deposit");

        uint256 effectiveBalance = _effectiveBalance(msg.sender);
        uint256 withdrawable = MeridianMath.min(amount, effectiveBalance);
        require(withdrawable > 0, "InsurancePool: nothing to withdraw");

        // Scale deposit record proportionally to the fraction of effective balance withdrawn.
        // Example: deposit=100, effective=80, withdraw=50 → reduce deposit by (50/80)*100 = 62.5
        // This keeps the totalReserves/totalDeposited ratio consistent for remaining depositors.
        uint256 depositReduction;
        if (withdrawable == effectiveBalance) {
            // Full withdrawal: clear entire deposit record
            depositReduction = deposits[msg.sender];
        } else {
            depositReduction = (deposits[msg.sender] * withdrawable) / effectiveBalance;
            if (depositReduction == 0) depositReduction = 1; // prevent dust lock
        }

        deposits[msg.sender] -= depositReduction;
        totalDeposited -= depositReduction;
        totalReserves -= withdrawable;

        reserveToken.safeTransfer(msg.sender, withdrawable);
        emit Withdrawn(msg.sender, withdrawable);
    }

    /// @notice Cover a liquidation shortfall (called by NexusHub)
    /// @param user The user whose shortfall is being covered
    /// @param shortfall The amount to cover
    /// @return covered The amount actually covered (may be less if reserves insufficient)
    function coverShortfall(
        address user,
        uint256 shortfall
    ) external override onlyNexusHub nonReentrant returns (uint256 covered) {
        covered = MeridianMath.min(shortfall, totalReserves);
        if (covered == 0) return 0;

        totalReserves -= covered;
        totalCovered += covered;

        reserveToken.safeTransfer(nexusHub, covered);

        emit ShortfallCovered(user, shortfall, covered);
    }

    /// @notice Collect insurance premium from a borrower
    /// @param from Address to pull premium from (must have approved this contract)
    /// @param borrowAmount The obligation amount to calculate premium on
    function collectPremium(
        address from,
        uint256 borrowAmount
    ) external override nonReentrant whenNotPaused {
        if (premiumRateBps == 0) return;
        uint256 premium = MeridianMath.bpsMul(borrowAmount, premiumRateBps);
        if (premium == 0) return;

        reserveToken.safeTransferFrom(from, address(this), premium);
        totalReserves += premium;
        totalPremiumsCollected += premium;

        emit PremiumCollected(from, premium);
    }

    // --- Admin ---

    function setPremiumRate(uint256 newRate) external onlyOwner {
        require(newRate <= 1000, "InsurancePool: rate > 10%");
        uint256 oldRate = premiumRateBps;
        premiumRateBps = newRate;
        emit PremiumRateUpdated(oldRate, newRate);
    }

    function setNexusHub(address newHub) external onlyOwner {
        address oldHub = nexusHub;
        nexusHub = newHub;
        emit NexusHubUpdated(oldHub, newHub);
    }

    // --- View ---

    function getReserves() external view override returns (uint256) {
        return totalReserves;
    }

    function getEffectiveBalance(address depositor) external view override returns (uint256) {
        return _effectiveBalance(depositor);
    }

    function _effectiveBalance(address depositor) internal view returns (uint256) {
        if (totalDeposited == 0) return 0;
        return (deposits[depositor] * totalReserves) / totalDeposited;
    }

    // --- Pausable ---

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
