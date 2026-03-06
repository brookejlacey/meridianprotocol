// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title StrategyRouter
/// @notice Multi-vault yield optimizer. Splits capital across multiple YieldVaults
///         based on configurable allocation strategies.
/// @dev Governance creates strategies (e.g., "Conservative" = 80% Senior + 20% Mezz).
///      Users open positions in a strategy → capital is split proportionally.
///      Users can rebalance to a different strategy at any time.
///
///      Example strategies:
///      - "Conservative": 80% Senior YieldVault + 20% Mezzanine YieldVault
///      - "Balanced":     50% Senior + 30% Mezz + 20% Equity
///      - "Aggressive":   30% Mezz + 70% Equity YieldVault
contract StrategyRouter is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // --- Structs ---
    struct Strategy {
        string name;
        address[] vaults;       // YieldVault addresses (IERC4626)
        uint256[] allocations;  // BPS per vault (sum = 10_000)
        bool active;
    }

    struct PositionInfo {
        address user;
        uint256 strategyId;
        uint256 totalDeposited;
    }

    // --- State ---
    uint256 public nextStrategyId;
    uint256 public nextPositionId;
    address public governance;

    mapping(uint256 => Strategy) internal _strategies;
    mapping(uint256 => PositionInfo) internal _positionInfo;
    mapping(uint256 => mapping(address => uint256)) internal _positionShares; // positionId => vault => shares
    mapping(address => uint256[]) internal _userPositions;

    // --- Events ---
    event StrategyCreated(uint256 indexed strategyId, string name);
    event StrategyPaused(uint256 indexed strategyId);
    event PositionOpened(uint256 indexed positionId, address indexed user, uint256 strategyId, uint256 amount);
    event PositionClosed(uint256 indexed positionId, address indexed user, uint256 amountOut);
    event PositionRebalanced(uint256 indexed positionId, uint256 oldStrategyId, uint256 newStrategyId);

    modifier onlyGovernance() {
        require(msg.sender == governance, "StrategyRouter: not governance");
        _;
    }

    constructor(address governance_) {
        require(governance_ != address(0), "StrategyRouter: zero governance");
        governance = governance_;
    }

    // --- Governance ---

    function createStrategy(
        string calldata name,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external onlyGovernance returns (uint256 strategyId) {
        require(vaults.length == allocations.length, "StrategyRouter: length mismatch");
        require(vaults.length > 0 && vaults.length <= 3, "StrategyRouter: invalid vault count");

        uint256 totalAlloc;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAlloc += allocations[i];
        }
        require(totalAlloc == 10_000, "StrategyRouter: must sum to 10000");

        strategyId = nextStrategyId++;
        Strategy storage s = _strategies[strategyId];
        s.name = name;
        s.vaults = vaults;
        s.allocations = allocations;
        s.active = true;

        emit StrategyCreated(strategyId, name);
    }

    function pauseStrategy(uint256 strategyId) external onlyGovernance {
        _strategies[strategyId].active = false;
        emit StrategyPaused(strategyId);
    }

    // --- User Functions ---

    /// @notice Open a position in a strategy
    /// @param strategyId Strategy to invest in
    /// @param amount Total underlying amount to deposit
    function openPosition(uint256 strategyId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 positionId)
    {
        Strategy storage strat = _strategies[strategyId];
        require(strat.active, "StrategyRouter: strategy not active");
        require(amount > 0, "StrategyRouter: zero amount");

        // Determine underlying asset from first vault
        address underlying = IERC4626(strat.vaults[0]).asset();

        // Pull underlying from user
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        // Create position
        positionId = nextPositionId++;
        _positionInfo[positionId] = PositionInfo({
            user: msg.sender,
            strategyId: strategyId,
            totalDeposited: amount
        });

        // Deposit into each vault according to allocation
        uint256 allocated;
        for (uint256 i = 0; i < strat.vaults.length; i++) {
            // Last vault gets remainder to prevent BPS rounding dust
            uint256 allocAmount = (i == strat.vaults.length - 1)
                ? amount - allocated
                : MeridianMath.bpsMul(amount, strat.allocations[i]);
            allocated += allocAmount;
            if (allocAmount == 0) continue;

            address vaultAddr = strat.vaults[i];
            IERC20(underlying).approve(vaultAddr, allocAmount);
            uint256 shares = IERC4626(vaultAddr).deposit(allocAmount, address(this));
            _positionShares[positionId][vaultAddr] = shares;
        }

        _userPositions[msg.sender].push(positionId);
        emit PositionOpened(positionId, msg.sender, strategyId, amount);
    }

    /// @notice Close a position and withdraw all funds
    function closePosition(uint256 positionId) external nonReentrant returns (uint256 totalOut) {
        PositionInfo storage info = _positionInfo[positionId];
        require(info.user == msg.sender, "StrategyRouter: not owner");

        Strategy storage strat = _strategies[info.strategyId];
        address underlying = IERC4626(strat.vaults[0]).asset();

        // Redeem from all vaults
        for (uint256 i = 0; i < strat.vaults.length; i++) {
            address vaultAddr = strat.vaults[i];
            uint256 shares = _positionShares[positionId][vaultAddr];
            if (shares == 0) continue;

            totalOut += IERC4626(vaultAddr).redeem(shares, address(this), address(this));
            delete _positionShares[positionId][vaultAddr];
        }

        IERC20(underlying).safeTransfer(msg.sender, totalOut);

        // Clear position info to prevent stale references
        delete _positionInfo[positionId];

        emit PositionClosed(positionId, msg.sender, totalOut);
    }

    /// @notice Rebalance a position to a different strategy
    function rebalance(uint256 positionId, uint256 newStrategyId) external nonReentrant whenNotPaused {
        PositionInfo storage info = _positionInfo[positionId];
        require(info.user == msg.sender, "StrategyRouter: not owner");

        Strategy storage oldStrat = _strategies[info.strategyId];
        Strategy storage newStrat = _strategies[newStrategyId];
        require(newStrat.active, "StrategyRouter: target not active");

        address underlying = IERC4626(oldStrat.vaults[0]).asset();
        uint256 oldId = info.strategyId;

        // Withdraw from old strategy
        uint256 totalAssets;
        for (uint256 i = 0; i < oldStrat.vaults.length; i++) {
            address vaultAddr = oldStrat.vaults[i];
            uint256 shares = _positionShares[positionId][vaultAddr];
            if (shares == 0) continue;

            totalAssets += IERC4626(vaultAddr).redeem(shares, address(this), address(this));
            delete _positionShares[positionId][vaultAddr];
        }

        // Deposit into new strategy
        uint256 allocated;
        for (uint256 i = 0; i < newStrat.vaults.length; i++) {
            // Last vault gets remainder to prevent BPS rounding dust
            uint256 allocAmount = (i == newStrat.vaults.length - 1)
                ? totalAssets - allocated
                : MeridianMath.bpsMul(totalAssets, newStrat.allocations[i]);
            allocated += allocAmount;
            if (allocAmount == 0) continue;

            address vaultAddr = newStrat.vaults[i];
            IERC20(underlying).approve(vaultAddr, allocAmount);
            uint256 shares = IERC4626(vaultAddr).deposit(allocAmount, address(this));
            _positionShares[positionId][vaultAddr] = shares;
        }

        info.strategyId = newStrategyId;
        emit PositionRebalanced(positionId, oldId, newStrategyId);
    }

    // --- View ---

    function getStrategy(uint256 strategyId)
        external
        view
        returns (string memory name, address[] memory vaults, uint256[] memory allocations, bool active)
    {
        Strategy storage s = _strategies[strategyId];
        return (s.name, s.vaults, s.allocations, s.active);
    }

    function getPositionValue(uint256 positionId) external view returns (uint256 totalValue) {
        PositionInfo storage info = _positionInfo[positionId];
        Strategy storage strat = _strategies[info.strategyId];

        for (uint256 i = 0; i < strat.vaults.length; i++) {
            address vaultAddr = strat.vaults[i];
            uint256 shares = _positionShares[positionId][vaultAddr];
            if (shares == 0) continue;
            totalValue += IERC4626(vaultAddr).convertToAssets(shares);
        }
    }

    function getPositionInfo(uint256 positionId)
        external
        view
        returns (address user, uint256 strategyId, uint256 totalDeposited)
    {
        PositionInfo storage info = _positionInfo[positionId];
        return (info.user, info.strategyId, info.totalDeposited);
    }

    function getUserPositions(address user) external view returns (uint256[] memory) {
        return _userPositions[user];
    }

    // --- Pausable ---

    function pause() external onlyGovernance {
        _pause();
    }

    function unpause() external onlyGovernance {
        _unpause();
    }

    // --- Governance Transfer (Two-Step) ---

    address public pendingGovernance;

    event GovernanceTransferStarted(address indexed previousGov, address indexed newGov);
    event GovernanceTransferred(address indexed previousGov, address indexed newGov);

    function transferGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "StrategyRouter: zero address");
        pendingGovernance = newGov;
        emit GovernanceTransferStarted(governance, newGov);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "StrategyRouter: not pending governance");
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }
}
