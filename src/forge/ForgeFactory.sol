// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ForgeVault} from "./ForgeVault.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";

/// @title ForgeFactory
/// @notice Creates and registers ForgeVault instances.
/// @dev Tracks all vaults for discovery and aggregate metrics.
///      Protocol fee configuration is set at factory level and passed to new vaults.
contract ForgeFactory {
    // --- State ---
    uint256 public vaultCount;
    mapping(uint256 id => address vault) public vaults;
    mapping(address originator => uint256[] vaultIds) public vaultsByOriginator;

    // --- Protocol Fee Config ---
    address public owner;
    address public treasury;
    address public protocolAdmin;
    uint256 public defaultProtocolFeeBps;

    // --- Events ---
    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vault,
        address indexed originator,
        address underlyingAsset
    );

    // --- Structs ---
    struct CreateVaultParams {
        address underlyingAsset;
        address[3] trancheTokenAddresses;
        IForgeVault.TrancheParams[3] trancheParams;
        uint256 distributionInterval;
    }

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "ForgeFactory: not owner");
        _;
    }

    constructor(address treasury_, address protocolAdmin_, uint256 defaultProtocolFeeBps_) {
        require(treasury_ != address(0), "ForgeFactory: zero treasury");
        require(protocolAdmin_ != address(0), "ForgeFactory: zero protocol admin");
        require(defaultProtocolFeeBps_ <= 1000, "ForgeFactory: fee exceeds max");

        owner = msg.sender;
        treasury = treasury_;
        protocolAdmin = protocolAdmin_;
        defaultProtocolFeeBps = defaultProtocolFeeBps_;
    }

    /// @notice Create a new ForgeVault
    /// @param params Vault creation parameters
    /// @return vaultAddress The deployed vault address
    function createVault(CreateVaultParams calldata params) external returns (address vaultAddress) {
        // Validate tranche tokens are deployed contracts
        for (uint256 i = 0; i < 3; i++) {
            require(params.trancheTokenAddresses[i] != address(0), "ForgeFactory: zero token");
            require(params.trancheTokenAddresses[i].code.length > 0, "ForgeFactory: token not deployed");
        }
        require(params.underlyingAsset != address(0), "ForgeFactory: zero underlying");
        require(params.underlyingAsset.code.length > 0, "ForgeFactory: underlying not deployed");

        uint256 vaultId = vaultCount++;

        ForgeVault vault = new ForgeVault(
            msg.sender,
            params.underlyingAsset,
            params.trancheTokenAddresses,
            params.trancheParams,
            params.distributionInterval,
            treasury,
            protocolAdmin,
            defaultProtocolFeeBps
        );

        vaultAddress = address(vault);
        vaults[vaultId] = vaultAddress;
        vaultsByOriginator[msg.sender].push(vaultId);

        emit VaultCreated(vaultId, vaultAddress, msg.sender, params.underlyingAsset);
    }

    /// @notice Get all vault IDs for an originator
    function getOriginatorVaults(address originator_) external view returns (uint256[] memory) {
        return vaultsByOriginator[originator_];
    }

    /// @notice Get vault address by ID
    function getVault(uint256 vaultId) external view returns (address) {
        return vaults[vaultId];
    }

    // --- Admin ---

    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "ForgeFactory: zero treasury");
        treasury = treasury_;
    }

    function setProtocolAdmin(address protocolAdmin_) external onlyOwner {
        require(protocolAdmin_ != address(0), "ForgeFactory: zero protocol admin");
        protocolAdmin = protocolAdmin_;
    }

    function setDefaultProtocolFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 1000, "ForgeFactory: fee exceeds max");
        defaultProtocolFeeBps = feeBps;
    }

    // --- Ownership Transfer (Two-Step) ---

    address public pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ForgeFactory: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "ForgeFactory: not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
}
