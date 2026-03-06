// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAIKeeper} from "../interfaces/IAIKeeper.sol";
import {ICreditEventOracle} from "../interfaces/ICreditEventOracle.sol";
import {ICDSPool} from "../interfaces/ICDSPool.sol";
import {NexusHub} from "../nexus/NexusHub.sol";
import {CDSPoolFactory} from "../shield/CDSPoolFactory.sol";
import {CreditEventOracle} from "../shield/CreditEventOracle.sol";

/// @title AIKeeper
/// @notice AI-prioritized liquidation keeper for NexusHub margin accounts.
/// @dev Off-chain AI monitors accounts and assigns priority scores. On-chain keeper
///      functions execute liquidations in priority order (highest risk first).
///
///      Unlike LiquidationBot (stateless, caller-ordered), AIKeeper maintains a
///      priority registry that the AI populates. This enables smarter liquidation:
///      - Liquidate accounts most likely to become insolvent first
///      - Flag accounts that may be attempting to avoid liquidation
///      - Prioritized waterfall: oracle check → pool trigger → settle → liquidate in order
///
///      All execution functions are permissionless — anyone can call them.
///      The AI only populates priority data.
contract AIKeeper is IAIKeeper {
    // --- State ---
    NexusHub public immutable NEXUS_HUB;
    CreditEventOracle public immutable ORACLE;
    CDSPoolFactory public immutable POOL_FACTORY;

    mapping(address => AccountPriority) private _priorities;
    address[] public monitoredAccounts;
    mapping(address => uint256) private _accountIndex;  // 1-indexed (0 = not present)
    mapping(address => bool) public isAIMonitor;
    uint256 public maxPriorityAge;

    address public owner;
    address public pendingOwner;

    // --- Events (admin) ---
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MaxPriorityAgeUpdated(uint256 newMaxAge);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "AIKeeper: not owner");
        _;
    }

    modifier onlyAIMonitor() {
        require(isAIMonitor[msg.sender], "AIKeeper: not monitor");
        _;
    }

    constructor(address nexusHub_, address oracle_, address poolFactory_, uint256 maxPriorityAge_) {
        require(nexusHub_ != address(0), "AIKeeper: zero hub");
        require(oracle_ != address(0), "AIKeeper: zero oracle");
        require(poolFactory_ != address(0), "AIKeeper: zero factory");

        NEXUS_HUB = NexusHub(nexusHub_);
        ORACLE = CreditEventOracle(oracle_);
        POOL_FACTORY = CDSPoolFactory(poolFactory_);
        maxPriorityAge = maxPriorityAge_;
        owner = msg.sender;
    }

    // --- AI Monitor Functions ---

    /// @notice Update priority for a single account
    function updateAccountPriority(
        address account,
        uint256 priorityScore,
        uint256 estimatedShortfall,
        bool flagged
    ) external override onlyAIMonitor {
        _updatePriority(account, priorityScore, estimatedShortfall, flagged);
    }

    /// @notice Batch update priorities
    function batchUpdatePriorities(
        address[] calldata accounts,
        uint256[] calldata scores,
        uint256[] calldata shortfalls,
        bool[] calldata flags
    ) external override onlyAIMonitor {
        require(
            accounts.length == scores.length &&
            accounts.length == shortfalls.length &&
            accounts.length == flags.length,
            "AIKeeper: length mismatch"
        );

        for (uint256 i = 0; i < accounts.length;) {
            _updatePriority(accounts[i], scores[i], shortfalls[i], flags[i]);
            unchecked { ++i; }
        }
    }

    /// @notice Remove an account from monitoring
    function removeAccount(address account) external override onlyAIMonitor {
        require(_accountIndex[account] > 0, "AIKeeper: not monitored");
        _removeFromList(account);
        delete _priorities[account];
        emit AccountRemoved(account);
    }

    // --- Keeper Execution (Permissionless) ---

    /// @notice Liquidate the top N accounts by priority score
    function liquidateTopN(uint256 n) external override returns (uint256 liquidatedCount) {
        uint256 len = monitoredAccounts.length;
        if (n > len) n = len;
        if (n == 0) return 0;

        // Find top N by score using in-memory sort
        address[] memory topAccounts = _getTopNAccounts(n);

        for (uint256 i = 0; i < topAccounts.length;) {
            if (topAccounts[i] == address(0)) break;
            try NEXUS_HUB.triggerLiquidation(topAccounts[i]) {
                uint256 score = _priorities[topAccounts[i]].priorityScore;
                emit PrioritizedLiquidation(topAccounts[i], msg.sender, score);
                liquidatedCount++;
            } catch {
                // Account may be healthy — skip silently
            }
            unchecked { ++i; }
        }
    }

    /// @notice Liquidate all flagged accounts
    function liquidateAllFlagged() external override returns (uint256 liquidatedCount) {
        uint256 len = monitoredAccounts.length;
        for (uint256 i = 0; i < len;) {
            address account = monitoredAccounts[i];
            if (_priorities[account].flagged) {
                try NEXUS_HUB.triggerLiquidation(account) {
                    uint256 score = _priorities[account].priorityScore;
                    emit PrioritizedLiquidation(account, msg.sender, score);
                    liquidatedCount++;
                } catch {
                    // Skip healthy accounts
                }
            }
            unchecked { ++i; }
        }
    }

    /// @notice Execute prioritized waterfall for a vault
    function executePrioritizedWaterfall(
        address vault,
        uint256 recoveryRateWad,
        uint256 maxAccounts
    ) external override returns (uint256 poolsTriggered, uint256 poolsSettled, uint256 accountsLiquidated) {
        // Step 1: Check oracle and trigger/settle pools
        bool hasEvent = ORACLE.hasActiveEvent(vault);

        if (hasEvent) {
            uint256[] memory poolIds = POOL_FACTORY.getPoolsForVault(vault);
            for (uint256 i = 0; i < poolIds.length;) {
                address pool = POOL_FACTORY.getPool(poolIds[i]);

                try ICDSPool(pool).triggerCreditEvent() {
                    poolsTriggered++;
                } catch {}

                try POOL_FACTORY.settlePool(poolIds[i], recoveryRateWad) {
                    poolsSettled++;
                } catch {}

                unchecked { ++i; }
            }
        }

        // Step 2: Liquidate top N accounts by priority
        uint256 len = monitoredAccounts.length;
        if (maxAccounts > len) maxAccounts = len;

        address[] memory topAccounts = _getTopNAccounts(maxAccounts);
        for (uint256 i = 0; i < topAccounts.length;) {
            if (topAccounts[i] == address(0)) break;
            try NEXUS_HUB.triggerLiquidation(topAccounts[i]) {
                emit PrioritizedLiquidation(topAccounts[i], msg.sender, _priorities[topAccounts[i]].priorityScore);
                accountsLiquidated++;
            } catch {}
            unchecked { ++i; }
        }

        emit PrioritizedWaterfallExecuted(vault, poolsTriggered, poolsSettled, accountsLiquidated);
    }

    // --- Views ---

    /// @notice Get top N accounts by priority score
    function getTopAccounts(uint256 n) external view override returns (AccountPriority[] memory) {
        uint256 len = monitoredAccounts.length;
        if (n > len) n = len;

        address[] memory topAddrs = _getTopNAccounts(n);
        AccountPriority[] memory result = new AccountPriority[](n);
        for (uint256 i = 0; i < n;) {
            if (topAddrs[i] == address(0)) {
                // Trim result
                assembly { mstore(result, i) }
                break;
            }
            result[i] = _priorities[topAddrs[i]];
            unchecked { ++i; }
        }
        return result;
    }

    /// @notice Get all flagged account addresses
    function getFlaggedAccounts() external view override returns (address[] memory) {
        uint256 len = monitoredAccounts.length;
        address[] memory temp = new address[](len);
        uint256 count;

        for (uint256 i = 0; i < len;) {
            if (_priorities[monitoredAccounts[i]].flagged) {
                temp[count++] = monitoredAccounts[i];
            }
            unchecked { ++i; }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count;) {
            result[i] = temp[i];
            unchecked { ++i; }
        }
        return result;
    }

    /// @notice Get priority for a specific account
    function getAccountPriority(address account) external view override returns (AccountPriority memory) {
        return _priorities[account];
    }

    /// @notice Total monitored accounts
    function getMonitoredAccountCount() external view override returns (uint256) {
        return monitoredAccounts.length;
    }

    // --- Admin ---

    function setAIMonitor(address monitor, bool authorized) external onlyOwner {
        require(monitor != address(0), "AIKeeper: zero address");
        isAIMonitor[monitor] = authorized;
        emit AIMonitorUpdated(monitor, authorized);
    }

    function setMaxPriorityAge(uint256 maxAge_) external onlyOwner {
        maxPriorityAge = maxAge_;
        emit MaxPriorityAgeUpdated(maxAge_);
    }

    // --- Ownership (Two-Step) ---

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AIKeeper: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "AIKeeper: not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // --- Internal ---

    function _updatePriority(
        address account,
        uint256 priorityScore,
        uint256 estimatedShortfall,
        bool flagged
    ) internal {
        require(account != address(0), "AIKeeper: zero account");

        // Add to monitored list if new
        if (_accountIndex[account] == 0) {
            monitoredAccounts.push(account);
            _accountIndex[account] = monitoredAccounts.length; // 1-indexed
        }

        _priorities[account] = AccountPriority({
            account: account,
            priorityScore: priorityScore,
            estimatedShortfall: estimatedShortfall,
            timestamp: block.timestamp,
            flagged: flagged
        });

        emit AccountPriorityUpdated(account, priorityScore, estimatedShortfall, flagged);
    }

    function _removeFromList(address account) internal {
        uint256 idx = _accountIndex[account]; // 1-indexed
        if (idx == 0) return;

        uint256 lastIdx = monitoredAccounts.length;
        if (idx != lastIdx) {
            // Swap with last
            address last = monitoredAccounts[lastIdx - 1];
            monitoredAccounts[idx - 1] = last;
            _accountIndex[last] = idx;
        }
        monitoredAccounts.pop();
        delete _accountIndex[account];
    }

    /// @dev In-memory selection of top N accounts by priority score
    function _getTopNAccounts(uint256 n) internal view returns (address[] memory) {
        uint256 len = monitoredAccounts.length;
        if (n > len) n = len;

        // Copy to memory for sorting
        address[] memory accounts = new address[](len);
        uint256[] memory scores = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            accounts[i] = monitoredAccounts[i];
            scores[i] = _priorities[accounts[i]].priorityScore;
            unchecked { ++i; }
        }

        // Partial selection sort for top N
        for (uint256 i = 0; i < n;) {
            uint256 maxIdx = i;
            for (uint256 j = i + 1; j < len;) {
                if (scores[j] > scores[maxIdx]) {
                    maxIdx = j;
                }
                unchecked { ++j; }
            }
            if (maxIdx != i) {
                // Swap
                (accounts[i], accounts[maxIdx]) = (accounts[maxIdx], accounts[i]);
                (scores[i], scores[maxIdx]) = (scores[maxIdx], scores[i]);
            }
            unchecked { ++i; }
        }

        // Return only top N
        address[] memory result = new address[](n);
        for (uint256 i = 0; i < n;) {
            result[i] = accounts[i];
            unchecked { ++i; }
        }
        return result;
    }
}
