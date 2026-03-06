// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LPIncentiveGauge} from "../../src/yield/LPIncentiveGauge.sol";
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract LPIncentiveGaugeTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;
    uint256 constant WEEK = 7 days;

    MockYieldSource usdc;
    MockYieldSource rewardToken;
    CreditEventOracle oracle;
    CDSPool pool;
    LPIncentiveGauge gauge;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address gov = makeAddr("governance");
    address vault = makeAddr("vault");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        rewardToken = new MockYieldSource("REWARD", "RWD", 18);
        oracle = new CreditEventOracle();

        ICDSPool.PoolTerms memory terms = ICDSPool.PoolTerms({
            referenceAsset: vault,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        });

        pool = new CDSPool(terms, address(this), address(this), address(this), 0);
        gauge = new LPIncentiveGauge(address(pool), address(rewardToken), gov);

        // Fund actors
        usdc.mint(alice, 10_000_000e18);
        usdc.mint(bob, 10_000_000e18);
        rewardToken.mint(gov, 10_000_000e18);

        // Approvals for pool deposits
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);

        // Governance approves gauge to pull reward tokens
        vm.prank(gov);
        rewardToken.approve(address(gauge), type(uint256).max);
    }

    // --- Constructor ---

    function test_constructor_setsImmutables() public view {
        assertEq(address(gauge.POOL()), address(pool));
        assertEq(address(gauge.REWARD_TOKEN()), address(rewardToken));
        assertEq(gauge.governance(), gov);
    }

    function test_constructor_revert_zeroPool() public {
        vm.expectRevert("LPIncentiveGauge: zero pool");
        new LPIncentiveGauge(address(0), address(rewardToken), gov);
    }

    function test_constructor_revert_zeroReward() public {
        vm.expectRevert("LPIncentiveGauge: zero reward");
        new LPIncentiveGauge(address(pool), address(0), gov);
    }

    // --- NotifyRewardAmount ---

    function test_notify_basic() public {
        vm.prank(gov);
        gauge.notifyRewardAmount(1_000e18, WEEK);

        assertEq(gauge.rewardRate(), 1_000e18 / WEEK);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
    }

    function test_notify_extends_period() public {
        // First notification
        vm.prank(gov);
        gauge.notifyRewardAmount(1_000e18, WEEK);

        // Warp half way and add more
        vm.warp(block.timestamp + WEEK / 2);

        vm.prank(gov);
        gauge.notifyRewardAmount(500e18, WEEK);

        // Rate should include leftover from first period
        assertGt(gauge.rewardRate(), 500e18 / WEEK, "Rate includes leftover");
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
    }

    function test_notify_revert_notGovernance() public {
        vm.prank(alice);
        vm.expectRevert("LPIncentiveGauge: not governance");
        gauge.notifyRewardAmount(1_000e18, WEEK);
    }

    function test_notify_revert_zeroReward() public {
        vm.prank(gov);
        vm.expectRevert("LPIncentiveGauge: zero reward");
        gauge.notifyRewardAmount(0, WEEK);
    }

    function test_notify_revert_zeroDuration() public {
        vm.prank(gov);
        vm.expectRevert("LPIncentiveGauge: zero duration");
        gauge.notifyRewardAmount(1_000e18, 0);
    }

    // --- Rewards Accumulation ---

    function test_earned_singleLP() public {
        // Alice deposits into pool
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Start rewards
        vm.prank(gov);
        gauge.notifyRewardAmount(7_000e18, WEEK);

        // Checkpoint alice
        gauge.checkpoint(alice);

        // Warp 1 day — should earn 1/7th of rewards
        vm.warp(block.timestamp + 1 days);

        uint256 earned = gauge.earned(alice);
        assertApproxEqRel(earned, 1_000e18, 1e15, "Earned ~1000 after 1 day");
    }

    function test_earned_twoLPs_proportional() public {
        // Alice deposits 750k, Bob deposits 250k (3:1 ratio)
        vm.prank(alice);
        pool.deposit(750_000e18);
        vm.prank(bob);
        pool.deposit(250_000e18);

        // Start rewards
        vm.prank(gov);
        gauge.notifyRewardAmount(10_000e18, WEEK);

        // Checkpoint both
        gauge.checkpoint(alice);
        gauge.checkpoint(bob);

        // Warp full week
        vm.warp(block.timestamp + WEEK);

        uint256 aliceEarned = gauge.earned(alice);
        uint256 bobEarned = gauge.earned(bob);

        // Alice should get ~75%, Bob ~25%
        assertApproxEqRel(aliceEarned, 7_500e18, 1e15, "Alice gets 75%");
        assertApproxEqRel(bobEarned, 2_500e18, 1e15, "Bob gets 25%");
    }

    function test_earned_multipleCheckpoints() public {
        // Alice deposits
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        // Start rewards
        vm.prank(gov);
        gauge.notifyRewardAmount(7_000e18, WEEK);
        gauge.checkpoint(alice);

        // Warp half way — checkpoint to lock in earnings
        vm.warp(block.timestamp + WEEK / 2);
        gauge.checkpoint(alice);
        uint256 halfEarned = gauge.earned(alice);
        assertApproxEqRel(halfEarned, 3_500e18, 1e15, "Half period earnings");

        // Warp rest — should double
        vm.warp(block.timestamp + WEEK / 2);
        uint256 fullEarned = gauge.earned(alice);
        assertApproxEqRel(fullEarned, 7_000e18, 1e15, "Full period earnings");
    }

    // --- Claim ---

    function test_claim_transfersTokens() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(gov);
        gauge.notifyRewardAmount(7_000e18, WEEK);
        gauge.checkpoint(alice);

        vm.warp(block.timestamp + WEEK);

        uint256 balBefore = rewardToken.balanceOf(alice);
        vm.prank(alice);
        gauge.claimReward();
        uint256 received = rewardToken.balanceOf(alice) - balBefore;

        assertApproxEqRel(received, 7_000e18, 1e15, "Claimed full reward");
    }

    function test_claim_resetsEarned() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(gov);
        gauge.notifyRewardAmount(7_000e18, WEEK);
        gauge.checkpoint(alice);

        vm.warp(block.timestamp + WEEK);

        vm.prank(alice);
        gauge.claimReward();

        assertEq(gauge.earned(alice), 0, "Earned reset after claim");
    }

    function test_claim_nothingToClaimNoOp() public {
        uint256 balBefore = rewardToken.balanceOf(alice);
        vm.prank(alice);
        gauge.claimReward();
        assertEq(rewardToken.balanceOf(alice), balBefore, "No change");
    }

    // --- Edge Cases ---

    function test_zeroTotalShares_noRevert() public {
        // No deposits — rewardPerShare should return stored value
        vm.prank(gov);
        gauge.notifyRewardAmount(1_000e18, WEEK);

        vm.warp(block.timestamp + WEEK);

        uint256 rps = gauge.rewardPerShare();
        assertEq(rps, 0, "No shares = no accumulation");
    }

    function test_periodExpired_earningsStop() public {
        vm.prank(alice);
        pool.deposit(1_000_000e18);

        vm.prank(gov);
        gauge.notifyRewardAmount(7_000e18, WEEK);
        gauge.checkpoint(alice);

        // Warp way past end
        vm.warp(block.timestamp + WEEK * 3);

        uint256 earned = gauge.earned(alice);
        // Should cap at total reward
        assertApproxEqRel(earned, 7_000e18, 1e15, "Capped at period end");
    }

    // --- Governance ---

    function test_transferGovernance() public {
        vm.prank(gov);
        gauge.transferGovernance(alice);

        // Two-step: governance not changed yet
        assertEq(gauge.governance(), gov);
        assertEq(gauge.pendingGovernance(), alice);

        // Accept
        vm.prank(alice);
        gauge.acceptGovernance();
        assertEq(gauge.governance(), alice);
    }

    function test_transferGovernance_revert_notGov() public {
        vm.prank(alice);
        vm.expectRevert("LPIncentiveGauge: not governance");
        gauge.transferGovernance(bob);
    }

    // --- Fuzz ---

    function testFuzz_rewardDistribution_conservation(uint256 reward, uint256 aliceAmt, uint256 bobAmt) public {
        reward = bound(reward, 1e18, 1_000_000e18);
        aliceAmt = bound(aliceAmt, 1e18, 5_000_000e18);
        bobAmt = bound(bobAmt, 1e18, 5_000_000e18);

        vm.prank(alice);
        pool.deposit(aliceAmt);
        vm.prank(bob);
        pool.deposit(bobAmt);

        vm.prank(gov);
        gauge.notifyRewardAmount(reward, WEEK);
        gauge.checkpoint(alice);
        gauge.checkpoint(bob);

        vm.warp(block.timestamp + WEEK);

        uint256 aliceEarned = gauge.earned(alice);
        uint256 bobEarned = gauge.earned(bob);

        // Total earned should not exceed reward distributed
        assertLe(aliceEarned + bobEarned, reward + 1e15, "Conservation: no inflation");
        // Total should be close to full reward
        assertApproxEqRel(aliceEarned + bobEarned, reward, 1e15, "Conservation: distributed ~all");
    }
}
