// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {YieldVault} from "./YieldVault.sol";

/// @title YieldVaultFactory
/// @notice Creates and tracks YieldVault instances.
/// @dev One YieldVault per (ForgeVault, trancheId) pair.
contract YieldVaultFactory {
    address public owner;
    address public pauseAdmin;

    uint256 public vaultCount;
    mapping(uint256 => address) public vaults;
    mapping(address => mapping(uint8 => address)) public vaultByForgeAndTranche;

    event YieldVaultCreated(
        uint256 indexed vaultId,
        address indexed yieldVault,
        address indexed forgeVault,
        uint8 trancheId,
        string name,
        string symbol
    );

    constructor(address pauseAdmin_) {
        require(pauseAdmin_ != address(0), "YieldVaultFactory: zero pause admin");
        owner = msg.sender;
        pauseAdmin = pauseAdmin_;
    }

    /// @notice Create a new YieldVault wrapping a ForgeVault tranche
    function createYieldVault(
        address forgeVault,
        uint8 trancheId,
        string calldata name,
        string calldata symbol,
        uint256 compoundInterval
    ) external returns (address yieldVaultAddress) {
        require(forgeVault != address(0), "YieldVaultFactory: zero vault");
        require(trancheId < 3, "YieldVaultFactory: invalid tranche");
        require(
            vaultByForgeAndTranche[forgeVault][trancheId] == address(0),
            "YieldVaultFactory: already exists"
        );

        uint256 vaultId = vaultCount++;

        YieldVault yv = new YieldVault(forgeVault, trancheId, name, symbol, compoundInterval, pauseAdmin);
        yieldVaultAddress = address(yv);

        vaults[vaultId] = yieldVaultAddress;
        vaultByForgeAndTranche[forgeVault][trancheId] = yieldVaultAddress;

        emit YieldVaultCreated(vaultId, yieldVaultAddress, forgeVault, trancheId, name, symbol);
    }

    function setPauseAdmin(address pauseAdmin_) external {
        require(msg.sender == owner, "YieldVaultFactory: not owner");
        require(pauseAdmin_ != address(0), "YieldVaultFactory: zero pause admin");
        pauseAdmin = pauseAdmin_;
    }

    function getYieldVault(address forgeVault, uint8 trancheId) external view returns (address) {
        return vaultByForgeAndTranche[forgeVault][trancheId];
    }

    function getVault(uint256 vaultId) external view returns (address) {
        return vaults[vaultId];
    }

    // --- Ownership Transfer (Two-Step) ---

    address public pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "YieldVaultFactory: not owner");
        require(newOwner != address(0), "YieldVaultFactory: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "YieldVaultFactory: not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
}
