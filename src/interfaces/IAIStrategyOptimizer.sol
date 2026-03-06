// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IAIStrategyOptimizer {
    enum ProposalStatus { Pending, Approved, Rejected, Executed, Expired }

    struct ProposalParams {
        string name;
        address[] vaults;
        uint256[] allocations;       // BPS, sums to 10_000
        uint256 confidenceScore;     // 0-10_000 BPS
        uint256 expectedApyBps;
        uint256 riskScore;           // 0-10_000 BPS (higher = riskier)
        bytes32 modelHash;
        string rationale;
    }

    struct StrategyProposal {
        string name;
        address[] vaults;
        uint256[] allocations;       // BPS, sums to 10_000
        uint256 confidenceScore;     // 0-10_000 BPS
        uint256 expectedApyBps;
        uint256 riskScore;           // 0-10_000 BPS (higher = riskier)
        bytes32 modelHash;
        string rationale;
        uint256 proposedAt;
        uint256 expiresAt;
        ProposalStatus status;
        address proposer;
    }

    struct RebalanceRecommendation {
        uint256 strategyId;
        uint256[] newAllocations;
        uint256 confidenceScore;
        string rationale;
        uint256 timestamp;
    }

    event StrategyProposed(uint256 indexed proposalId, string name, uint256 confidenceScore, address proposer);
    event ProposalApproved(uint256 indexed proposalId);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId, uint256 strategyId);
    event ProposalExpired(uint256 indexed proposalId);
    event RebalanceRecommended(uint256 indexed recommendationId, uint256 strategyId, uint256 confidenceScore);
    event AIAgentUpdated(address indexed agent, bool authorized);

    function proposeStrategy(ProposalParams calldata params) external returns (uint256 proposalId);

    function recommendRebalance(
        uint256 strategyId,
        uint256[] calldata newAllocations,
        uint256 confidenceScore,
        string calldata rationale
    ) external returns (uint256 recommendationId);

    function approveProposal(uint256 proposalId) external;
    function rejectProposal(uint256 proposalId) external;
    function executeProposal(uint256 proposalId) external returns (uint256 strategyId);

    function getProposal(uint256 proposalId) external view returns (StrategyProposal memory);
    function getRecommendation(uint256 recId) external view returns (RebalanceRecommendation memory);
    function getPendingProposals() external view returns (uint256[] memory);
}
