// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {INexusVault} from "../interfaces/INexusVault.sol";
import {CollateralOracle} from "./CollateralOracle.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title NexusVault
/// @notice Collateral custody vault deployed on each Avalanche L1.
/// @dev Holds user deposits, sends balance attestations to NexusHub via Teleporter,
///      and executes liquidations on instruction from the Hub.
///
///      Cross-chain message types:
///        1 = BALANCE_ATTESTATION: (uint8 msgType, address user, uint256 totalValue)
///        2 = LIQUIDATE: (uint8 msgType, address user)
///        3 = LIQUIDATION_COMPLETE: (uint8 msgType, address user, uint256 proceeds)
///
///      MVP: uses MockTeleporter. In production, extends TeleporterRegistryOwnableApp.
contract NexusVault is INexusVault, ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    // --- State ---

    /// @notice CollateralOracle for local asset valuation
    CollateralOracle public oracle;

    /// @notice MockTeleporter address for cross-chain messaging
    address public teleporter;

    /// @notice The NexusHub chain ID (where attestations are sent)
    bytes32 public hubChainId;

    /// @notice The NexusHub address on C-Chain
    address public hubAddress;

    /// @notice User deposits: user → asset → amount
    mapping(address user => mapping(address asset => uint256)) public deposits;

    /// @notice List of assets deposited by a user
    mapping(address user => address[]) private _userAssets;

    /// @notice Whether user has deposited a specific asset
    mapping(address user => mapping(address asset => bool)) private _hasDeposited;

    /// @notice Minimum seconds between attestations per user
    uint256 public attestationInterval;

    /// @notice Last attestation time per user
    mapping(address user => uint256) public lastAttestation;

    /// @notice Whether a user's collateral is locked (active cross-chain position)
    mapping(address user => bool) public withdrawalLocked;

    /// @notice Processed message hashes for replay protection
    mapping(bytes32 => bool) public processedMessages;

    // --- Events ---
    event AttestationSent(address indexed user, uint256 totalValue);

    constructor(
        address oracle_,
        address teleporter_,
        bytes32 hubChainId_,
        address hubAddress_,
        uint256 attestationInterval_
    ) Ownable(msg.sender) {
        require(oracle_ != address(0), "NexusVault: zero oracle");
        require(hubAddress_ != address(0), "NexusVault: zero hub");

        oracle = CollateralOracle(oracle_);
        teleporter = teleporter_;
        hubChainId = hubChainId_;
        hubAddress = hubAddress_;
        attestationInterval = attestationInterval_;
    }

    // --- User Functions ---

    /// @notice Deposit collateral into this vault
    /// @param asset ERC-20 collateral token
    /// @param amount Amount to deposit
    function deposit(address asset, uint256 amount) external override nonReentrant {
        require(amount > 0, "NexusVault: zero amount");
        require(oracle.isSupported(asset), "NexusVault: unsupported asset");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        deposits[msg.sender][asset] += amount;

        if (!_hasDeposited[msg.sender][asset]) {
            _hasDeposited[msg.sender][asset] = true;
            _userAssets[msg.sender].push(asset);
        }

        emit Deposited(msg.sender, asset, amount);
    }

    /// @notice Withdraw collateral
    /// @dev Withdrawal is blocked while user has an active cross-chain attestation.
    ///      User must call unlockWithdrawal() (which re-attests zero or reduced balance) first.
    /// @param asset ERC-20 collateral token
    /// @param amount Amount to withdraw
    function withdraw(address asset, uint256 amount) external override nonReentrant {
        require(amount > 0, "NexusVault: zero amount");
        require(!withdrawalLocked[msg.sender], "NexusVault: locked - attest updated balance first");
        require(deposits[msg.sender][asset] >= amount, "NexusVault: insufficient balance");

        deposits[msg.sender][asset] -= amount;
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, asset, amount);
    }

    /// @notice Send a balance attestation to NexusHub via Teleporter
    /// @dev Anyone can call this to attest their own balances.
    ///      Attests total risk-adjusted collateral value for the caller.
    function attestBalances() external override {
        require(
            block.timestamp >= lastAttestation[msg.sender] + attestationInterval,
            "NexusVault: too soon"
        );

        uint256 totalValue = _getUserTotalValue(msg.sender);
        lastAttestation[msg.sender] = block.timestamp;

        // Lock withdrawals while attestation is active on Hub
        if (totalValue > 0) {
            withdrawalLocked[msg.sender] = true;
        }

        // Encode attestation message: (msgType=1, user, totalValue)
        bytes memory message = abi.encode(uint8(1), msg.sender, totalValue);

        // Send via MockTeleporter
        _sendMessage(message);

        emit AttestationSent(msg.sender, totalValue);
        emit BalancesAttested(msg.sender, totalValue);
    }

    /// @notice Unlock withdrawals by re-attesting current balance to Hub
    /// @dev This sends an updated attestation so the Hub has accurate collateral values
    ///      before any withdrawal occurs.
    function unlockWithdrawal() external {
        require(withdrawalLocked[msg.sender], "NexusVault: not locked");
        require(
            block.timestamp >= lastAttestation[msg.sender] + attestationInterval,
            "NexusVault: too soon"
        );

        uint256 totalValue = _getUserTotalValue(msg.sender);
        lastAttestation[msg.sender] = block.timestamp;
        withdrawalLocked[msg.sender] = false;

        // Re-attest current balance so Hub has accurate data
        bytes memory message = abi.encode(uint8(1), msg.sender, totalValue);
        _sendMessage(message);

        emit AttestationSent(msg.sender, totalValue);
    }

    /// @notice Execute liquidation ordered by NexusHub
    /// @dev Called via Teleporter message from Hub. Seizes all user collateral.
    ///      For MVP, admin can also call this directly.
    function executeLiquidation(address user) external override nonReentrant {
        require(
            msg.sender == owner() || msg.sender == teleporter,
            "NexusVault: not authorized"
        );

        uint256 totalProceeds;
        address[] memory assets = _userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balance = deposits[user][assets[i]];
            if (balance > 0) {
                deposits[user][assets[i]] = 0;
                totalProceeds += oracle.getCollateralValue(assets[i], balance);
                // In production: sell on DEX and send proceeds to Hub
                // For MVP: just transfer to owner (protocol treasury)
                IERC20(assets[i]).safeTransfer(owner(), balance);
            }
        }

        // Send liquidation complete message to Hub
        bytes memory message = abi.encode(uint8(3), user, totalProceeds);
        _sendMessage(message);

        emit LiquidationExecuted(user, totalProceeds);
    }

    /// @notice Receive a Teleporter message (liquidation order from Hub)
    function receiveTeleporterMessage(
        bytes32 sourceChainId,
        address sender,
        bytes calldata message
    ) external {
        require(msg.sender == teleporter, "NexusVault: not teleporter");
        require(sourceChainId == hubChainId, "NexusVault: wrong source chain");
        require(sender == hubAddress, "NexusVault: wrong sender");

        // Replay protection
        bytes32 msgHash = keccak256(abi.encodePacked(sourceChainId, sender, message));
        require(!processedMessages[msgHash], "NexusVault: message already processed");
        processedMessages[msgHash] = true;

        (uint8 msgType, address user) = abi.decode(message, (uint8, address));

        if (msgType == 2) {
            // LIQUIDATE order from Hub
            _executeLiquidationInternal(user);
        }
    }

    // --- View Functions ---

    /// @notice Get a user's deposit for a specific asset
    function getUserDeposit(address user, address asset) external view override returns (uint256) {
        return deposits[user][asset];
    }

    /// @notice Get total risk-adjusted value of a user's deposits
    function getUserTotalValue(address user) external view returns (uint256) {
        return _getUserTotalValue(user);
    }

    /// @notice Get list of assets deposited by a user
    function getUserAssets(address user) external view returns (address[] memory) {
        return _userAssets[user];
    }

    // --- Internal ---

    function _getUserTotalValue(address user) internal view returns (uint256 total) {
        address[] memory assets = _userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balance = deposits[user][assets[i]];
            if (balance > 0) {
                total += oracle.getCollateralValue(assets[i], balance);
            }
        }
    }

    function _sendMessage(bytes memory message) internal {
        // Use MockTeleporter's simplified interface
        (bool success,) = teleporter.call(
            abi.encodeWithSignature(
                "sendCrossChainMessage(bytes32,address,bytes,uint256)",
                hubChainId,
                hubAddress,
                message,
                uint256(200_000) // gas limit
            )
        );
        require(success, "NexusVault: teleporter send failed");
    }

    function _executeLiquidationInternal(address user) internal {
        uint256 totalProceeds;
        address[] memory assets = _userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balance = deposits[user][assets[i]];
            if (balance > 0) {
                deposits[user][assets[i]] = 0;
                totalProceeds += oracle.getCollateralValue(assets[i], balance);
                IERC20(assets[i]).safeTransfer(owner(), balance);
            }
        }

        // Notify Hub that liquidation is complete
        bytes memory message = abi.encode(uint8(3), user, totalProceeds);
        _sendMessage(message);

        emit LiquidationExecuted(user, totalProceeds);
    }
}
