// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAIStrategyOptimizer} from "../interfaces/IAIStrategyOptimizer.sol";

/// @dev Minimal interface for StrategyRouter.createStrategy
interface IStrategyRouterMinimal {
    function createStrategy(
        string calldata name,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external returns (uint256 strategyId);
}

/// @title AIStrategyOptimizer
/// @notice AI-driven strategy proposals for the StrategyRouter.
/// @dev Off-chain AI computes optimal vault allocations and proposes them on-chain.
///      Governance must approve before execution. Wraps StrategyRouter without modifying it.
///
///      Flow: AI proposes → governance reviews → governance approves → governance executes
///      (which calls StrategyRouter.createStrategy)
///
///      Safety features:
///      - Governance gating: AI can only propose, never execute
///      - Minimum confidence threshold: low-confidence proposals rejected
///      - Auto-expiry: unacted proposals expire after proposalExpiry
///      - Two-step governance transfer
contract AIStrategyOptimizer is IAIStrategyOptimizer {
    // --- State ---
    IStrategyRouterMinimal public immutable STRATEGY_ROUTER;
    mapping(uint256 => StrategyProposal) private _proposals;
    uint256 public nextProposalId;
    mapping(uint256 => RebalanceRecommendation) private _recommendations;
    uint256 public nextRecommendationId;
    mapping(address => bool) public isAIAgent;
    uint256 public proposalExpiry;
    uint256 public minConfidence;

    address public governance;
    address public pendingGovernance;

    // --- Events (admin) ---
    event GovernanceTransferStarted(address indexed previousGov, address indexed newGov);
    event GovernanceTransferred(address indexed previousGov, address indexed newGov);
    event ProposalExpiryUpdated(uint256 newExpiry);
    event MinConfidenceUpdated(uint256 newMinConfidence);

    // --- Modifiers ---
    modifier onlyGovernance() {
        require(msg.sender == governance, "AIStrategyOptimizer: not governance");
        _;
    }

    modifier onlyAIAgent_() {
        require(isAIAgent[msg.sender], "AIStrategyOptimizer: not AI agent");
        _;
    }

    constructor(address strategyRouter_, address governance_, uint256 proposalExpiry_, uint256 minConfidence_) {
        require(strategyRouter_ != address(0), "AIStrategyOptimizer: zero router");
        require(governance_ != address(0), "AIStrategyOptimizer: zero governance");
        require(proposalExpiry_ > 0, "AIStrategyOptimizer: zero expiry");
        STRATEGY_ROUTER = IStrategyRouterMinimal(strategyRouter_);
        governance = governance_;
        proposalExpiry = proposalExpiry_;
        minConfidence = minConfidence_;
    }

    // --- AI Agent Functions ---

    /// @notice Propose a new strategy
    function proposeStrategy(
        ProposalParams calldata params
    ) external override onlyAIAgent_ returns (uint256 proposalId) {
        require(params.vaults.length == params.allocations.length, "AIStrategyOptimizer: length mismatch");
        require(params.vaults.length > 0 && params.vaults.length <= 3, "AIStrategyOptimizer: invalid vault count");
        require(params.confidenceScore >= minConfidence, "AIStrategyOptimizer: low confidence");
        require(params.confidenceScore <= 10_000, "AIStrategyOptimizer: confidence > 10000");
        require(params.riskScore <= 10_000, "AIStrategyOptimizer: risk > 10000");

        uint256 totalAlloc;
        for (uint256 i = 0; i < params.allocations.length;) {
            totalAlloc += params.allocations[i];
            unchecked { ++i; }
        }
        require(totalAlloc == 10_000, "AIStrategyOptimizer: must sum to 10000");

        proposalId = nextProposalId++;

        StrategyProposal storage p = _proposals[proposalId];
        p.name = params.name;
        p.vaults = params.vaults;
        p.allocations = params.allocations;
        p.confidenceScore = params.confidenceScore;
        p.expectedApyBps = params.expectedApyBps;
        p.riskScore = params.riskScore;
        p.modelHash = params.modelHash;
        p.rationale = params.rationale;
        p.proposedAt = block.timestamp;
        p.expiresAt = block.timestamp + proposalExpiry;
        p.status = ProposalStatus.Pending;
        p.proposer = msg.sender;

        emit StrategyProposed(proposalId, params.name, params.confidenceScore, msg.sender);
    }

    /// @notice Recommend rebalancing an existing strategy (advisory only)
    function recommendRebalance(
        uint256 strategyId,
        uint256[] calldata newAllocations,
        uint256 confidenceScore,
        string calldata rationale
    ) external override onlyAIAgent_ returns (uint256 recommendationId) {
        require(confidenceScore <= 10_000, "AIStrategyOptimizer: confidence > 10000");

        uint256 totalAlloc;
        for (uint256 i = 0; i < newAllocations.length;) {
            totalAlloc += newAllocations[i];
            unchecked { ++i; }
        }
        require(totalAlloc == 10_000, "AIStrategyOptimizer: must sum to 10000");

        recommendationId = nextRecommendationId++;

        RebalanceRecommendation storage r = _recommendations[recommendationId];
        r.strategyId = strategyId;
        r.newAllocations = newAllocations;
        r.confidenceScore = confidenceScore;
        r.rationale = rationale;
        r.timestamp = block.timestamp;

        emit RebalanceRecommended(recommendationId, strategyId, confidenceScore);
    }

    // --- Governance Functions ---

    /// @notice Approve a pending proposal
    function approveProposal(uint256 proposalId) external override onlyGovernance {
        StrategyProposal storage p = _proposals[proposalId];
        require(p.status == ProposalStatus.Pending, "AIStrategyOptimizer: not pending");
        require(block.timestamp < p.expiresAt, "AIStrategyOptimizer: expired");
        p.status = ProposalStatus.Approved;
        emit ProposalApproved(proposalId);
    }

    /// @notice Reject a pending proposal
    function rejectProposal(uint256 proposalId) external override onlyGovernance {
        StrategyProposal storage p = _proposals[proposalId];
        require(p.status == ProposalStatus.Pending, "AIStrategyOptimizer: not pending");
        p.status = ProposalStatus.Rejected;
        emit ProposalRejected(proposalId);
    }

    /// @notice Execute an approved proposal (calls StrategyRouter.createStrategy)
    function executeProposal(uint256 proposalId) external override onlyGovernance returns (uint256 strategyId) {
        StrategyProposal storage p = _proposals[proposalId];
        require(p.status == ProposalStatus.Approved, "AIStrategyOptimizer: not approved");
        require(block.timestamp < p.expiresAt, "AIStrategyOptimizer: expired");

        p.status = ProposalStatus.Executed;
        strategyId = STRATEGY_ROUTER.createStrategy(p.name, p.vaults, p.allocations);

        emit ProposalExecuted(proposalId, strategyId);
    }

    // --- Views ---

    function getProposal(uint256 proposalId) external view override returns (StrategyProposal memory) {
        return _proposals[proposalId];
    }

    function getRecommendation(uint256 recId) external view override returns (RebalanceRecommendation memory) {
        return _recommendations[recId];
    }

    function getPendingProposals() external view override returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < nextProposalId;) {
            if (_proposals[i].status == ProposalStatus.Pending && block.timestamp < _proposals[i].expiresAt) {
                count++;
            }
            unchecked { ++i; }
        }

        uint256[] memory pending = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < nextProposalId;) {
            if (_proposals[i].status == ProposalStatus.Pending && block.timestamp < _proposals[i].expiresAt) {
                pending[idx++] = i;
            }
            unchecked { ++i; }
        }
        return pending;
    }

    // --- Admin ---

    function setAIAgent(address agent, bool authorized) external onlyGovernance {
        require(agent != address(0), "AIStrategyOptimizer: zero address");
        isAIAgent[agent] = authorized;
        emit AIAgentUpdated(agent, authorized);
    }

    function setMinConfidence(uint256 minConf) external onlyGovernance {
        minConfidence = minConf;
        emit MinConfidenceUpdated(minConf);
    }

    function setProposalExpiry(uint256 expiry) external onlyGovernance {
        require(expiry > 0, "AIStrategyOptimizer: zero expiry");
        proposalExpiry = expiry;
        emit ProposalExpiryUpdated(expiry);
    }

    // --- Governance Transfer (Two-Step) ---

    function transferGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "AIStrategyOptimizer: zero address");
        pendingGovernance = newGov;
        emit GovernanceTransferStarted(governance, newGov);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "AIStrategyOptimizer: not pending governance");
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }
}
