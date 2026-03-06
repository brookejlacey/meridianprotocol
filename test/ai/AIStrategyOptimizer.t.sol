// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {AIStrategyOptimizer} from "../../src/ai/AIStrategyOptimizer.sol";
import {IAIStrategyOptimizer} from "../../src/interfaces/IAIStrategyOptimizer.sol";
import {StrategyRouter} from "../../src/yield/StrategyRouter.sol";

contract AIStrategyOptimizerTest is Test {
    uint256 constant WEEK = 7 days;

    StrategyRouter router;
    AIStrategyOptimizer optimizer;

    address gov = makeAddr("governance");
    address aiAgent = makeAddr("aiAgent");
    address alice = makeAddr("alice");
    address vault1 = makeAddr("vault1");
    address vault2 = makeAddr("vault2");

    function setUp() public {
        // Deploy router with optimizer as governance
        // First deploy optimizer, then transfer router governance to it
        router = new StrategyRouter(gov);
        optimizer = new AIStrategyOptimizer(address(router), gov, WEEK, 5000);

        // Gov authorizes AI agent
        vm.startPrank(gov);
        optimizer.setAIAgent(aiAgent, true);
        // Transfer router governance to optimizer so it can createStrategy
        router.transferGovernance(address(optimizer));
        vm.stopPrank();
        vm.prank(address(optimizer));
        router.acceptGovernance();
    }

    function _defaultParams() internal view returns (IAIStrategyOptimizer.ProposalParams memory) {
        address[] memory vaults = new address[](2);
        vaults[0] = vault1;
        vaults[1] = vault2;
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 6000;
        allocs[1] = 4000;

        return IAIStrategyOptimizer.ProposalParams({
            name: "Balanced AI",
            vaults: vaults,
            allocations: allocs,
            confidenceScore: 8000,
            expectedApyBps: 1200,
            riskScore: 3000,
            modelHash: bytes32("model-v1"),
            rationale: "Optimized for risk-adjusted return"
        });
    }

    // --- Constructor ---

    function test_constructor() public view {
        assertEq(address(optimizer.STRATEGY_ROUTER()), address(router));
        assertEq(optimizer.governance(), gov);
        assertEq(optimizer.proposalExpiry(), WEEK);
        assertEq(optimizer.minConfidence(), 5000);
    }

    // --- Propose ---

    function test_proposeStrategy_basic() public {
        vm.prank(aiAgent);
        uint256 id = optimizer.proposeStrategy(_defaultParams());

        IAIStrategyOptimizer.StrategyProposal memory p = optimizer.getProposal(id);
        assertEq(p.confidenceScore, 8000);
        assertEq(p.expectedApyBps, 1200);
        assertEq(uint8(p.status), uint8(IAIStrategyOptimizer.ProposalStatus.Pending));
        assertEq(p.proposer, aiAgent);
    }

    function test_proposeStrategy_revert_notAgent() public {
        vm.prank(alice);
        vm.expectRevert("AIStrategyOptimizer: not AI agent");
        optimizer.proposeStrategy(_defaultParams());
    }

    function test_proposeStrategy_revert_lowConfidence() public {
        IAIStrategyOptimizer.ProposalParams memory params = _defaultParams();
        params.confidenceScore = 4000; // Below 5000 min

        vm.prank(aiAgent);
        vm.expectRevert("AIStrategyOptimizer: low confidence");
        optimizer.proposeStrategy(params);
    }

    function test_proposeStrategy_revert_allocSumNot10000() public {
        address[] memory vaults = new address[](2);
        vaults[0] = vault1;
        vaults[1] = vault2;
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 5000;
        allocs[1] = 3000; // Sum = 8000, not 10000

        IAIStrategyOptimizer.ProposalParams memory params = IAIStrategyOptimizer.ProposalParams({
            name: "Bad",
            vaults: vaults,
            allocations: allocs,
            confidenceScore: 8000,
            expectedApyBps: 1000,
            riskScore: 2000,
            modelHash: bytes32("v1"),
            rationale: "test"
        });

        vm.prank(aiAgent);
        vm.expectRevert("AIStrategyOptimizer: must sum to 10000");
        optimizer.proposeStrategy(params);
    }

    // --- Approve + Execute Lifecycle ---

    function test_approveAndExecute() public {
        vm.prank(aiAgent);
        uint256 proposalId = optimizer.proposeStrategy(_defaultParams());

        vm.prank(gov);
        optimizer.approveProposal(proposalId);

        IAIStrategyOptimizer.StrategyProposal memory p = optimizer.getProposal(proposalId);
        assertEq(uint8(p.status), uint8(IAIStrategyOptimizer.ProposalStatus.Approved));

        vm.prank(gov);
        uint256 stratId = optimizer.executeProposal(proposalId);

        p = optimizer.getProposal(proposalId);
        assertEq(uint8(p.status), uint8(IAIStrategyOptimizer.ProposalStatus.Executed));

        // Verify strategy was created in router
        (string memory name,,, bool active) = router.getStrategy(stratId);
        assertEq(name, "Balanced AI");
        assertTrue(active);
    }

    function test_rejectProposal() public {
        vm.prank(aiAgent);
        uint256 id = optimizer.proposeStrategy(_defaultParams());

        vm.prank(gov);
        optimizer.rejectProposal(id);

        IAIStrategyOptimizer.StrategyProposal memory p = optimizer.getProposal(id);
        assertEq(uint8(p.status), uint8(IAIStrategyOptimizer.ProposalStatus.Rejected));
    }

    function test_executeProposal_revert_notApproved() public {
        vm.prank(aiAgent);
        uint256 id = optimizer.proposeStrategy(_defaultParams());

        vm.prank(gov);
        vm.expectRevert("AIStrategyOptimizer: not approved");
        optimizer.executeProposal(id);
    }

    // --- Expiry ---

    function test_proposalExpiry() public {
        vm.prank(aiAgent);
        uint256 id = optimizer.proposeStrategy(_defaultParams());

        vm.warp(block.timestamp + WEEK + 1);

        vm.prank(gov);
        vm.expectRevert("AIStrategyOptimizer: expired");
        optimizer.approveProposal(id);
    }

    // --- Rebalance Recommendation ---

    function test_recommendRebalance() public {
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 7000;
        allocs[1] = 3000;

        vm.prank(aiAgent);
        uint256 recId = optimizer.recommendRebalance(0, allocs, 7500, "Shift to safer assets");

        IAIStrategyOptimizer.RebalanceRecommendation memory rec = optimizer.getRecommendation(recId);
        assertEq(rec.strategyId, 0);
        assertEq(rec.confidenceScore, 7500);
    }

    // --- Pending Proposals ---

    function test_getPendingProposals() public {
        vm.startPrank(aiAgent);
        optimizer.proposeStrategy(_defaultParams());
        optimizer.proposeStrategy(_defaultParams());
        vm.stopPrank();

        uint256[] memory pending = optimizer.getPendingProposals();
        assertEq(pending.length, 2);

        // Reject first
        vm.prank(gov);
        optimizer.rejectProposal(0);

        pending = optimizer.getPendingProposals();
        assertEq(pending.length, 1);
        assertEq(pending[0], 1);
    }

    // --- Governance Transfer ---

    function test_governanceTransfer_twoStep() public {
        vm.prank(gov);
        optimizer.transferGovernance(alice);
        assertEq(optimizer.governance(), gov);

        vm.prank(alice);
        optimizer.acceptGovernance();
        assertEq(optimizer.governance(), alice);
    }

    function test_governanceTransfer_revert_notGov() public {
        vm.prank(alice);
        vm.expectRevert("AIStrategyOptimizer: not governance");
        optimizer.transferGovernance(alice);
    }

    // --- Fuzz ---

    function testFuzz_proposeStrategy(uint256 confScore, uint256 apyBps) public {
        confScore = bound(confScore, 5000, 10_000);
        apyBps = bound(apyBps, 0, 50_000);

        IAIStrategyOptimizer.ProposalParams memory params = _defaultParams();
        params.confidenceScore = confScore;
        params.expectedApyBps = apyBps;

        vm.prank(aiAgent);
        uint256 id = optimizer.proposeStrategy(params);

        IAIStrategyOptimizer.StrategyProposal memory p = optimizer.getProposal(id);
        assertEq(p.confidenceScore, confScore);
        assertEq(p.expectedApyBps, apyBps);
    }
}
