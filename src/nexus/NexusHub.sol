// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {INexusHub} from "../interfaces/INexusHub.sol";
import {CollateralOracle} from "./CollateralOracle.sol";
import {MarginAccount} from "../libraries/MarginAccount.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";
import {IInsurancePool} from "../interfaces/IInsurancePool.sol";

/// @title NexusHub
/// @notice Central margin engine on C-Chain. Tracks multi-asset collateral positions,
///         receives cross-chain balance attestations, and triggers liquidations.
/// @dev MVP simplifications:
///      - Local deposits only for now (cross-chain via attestation)
///      - Binary health signal (isHealthy bool)
///      - No borrows for MVP — borrowValue tracked as obligations set by admin
///      - Liquidation penalty fixed at 5%
///
///      Cross-chain flow:
///      1. User deposits on remote L1 NexusVault
///      2. NexusVault sends attestation message via Teleporter
///      3. NexusHub receives and updates cross-chain collateral values
///      4. If unhealthy, anyone can call triggerLiquidation()
///      5. Hub sends liquidation message to remote NexusVault
contract NexusHub is INexusHub, ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    // --- Constants ---

    /// @notice Maximum distinct assets per margin account (prevents unbounded iteration DoS)
    uint256 public constant MAX_ASSETS_PER_ACCOUNT = 20;

    /// @notice Liquidation threshold (WAD). 1.1e18 = 110% — must maintain 110% collateralization
    uint256 public liquidationThreshold;

    /// @notice Liquidation penalty in bps. 500 = 5%
    uint256 public liquidationPenaltyBps;

    // --- State ---

    /// @notice CollateralOracle for pricing
    CollateralOracle public oracle;

    /// @notice Whether a user has an open margin account
    mapping(address user => bool) public hasAccount;

    /// @notice Local collateral deposits: user → asset → amount
    mapping(address user => mapping(address asset => uint256)) public localDeposits;

    /// @notice List of assets deposited locally by a user
    mapping(address user => address[]) private _userAssets;

    /// @notice Whether user has deposited a specific asset (for dedup)
    mapping(address user => mapping(address asset => bool)) private _hasDeposited;

    /// @notice Cross-chain attested collateral value per user per chain
    mapping(address user => mapping(bytes32 chainId => uint256 value)) public crossChainCollateral;

    /// @notice Chains that have attested for a user
    mapping(address user => bytes32[]) private _userChains;
    mapping(address user => mapping(bytes32 chainId => bool)) private _hasChainAttestation;

    /// @notice User obligations (set by admin or protocol — simplified borrow tracking)
    mapping(address user => uint256) public obligations;

    /// @notice Maximum age of cross-chain attestation before it's considered stale (seconds)
    uint256 public attestationMaxAge = 1 hours;

    /// @notice Timestamp of last attestation per user per chain
    mapping(address user => mapping(bytes32 chainId => uint256 timestamp)) public attestationTimestamp;

    /// @notice Teleporter address for cross-chain message verification
    address public teleporter;

    /// @notice Registered NexusVault addresses per chain
    mapping(bytes32 chainId => address vault) public registeredVaults;

    /// @notice Processed message hashes for replay protection
    mapping(bytes32 => bool) public processedMessages;

    /// @notice Insurance pool for covering liquidation shortfalls
    address public insurancePool;

    // --- Protocol Fee ---
    address public treasury;
    uint256 public liquidationFeeBps;
    uint256 public constant MAX_LIQUIDATION_FEE_BPS = 5000; // 50%
    uint256 public totalProtocolFeesCollected;

    // --- Events ---
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event ObligationUpdated(address indexed user, uint256 newObligation);
    event VaultRegistered(bytes32 indexed chainId, address vault);
    event LiquidationExecuted(address indexed user, address indexed liquidator, uint256 collateralSeized);
    event AttestationMaxAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event LiquidationParamsUpdated(uint256 threshold, uint256 penaltyBps);
    event InsurancePoolUpdated(address oldPool, address newPool);

    constructor(
        address oracle_,
        address teleporter_,
        uint256 liquidationThreshold_,
        uint256 liquidationPenaltyBps_
    ) Ownable(msg.sender) {
        require(oracle_ != address(0), "NexusHub: zero oracle");
        require(liquidationThreshold_ >= MeridianMath.WAD, "NexusHub: threshold < 100%");

        oracle = CollateralOracle(oracle_);
        teleporter = teleporter_;
        liquidationThreshold = liquidationThreshold_;
        liquidationPenaltyBps = liquidationPenaltyBps_;
    }

    // --- User Functions ---

    /// @notice Open a margin account
    function openMarginAccount() external override whenNotPaused {
        require(!hasAccount[msg.sender], "NexusHub: account exists");
        hasAccount[msg.sender] = true;
        emit MarginAccountOpened(msg.sender);
    }

    /// @notice Deposit collateral on the local chain (C-Chain)
    /// @param asset ERC-20 collateral token
    /// @param amount Amount to deposit
    function depositCollateral(address asset, uint256 amount) external override nonReentrant whenNotPaused {
        require(hasAccount[msg.sender], "NexusHub: no account");
        require(amount > 0, "NexusHub: zero amount");
        require(oracle.isSupported(asset), "NexusHub: unsupported asset");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        localDeposits[msg.sender][asset] += amount;

        // Track asset list for iteration (bounded to prevent DoS)
        if (!_hasDeposited[msg.sender][asset]) {
            require(
                _userAssets[msg.sender].length < MAX_ASSETS_PER_ACCOUNT,
                "NexusHub: too many assets"
            );
            _hasDeposited[msg.sender][asset] = true;
            _userAssets[msg.sender].push(asset);
        }

        emit CollateralDeposited(msg.sender, asset, amount);
    }

    /// @notice Withdraw collateral (only if position stays healthy)
    /// @param asset ERC-20 collateral token
    /// @param amount Amount to withdraw
    function withdrawCollateral(address asset, uint256 amount) external nonReentrant {
        require(hasAccount[msg.sender], "NexusHub: no account");
        require(amount > 0, "NexusHub: zero amount");
        require(localDeposits[msg.sender][asset] >= amount, "NexusHub: insufficient balance");

        // Check that withdrawal keeps position healthy
        localDeposits[msg.sender][asset] -= amount;

        require(
            _isHealthy(msg.sender),
            "NexusHub: would be unhealthy"
        );

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    /// @notice Trigger liquidation of an unhealthy account
    /// @param user The account to liquidate
    function triggerLiquidation(address user) external override nonReentrant {
        require(hasAccount[user], "NexusHub: no account");
        require(!_isHealthy(user), "NexusHub: account is healthy");

        uint256 userObligation = obligations[user];

        // Seize collateral and transfer to liquidator
        uint256 totalSeized = _seizeCollateral(user, msg.sender);

        // If seized collateral < obligations, attempt insurance coverage
        if (totalSeized < userObligation && insurancePool != address(0)) {
            uint256 shortfall = userObligation - totalSeized;
            uint256 covered = IInsurancePool(insurancePool).coverShortfall(user, shortfall);
            obligations[user] = shortfall - covered;
        } else {
            obligations[user] = 0;
        }

        // Clear cross-chain attestations
        bytes32[] memory chains = _userChains[user];
        for (uint256 i = 0; i < chains.length; i++) {
            crossChainCollateral[user][chains[i]] = 0;
        }

        emit LiquidationTriggered(user, msg.sender);
        emit LiquidationExecuted(user, msg.sender, totalSeized);
    }

    // --- Cross-Chain Messaging ---

    /// @notice Receive a balance attestation from a remote NexusVault via Teleporter
    /// @dev In production, this is called by TeleporterRegistryOwnableApp._receiveTeleporterMessage().
    ///      For MVP, the MockTeleporter calls receiveTeleporterMessage() on this contract.
    /// @param sourceChainId The chain ID the attestation came from
    /// @param sender The NexusVault that sent the attestation
    /// @param message ABI-encoded attestation data
    function receiveTeleporterMessage(
        bytes32 sourceChainId,
        address sender,
        bytes calldata message
    ) external {
        require(msg.sender == teleporter, "NexusHub: not teleporter");
        require(
            registeredVaults[sourceChainId] == sender,
            "NexusHub: unknown vault"
        );

        // Replay protection: hash the full message with source context
        bytes32 msgHash = keccak256(abi.encodePacked(sourceChainId, sender, message));
        require(!processedMessages[msgHash], "NexusHub: message already processed");
        processedMessages[msgHash] = true;

        // Decode attestation: (uint8 msgType, address user, uint256 totalValue)
        (uint8 msgType, address user, uint256 totalValue) = abi.decode(message, (uint8, address, uint256));

        if (msgType == 1) {
            // BALANCE_ATTESTATION
            _processAttestation(sourceChainId, user, totalValue);
        } else if (msgType == 3) {
            // LIQUIDATION_COMPLETE
            _processLiquidationComplete(user, totalValue);
        }
    }

    // --- Admin ---

    /// @notice Register a NexusVault on a remote chain
    function registerVault(bytes32 chainId, address vault) external onlyOwner {
        registeredVaults[chainId] = vault;
        emit VaultRegistered(chainId, vault);
    }

    /// @notice Set obligation for a user (simplified borrow tracking)
    function setObligation(address user, uint256 amount) external onlyOwner {
        require(hasAccount[user], "NexusHub: no account");
        obligations[user] = amount;
        emit ObligationUpdated(user, amount);
    }

    /// @notice Update attestation max age
    function setAttestationMaxAge(uint256 maxAge_) external onlyOwner {
        require(maxAge_ >= 10 minutes, "NexusHub: max age too short");
        uint256 oldMaxAge = attestationMaxAge;
        attestationMaxAge = maxAge_;
        emit AttestationMaxAgeUpdated(oldMaxAge, maxAge_);
    }

    /// @notice Update liquidation parameters
    function setLiquidationParams(uint256 threshold_, uint256 penaltyBps_) external onlyOwner {
        require(threshold_ >= MeridianMath.WAD, "NexusHub: threshold < 100%");
        require(penaltyBps_ <= 5000, "NexusHub: penalty > 50%");
        liquidationThreshold = threshold_;
        liquidationPenaltyBps = penaltyBps_;
        emit LiquidationParamsUpdated(threshold_, penaltyBps_);
    }

    /// @notice Set the insurance pool for covering liquidation shortfalls
    function setInsurancePool(address pool_) external onlyOwner {
        address oldPool = insurancePool;
        insurancePool = pool_;
        emit InsurancePoolUpdated(oldPool, pool_);
    }

    // --- View Functions ---

    /// @notice Get margin ratio for a user (WAD-scaled)
    function getMarginRatio(address user) external view override returns (uint256) {
        MarginAccount.Position memory pos = _buildPosition(user);
        return MarginAccount.marginRatio(pos);
    }

    /// @notice Check if user account is healthy
    function isHealthy(address user) external view override returns (bool) {
        return _isHealthy(user);
    }

    /// @notice Get total collateral value for a user (risk-adjusted, USD, 18 dec)
    function getTotalCollateralValue(address user) external view returns (uint256 total) {
        total = _localCollateralValue(user) + _crossChainCollateralValue(user);
    }

    /// @notice Get local collateral value for a user
    function getLocalCollateralValue(address user) external view returns (uint256) {
        return _localCollateralValue(user);
    }

    /// @notice Get list of assets deposited by a user
    function getUserAssets(address user) external view returns (address[] memory) {
        return _userAssets[user];
    }

    // --- Internal ---

    function _isHealthy(address user) internal view returns (bool) {
        MarginAccount.Position memory pos = _buildPosition(user);
        return MarginAccount.isHealthy(pos, liquidationThreshold);
    }

    function _buildPosition(address user) internal view returns (MarginAccount.Position memory) {
        return MarginAccount.Position({
            collateralValue: _localCollateralValue(user) + _crossChainCollateralValue(user),
            borrowValue: obligations[user]
        });
    }

    function _localCollateralValue(address user) internal view returns (uint256 total) {
        address[] memory assets = _userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balance = localDeposits[user][assets[i]];
            if (balance > 0) {
                total += oracle.getCollateralValue(assets[i], balance);
            }
        }
    }

    function _crossChainCollateralValue(address user) internal view returns (uint256 total) {
        bytes32[] memory chains = _userChains[user];
        for (uint256 i = 0; i < chains.length; i++) {
            // Skip stale attestations
            if (block.timestamp - attestationTimestamp[user][chains[i]] <= attestationMaxAge) {
                total += crossChainCollateral[user][chains[i]];
            }
        }
    }

    function _processAttestation(bytes32 chainId, address user, uint256 totalValue) internal {
        crossChainCollateral[user][chainId] = totalValue;
        attestationTimestamp[user][chainId] = block.timestamp;

        if (!_hasChainAttestation[user][chainId]) {
            _hasChainAttestation[user][chainId] = true;
            _userChains[user].push(chainId);
        }

        emit AttestationReceived(chainId, user);
    }

    /// @dev Seize local collateral from user and transfer to liquidator.
    ///      Seizure is capped at obligation + penalty; excess returned to user.
    function _seizeCollateral(address user, address liquidator) internal returns (uint256 totalSeizedValue) {
        uint256 seizureTarget = obligations[user] +
            MeridianMath.bpsMul(
                MarginAccount.shortfall(_buildPosition(user), liquidationThreshold),
                liquidationPenaltyBps
            );

        address[] memory assets = _userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 bal = localDeposits[user][assets[i]];
            if (bal == 0) continue;

            uint256 val = oracle.getCollateralValue(assets[i], bal);
            localDeposits[user][assets[i]] = 0;

            if (totalSeizedValue + val <= seizureTarget) {
                _transferWithFee(assets[i], bal, liquidator);
                totalSeizedValue += val;
            } else {
                // Partial: seize only what's needed, return rest
                uint256 needed = seizureTarget - totalSeizedValue;
                uint256 price = oracle.getPrice(assets[i]);
                uint256 seizeAmt = price > 0 ? MeridianMath.wadDiv(needed, price) : bal;
                if (seizeAmt > bal) seizeAmt = bal;
                _transferWithFee(assets[i], seizeAmt, liquidator);
                if (bal > seizeAmt) {
                    IERC20(assets[i]).safeTransfer(user, bal - seizeAmt);
                    localDeposits[user][assets[i]] = bal - seizeAmt;
                }
                totalSeizedValue = seizureTarget;
            }
        }
    }

    function _processLiquidationComplete(address user, uint256 proceeds) internal {
        // Reduce obligations proportionally to proceeds received
        // If proceeds >= obligation, clear entirely; otherwise reduce by proceeds amount
        if (proceeds >= obligations[user]) {
            obligations[user] = 0;
        } else {
            obligations[user] -= proceeds;
            // Attempt to cover remaining shortfall via insurance pool
            if (insurancePool != address(0) && obligations[user] > 0) {
                uint256 covered = IInsurancePool(insurancePool).coverShortfall(user, obligations[user]);
                obligations[user] -= covered;
            }
        }
    }

    /// @dev Split seized tokens between liquidator and treasury
    function _transferWithFee(address asset, uint256 amount, address liquidator) internal {
        if (liquidationFeeBps > 0 && treasury != address(0)) {
            uint256 protocolCut = MeridianMath.bpsMul(amount, liquidationFeeBps);
            if (protocolCut > 0) {
                IERC20(asset).safeTransfer(treasury, protocolCut);
                totalProtocolFeesCollected += oracle.getCollateralValue(asset, protocolCut);
                amount -= protocolCut;
            }
        }
        IERC20(asset).safeTransfer(liquidator, amount);
    }

    // --- Protocol Fee Admin ---

    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "NexusHub: zero treasury");
        address oldTreasury = treasury;
        treasury = treasury_;
        emit TreasuryUpdated(oldTreasury, treasury_);
    }

    function setLiquidationFeeBps(uint256 feeBps) external onlyOwner {
        require(feeBps <= MAX_LIQUIDATION_FEE_BPS, "NexusHub: fee exceeds max");
        uint256 oldFeeBps = liquidationFeeBps;
        liquidationFeeBps = feeBps;
        emit LiquidationFeeUpdated(oldFeeBps, feeBps);
    }

    // --- Pausable ---

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
