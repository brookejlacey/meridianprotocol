// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAIRiskOracle} from "../interfaces/IAIRiskOracle.sol";

/// @title AIRiskOracle
/// @notice On-chain oracle storing AI-generated credit risk scores per reference asset.
/// @dev Off-chain AI models compute risk scores and authorized updaters push them on-chain.
///      Integrates with ShieldPricer to provide dynamic credit risk pricing.
///
///      Safety features:
///      - Circuit breaker: caps single-update PD changes to prevent manipulation
///      - Staleness: scores expire after maxScoreAge — stale scores revert
///      - Updater whitelist: only authorized AI backends can push scores
///      - Two-step ownership transfer
contract AIRiskOracle is IAIRiskOracle {
    // --- State ---
    mapping(address asset => RiskScore) private _riskScores;
    mapping(address asset => RiskScore[]) private _scoreHistory;
    mapping(address => bool) public isUpdater;

    uint256 public maxScoreAge;     // Staleness threshold (seconds)
    uint256 public maxScoreChange;  // Max single-update PD delta (WAD)

    address public owner;
    address public pendingOwner;

    // --- Events (admin) ---
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "AIRiskOracle: not owner");
        _;
    }

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "AIRiskOracle: not updater");
        _;
    }

    constructor(uint256 maxScoreAge_, uint256 maxScoreChange_) {
        require(maxScoreAge_ > 0, "AIRiskOracle: zero max age");
        require(maxScoreChange_ > 0, "AIRiskOracle: zero max change");
        owner = msg.sender;
        maxScoreAge = maxScoreAge_;
        maxScoreChange = maxScoreChange_;
    }

    // --- Core ---

    /// @notice Update risk score for an asset
    function updateRiskScore(
        address asset,
        uint256 creditScore,
        uint256 defaultProbability,
        RiskTier tier,
        bytes32 modelHash
    ) external override onlyUpdater {
        _updateScore(asset, creditScore, defaultProbability, tier, modelHash);
    }

    /// @notice Batch update risk scores
    function batchUpdateRiskScores(
        address[] calldata assets,
        uint256[] calldata creditScores,
        uint256[] calldata defaultProbabilities,
        RiskTier[] calldata tiers,
        bytes32 modelHash
    ) external override onlyUpdater {
        require(
            assets.length == creditScores.length &&
            assets.length == defaultProbabilities.length &&
            assets.length == tiers.length,
            "AIRiskOracle: length mismatch"
        );

        for (uint256 i = 0; i < assets.length;) {
            _updateScore(assets[i], creditScores[i], defaultProbabilities[i], tiers[i], modelHash);
            unchecked { ++i; }
        }
    }

    // --- Views ---

    /// @notice Get full risk score for an asset
    function getRiskScore(address asset) external view override returns (RiskScore memory) {
        return _riskScores[asset];
    }

    /// @notice Get default probability, reverts if stale
    function getDefaultProbability(address asset) external view override returns (uint256) {
        RiskScore memory score = _riskScores[asset];
        require(score.timestamp > 0, "AIRiskOracle: no score");
        require(
            block.timestamp <= score.timestamp + maxScoreAge,
            "AIRiskOracle: stale score"
        );
        return score.defaultProbability;
    }

    /// @notice Check if score is fresh
    function isFresh(address asset) external view override returns (bool) {
        RiskScore memory score = _riskScores[asset];
        if (score.timestamp == 0) return false;
        return block.timestamp <= score.timestamp + maxScoreAge;
    }

    /// @notice Get full score history for an asset
    function getScoreHistory(address asset) external view override returns (RiskScore[] memory) {
        return _scoreHistory[asset];
    }

    // --- Admin ---

    function setUpdater(address updater, bool authorized) external onlyOwner {
        require(updater != address(0), "AIRiskOracle: zero address");
        isUpdater[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    function setMaxScoreAge(uint256 maxAge_) external onlyOwner {
        require(maxAge_ > 0, "AIRiskOracle: zero max age");
        maxScoreAge = maxAge_;
        emit MaxScoreAgeUpdated(maxAge_);
    }

    function setMaxScoreChange(uint256 maxChange_) external onlyOwner {
        require(maxChange_ > 0, "AIRiskOracle: zero max change");
        maxScoreChange = maxChange_;
        emit MaxScoreChangeUpdated(maxChange_);
    }

    // --- Ownership (Two-Step) ---

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AIRiskOracle: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "AIRiskOracle: not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // --- Internal ---

    function _updateScore(
        address asset,
        uint256 creditScore,
        uint256 defaultProbability,
        RiskTier tier,
        bytes32 modelHash
    ) internal {
        require(asset != address(0), "AIRiskOracle: zero asset");
        require(creditScore <= 1000, "AIRiskOracle: credit score > 1000");
        require(defaultProbability <= 1e18, "AIRiskOracle: PD > WAD");

        // Circuit breaker: check PD delta
        RiskScore memory existing = _riskScores[asset];
        if (existing.timestamp > 0) {
            uint256 delta = defaultProbability > existing.defaultProbability
                ? defaultProbability - existing.defaultProbability
                : existing.defaultProbability - defaultProbability;

            if (delta > maxScoreChange) {
                emit CircuitBreakerTripped(asset, existing.defaultProbability, defaultProbability, maxScoreChange);
                revert("AIRiskOracle: circuit breaker");
            }
        }

        RiskScore memory score = RiskScore({
            creditScore: creditScore,
            defaultProbability: defaultProbability,
            tier: tier,
            timestamp: block.timestamp,
            reporter: msg.sender,
            modelHash: modelHash
        });

        _riskScores[asset] = score;
        _scoreHistory[asset].push(score);

        emit RiskScoreUpdated(asset, creditScore, defaultProbability, tier, modelHash);
    }
}
