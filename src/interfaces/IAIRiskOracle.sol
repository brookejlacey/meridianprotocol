// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IAIRiskOracle {
    enum RiskTier { AAA, AA, A, BBB, BB, B, CCC, Default }

    struct RiskScore {
        uint256 creditScore;        // 0-1000 (higher = safer)
        uint256 defaultProbability;  // WAD-scaled (e.g., 0.02e18 = 2% annual PD)
        RiskTier tier;
        uint256 timestamp;
        address reporter;
        bytes32 modelHash;
    }

    event RiskScoreUpdated(address indexed asset, uint256 creditScore, uint256 defaultProbability, RiskTier tier, bytes32 modelHash);
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event CircuitBreakerTripped(address indexed asset, uint256 oldPD, uint256 newPD, uint256 maxChange);
    event MaxScoreAgeUpdated(uint256 newMaxAge);
    event MaxScoreChangeUpdated(uint256 newMaxChange);

    function updateRiskScore(
        address asset,
        uint256 creditScore,
        uint256 defaultProbability,
        RiskTier tier,
        bytes32 modelHash
    ) external;

    function batchUpdateRiskScores(
        address[] calldata assets,
        uint256[] calldata creditScores,
        uint256[] calldata defaultProbabilities,
        RiskTier[] calldata tiers,
        bytes32 modelHash
    ) external;

    function getRiskScore(address asset) external view returns (RiskScore memory);
    function getDefaultProbability(address asset) external view returns (uint256);
    function isFresh(address asset) external view returns (bool);
    function getScoreHistory(address asset) external view returns (RiskScore[] memory);
}
