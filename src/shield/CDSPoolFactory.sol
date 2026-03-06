// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {CDSPool} from "./CDSPool.sol";
import {ICDSPool} from "../interfaces/ICDSPool.sol";

/// @title CDSPoolFactory
/// @notice Creates and registers CDSPool AMM instances.
/// @dev Tracks pools by ID, reference asset, and creator.
///      Owner can authorize pool settlements (recovery rate from oracle/governance).
///      Protocol fee configuration is set at factory level and passed to new pools.
contract CDSPoolFactory is Ownable2Step {
    // --- State ---
    uint256 public poolCount;
    mapping(uint256 id => address pool) public pools;
    mapping(address referenceAsset => uint256[] poolIds) public poolsByReferenceAsset;
    mapping(address creator => uint256[] poolIds) public poolsByCreator;
    mapping(address => bool) public settleAuthorized;

    // --- Protocol Fee Config ---
    address public treasury;
    address public protocolAdmin;
    uint256 public defaultProtocolFeeBps;

    // --- Events ---
    event PoolCreated(
        uint256 indexed poolId,
        address indexed pool,
        address indexed referenceAsset,
        address creator,
        uint256 baseSpreadWad,
        uint256 slopeWad,
        uint256 maturity
    );

    // --- Structs ---
    struct CreatePoolParams {
        address referenceAsset;     // ForgeVault being insured
        address collateralToken;    // Token for collateral/premiums
        address oracle;             // CreditEventOracle address
        uint256 maturity;           // Pool expiry timestamp
        uint256 baseSpreadWad;      // Base annual spread (WAD)
        uint256 slopeWad;           // Bonding curve slope (WAD)
    }

    constructor(
        address treasury_,
        address protocolAdmin_,
        uint256 defaultProtocolFeeBps_
    ) Ownable(msg.sender) {
        require(treasury_ != address(0), "CDSPoolFactory: zero treasury");
        require(protocolAdmin_ != address(0), "CDSPoolFactory: zero protocol admin");
        require(defaultProtocolFeeBps_ <= 5000, "CDSPoolFactory: fee exceeds max");

        treasury = treasury_;
        protocolAdmin = protocolAdmin_;
        defaultProtocolFeeBps = defaultProtocolFeeBps_;
    }

    /// @notice Authorize an address to settle pools (e.g., LiquidationBot)
    function authorizeSettler(address settler, bool authorized) external onlyOwner {
        settleAuthorized[settler] = authorized;
    }

    /// @notice Settle a pool after credit event (only owner or authorized settlers)
    /// @param poolId Pool to settle
    /// @param recoveryRateWad Recovery rate in WAD (from oracle/governance decision)
    function settlePool(uint256 poolId, uint256 recoveryRateWad) external {
        require(msg.sender == owner() || settleAuthorized[msg.sender], "CDSPoolFactory: not authorized");
        address poolAddr = pools[poolId];
        require(poolAddr != address(0), "CDSPoolFactory: unknown pool");
        CDSPool(poolAddr).settle(recoveryRateWad);
    }

    /// @notice Create a new CDS AMM pool
    /// @param params Pool creation parameters
    /// @return poolAddress The deployed CDSPool address
    function createPool(CreatePoolParams calldata params) external returns (address poolAddress) {
        require(params.referenceAsset != address(0), "CDSPoolFactory: zero ref asset");
        require(params.collateralToken != address(0), "CDSPoolFactory: zero collateral");
        require(params.oracle != address(0), "CDSPoolFactory: zero oracle");
        require(params.maturity > block.timestamp, "CDSPoolFactory: maturity in past");
        require(params.maturity <= block.timestamp + 10 * 365 days, "CDSPoolFactory: maturity too far");
        require(params.baseSpreadWad > 0, "CDSPoolFactory: zero base spread");
        require(params.slopeWad > 0, "CDSPoolFactory: zero slope");

        uint256 poolId = poolCount++;

        ICDSPool.PoolTerms memory poolTerms = ICDSPool.PoolTerms({
            referenceAsset: params.referenceAsset,
            collateralToken: params.collateralToken,
            oracle: params.oracle,
            maturity: params.maturity,
            baseSpreadWad: params.baseSpreadWad,
            slopeWad: params.slopeWad
        });

        CDSPool pool = new CDSPool(
            poolTerms,
            address(this),
            treasury,
            protocolAdmin,
            defaultProtocolFeeBps
        );

        poolAddress = address(pool);
        pools[poolId] = poolAddress;
        poolsByReferenceAsset[params.referenceAsset].push(poolId);
        poolsByCreator[msg.sender].push(poolId);

        emit PoolCreated(
            poolId,
            poolAddress,
            params.referenceAsset,
            msg.sender,
            params.baseSpreadWad,
            params.slopeWad,
            params.maturity
        );
    }

    /// @notice Get all pool IDs referencing a specific vault
    function getPoolsForVault(address referenceAsset) external view returns (uint256[] memory) {
        return poolsByReferenceAsset[referenceAsset];
    }

    /// @notice Get all pool IDs created by a specific address
    function getCreatorPools(address creator) external view returns (uint256[] memory) {
        return poolsByCreator[creator];
    }

    /// @notice Get pool address by ID
    function getPool(uint256 poolId) external view returns (address) {
        return pools[poolId];
    }

    // --- Admin ---

    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "CDSPoolFactory: zero treasury");
        treasury = treasury_;
    }

    function setProtocolAdmin(address protocolAdmin_) external onlyOwner {
        require(protocolAdmin_ != address(0), "CDSPoolFactory: zero protocol admin");
        protocolAdmin = protocolAdmin_;
    }

    function setDefaultProtocolFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 5000, "CDSPoolFactory: fee exceeds max");
        defaultProtocolFeeBps = feeBps;
    }
}
