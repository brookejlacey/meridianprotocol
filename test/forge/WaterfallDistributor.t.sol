// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console2} from "@forge-std/Test.sol";
import {WaterfallDistributor} from "../../src/libraries/WaterfallDistributor.sol";
import {MeridianMath} from "../../src/libraries/MeridianMath.sol";

contract WaterfallDistributorTest is Test {
    using MeridianMath for uint256;

    uint256 constant BPS = 10_000;
    uint256 constant WAD = 1e18;

    // --- Helper: Build standard tranche config (70/20/10 split, 5%/8%/0% APR) ---
    function _standardTranches(uint256 poolSize)
        internal
        pure
        returns (WaterfallDistributor.TrancheState[3] memory t)
    {
        uint256 seniorDeposit = (poolSize * 70) / 100;
        uint256 mezzDeposit = (poolSize * 20) / 100;
        uint256 equityDeposit = poolSize - seniorDeposit - mezzDeposit;

        t[0] = WaterfallDistributor.TrancheState({
            targetApr: 500, // 5%
            totalShares: seniorDeposit,
            depositValue: seniorDeposit
        });
        t[1] = WaterfallDistributor.TrancheState({
            targetApr: 800, // 8%
            totalShares: mezzDeposit,
            depositValue: mezzDeposit
        });
        t[2] = WaterfallDistributor.TrancheState({
            targetApr: 0, // Equity has no target — gets remainder
            totalShares: equityDeposit,
            depositValue: equityDeposit
        });
    }

    // ===== YIELD DISTRIBUTION TESTS =====

    function test_distributeYield_seniorFirst() public pure {
        uint256 poolSize = 1_000_000e18;
        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(poolSize);

        // Full year distribution, yield = 50k (exactly covers senior coupon of 35k)
        uint256 totalYield = 50_000e18;
        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, BPS);

        // Senior coupon = 700k * 5% = 35k
        assertEq(result.amounts[0], 35_000e18, "Senior should get full coupon");
        // Mezz coupon = 200k * 8% = 16k, but only 15k remains
        assertEq(result.amounts[1], 15_000e18, "Mezz should get remaining 15k");
        // Equity gets nothing
        assertEq(result.amounts[2], 0, "Equity gets nothing when yield is scarce");
        assertEq(result.totalDistributed, totalYield, "Total should equal input");
    }

    function test_distributeYield_excessToEquity() public pure {
        uint256 poolSize = 1_000_000e18;
        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(poolSize);

        // Full year, yield = 100k (senior needs 35k, mezz needs 16k, 49k excess)
        uint256 totalYield = 100_000e18;
        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, BPS);

        assertEq(result.amounts[0], 35_000e18, "Senior coupon");
        assertEq(result.amounts[1], 16_000e18, "Mezz coupon");
        assertEq(result.amounts[2], 49_000e18, "Equity gets excess spread");
    }

    function test_distributeYield_zeroYield() public pure {
        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(1_000_000e18);

        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(0, t, BPS);

        assertEq(result.amounts[0], 0);
        assertEq(result.amounts[1], 0);
        assertEq(result.amounts[2], 0);
        assertEq(result.totalDistributed, 0);
    }

    function test_distributeYield_weeklyPeriod() public pure {
        uint256 poolSize = 1_000_000e18;
        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(poolSize);

        // Weekly: ~1/52 of a year ≈ 192 bps
        uint256 weeklyBps = 192;
        uint256 totalYield = 2_000e18; // plenty for weekly obligations

        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, weeklyBps);

        // Senior weekly coupon ≈ 700k * 500/10000 * 192/10000 ≈ 672
        uint256 expectedSenior = (700_000e18 * 500 * 192) / (BPS * BPS);
        assertEq(result.amounts[0], expectedSenior, "Senior weekly coupon");

        // Mezz weekly coupon ≈ 200k * 800/10000 * 192/10000 ≈ 307.2
        uint256 expectedMezz = (200_000e18 * 800 * 192) / (BPS * BPS);
        assertEq(result.amounts[1], expectedMezz, "Mezz weekly coupon");

        // Rest goes to equity
        assertEq(result.amounts[2], totalYield - expectedSenior - expectedMezz);
    }

    function test_distributeYield_onlySeniorPartiallyFunded() public pure {
        uint256 poolSize = 1_000_000e18;
        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(poolSize);

        // Yield only covers half of senior obligation
        uint256 totalYield = 17_500e18; // half of 35k senior coupon
        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, BPS);

        assertEq(result.amounts[0], 17_500e18, "Senior gets what's available");
        assertEq(result.amounts[1], 0, "Mezz gets nothing");
        assertEq(result.amounts[2], 0, "Equity gets nothing");
    }

    function test_distributeYield_noShares() public pure {
        WaterfallDistributor.TrancheState[3] memory t;
        // All tranches have 0 shares
        t[0] = WaterfallDistributor.TrancheState({targetApr: 500, totalShares: 0, depositValue: 0});
        t[1] = WaterfallDistributor.TrancheState({targetApr: 800, totalShares: 0, depositValue: 0});
        t[2] = WaterfallDistributor.TrancheState({targetApr: 0, totalShares: 0, depositValue: 0});

        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(1_000e18, t, BPS);

        // No obligations → all goes to equity (index 2)
        assertEq(result.amounts[0], 0, "No senior obligation when no deposits");
        assertEq(result.amounts[1], 0, "No mezz obligation when no deposits");
        assertEq(result.amounts[2], 1_000e18, "Equity gets everything");
    }

    // ===== LOSS ABSORPTION TESTS =====

    function test_allocateLoss_equityAbsorbsFirst() public pure {
        uint256[3] memory values = [uint256(700_000e18), 200_000e18, 100_000e18];

        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(50_000e18, values);

        assertEq(result.losses[2], 50_000e18, "Equity absorbs all");
        assertEq(result.losses[1], 0, "Mezz untouched");
        assertEq(result.losses[0], 0, "Senior untouched");
        assertEq(result.totalAbsorbed, 50_000e18);
    }

    function test_allocateLoss_wipesEquityIntoMezz() public pure {
        uint256[3] memory values = [uint256(700_000e18), 200_000e18, 100_000e18];

        // 150k loss: equity absorbs 100k, mezz absorbs 50k
        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(150_000e18, values);

        assertEq(result.losses[2], 100_000e18, "Equity fully wiped");
        assertEq(result.losses[1], 50_000e18, "Mezz absorbs remainder");
        assertEq(result.losses[0], 0, "Senior untouched");
    }

    function test_allocateLoss_totalDefault() public pure {
        uint256[3] memory values = [uint256(700_000e18), 200_000e18, 100_000e18];

        // Total loss = entire pool
        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(1_000_000e18, values);

        assertEq(result.losses[2], 100_000e18, "Equity fully wiped");
        assertEq(result.losses[1], 200_000e18, "Mezz fully wiped");
        assertEq(result.losses[0], 700_000e18, "Senior fully wiped");
        assertEq(result.totalAbsorbed, 1_000_000e18);
    }

    function test_allocateLoss_exceedsPoolValue() public pure {
        uint256[3] memory values = [uint256(700_000e18), 200_000e18, 100_000e18];

        // Loss exceeds total pool (bad debt beyond pool size)
        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(1_500_000e18, values);

        // Can only absorb up to pool value
        assertEq(result.totalAbsorbed, 1_000_000e18, "Can only absorb pool value");
    }

    function test_allocateLoss_zero() public pure {
        uint256[3] memory values = [uint256(700_000e18), 200_000e18, 100_000e18];

        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(0, values);

        assertEq(result.losses[0], 0);
        assertEq(result.losses[1], 0);
        assertEq(result.losses[2], 0);
        assertEq(result.totalAbsorbed, 0);
    }

    // ===== YIELD-PER-SHARE TESTS =====

    function test_calculateYieldPerShareDelta_basic() public pure {
        uint256 delta = WaterfallDistributor.calculateYieldPerShareDelta(1_000e18, 10_000e18);
        // 1000/10000 = 0.1 WAD
        assertEq(delta, 0.1e18);
    }

    function test_calculateYieldPerShareDelta_zeroShares() public pure {
        uint256 delta = WaterfallDistributor.calculateYieldPerShareDelta(1_000e18, 0);
        assertEq(delta, 0, "Zero shares = zero delta");
    }

    function test_calculateUserYield_basic() public pure {
        uint256 owed = WaterfallDistributor.calculateUserYield(
            100e18, // shares
            0.5e18, // current yieldPerShare
            0.1e18  // last checkpoint
        );
        // 100 * (0.5 - 0.1) = 40
        assertEq(owed, 40e18);
    }

    function test_calculateUserYield_noNewYield() public pure {
        uint256 owed = WaterfallDistributor.calculateUserYield(100e18, 0.5e18, 0.5e18);
        assertEq(owed, 0, "No yield when checkpoint is current");
    }

    function test_calculateUserYield_checkpointBeyondCurrent() public pure {
        // Edge case: checkpoint > current (shouldn't happen, but should return 0)
        uint256 owed = WaterfallDistributor.calculateUserYield(100e18, 0.3e18, 0.5e18);
        assertEq(owed, 0, "Returns 0 if checkpoint beyond current");
    }

    // ===== FUZZ TESTS =====

    function testFuzz_distributeYield_sumEqualsInput(
        uint256 totalYield,
        uint256 seniorDeposit,
        uint256 mezzDeposit,
        uint256 equityDeposit,
        uint16 seniorApr,
        uint16 mezzApr,
        uint16 periodBps
    ) public pure {
        // Bound inputs to reasonable ranges
        totalYield = bound(totalYield, 0, 1e30);
        seniorDeposit = bound(seniorDeposit, 0, 1e30);
        mezzDeposit = bound(mezzDeposit, 0, 1e30);
        equityDeposit = bound(equityDeposit, 0, 1e30);
        seniorApr = uint16(bound(seniorApr, 0, 5000)); // max 50%
        mezzApr = uint16(bound(mezzApr, 0, 5000));
        periodBps = uint16(bound(periodBps, 1, 10000)); // 1 bps to 1 year

        WaterfallDistributor.TrancheState[3] memory t;
        t[0] = WaterfallDistributor.TrancheState({
            targetApr: seniorApr,
            totalShares: seniorDeposit,
            depositValue: seniorDeposit
        });
        t[1] = WaterfallDistributor.TrancheState({
            targetApr: mezzApr,
            totalShares: mezzDeposit,
            depositValue: mezzDeposit
        });
        t[2] = WaterfallDistributor.TrancheState({
            targetApr: 0,
            totalShares: equityDeposit,
            depositValue: equityDeposit
        });

        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, periodBps);

        // Invariant: sum of distributions == totalYield
        uint256 sum = result.amounts[0] + result.amounts[1] + result.amounts[2];
        assertEq(sum, totalYield, "Distribution sum must equal total yield");
    }

    function testFuzz_distributeYield_seniorPriority(
        uint256 totalYield,
        uint256 poolSize
    ) public pure {
        totalYield = bound(totalYield, 1, 1e30);
        poolSize = bound(poolSize, 1e18, 1e30);

        WaterfallDistributor.TrancheState[3] memory t = _standardTranches(poolSize);

        WaterfallDistributor.DistributionResult memory result =
            WaterfallDistributor.distributeYield(totalYield, t, BPS);

        // Invariant: if senior doesn't get full coupon, no lower tranche gets anything
        uint256 seniorOwed = (t[0].depositValue * t[0].targetApr) / BPS;
        if (result.amounts[0] < seniorOwed) {
            assertEq(result.amounts[1], 0, "Mezz should be 0 if senior underfunded");
            assertEq(result.amounts[2], 0, "Equity should be 0 if senior underfunded");
        }
    }

    function testFuzz_allocateLoss_sumEqualsAbsorbed(
        uint256 totalLoss,
        uint256 seniorValue,
        uint256 mezzValue,
        uint256 equityValue
    ) public pure {
        totalLoss = bound(totalLoss, 0, 1e30);
        seniorValue = bound(seniorValue, 0, 1e30);
        mezzValue = bound(mezzValue, 0, 1e30);
        equityValue = bound(equityValue, 0, 1e30);

        uint256[3] memory values = [seniorValue, mezzValue, equityValue];

        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(totalLoss, values);

        // Invariant: sum of losses == totalAbsorbed
        uint256 sum = result.losses[0] + result.losses[1] + result.losses[2];
        assertEq(sum, result.totalAbsorbed, "Loss sum must equal totalAbsorbed");

        // Invariant: totalAbsorbed <= totalLoss
        assertLe(result.totalAbsorbed, totalLoss, "Cannot absorb more than loss");

        // Invariant: totalAbsorbed <= sum of tranche values
        uint256 totalValue = seniorValue + mezzValue + equityValue;
        assertLe(result.totalAbsorbed, totalValue, "Cannot absorb more than pool value");

        // Invariant: each tranche loss <= tranche value
        assertLe(result.losses[0], seniorValue, "Senior loss <= senior value");
        assertLe(result.losses[1], mezzValue, "Mezz loss <= mezz value");
        assertLe(result.losses[2], equityValue, "Equity loss <= equity value");
    }

    function testFuzz_allocateLoss_equityFirst(
        uint256 totalLoss,
        uint256 seniorValue,
        uint256 mezzValue,
        uint256 equityValue
    ) public pure {
        totalLoss = bound(totalLoss, 1, 1e30);
        seniorValue = bound(seniorValue, 1e18, 1e30);
        mezzValue = bound(mezzValue, 1e18, 1e30);
        equityValue = bound(equityValue, 1e18, 1e30);

        uint256[3] memory values = [seniorValue, mezzValue, equityValue];

        WaterfallDistributor.LossResult memory result =
            WaterfallDistributor.allocateLoss(totalLoss, values);

        // Invariant: if equity is not fully wiped, mezz and senior take no loss
        if (result.losses[2] < equityValue) {
            assertEq(result.losses[1], 0, "Mezz should be 0 if equity not wiped");
            assertEq(result.losses[0], 0, "Senior should be 0 if equity not wiped");
        }
    }

    function testFuzz_yieldPerShare_roundTrip(
        uint256 distribution,
        uint256 totalShares,
        uint256 userShares
    ) public pure {
        // Use realistic token amounts (at least 1 token with 18 decimals)
        distribution = bound(distribution, 1e18, 1e30);
        totalShares = bound(totalShares, 1e18, 1e30);
        userShares = bound(userShares, 1e18, totalShares);

        uint256 delta = WaterfallDistributor.calculateYieldPerShareDelta(distribution, totalShares);
        uint256 userOwed = WaterfallDistributor.calculateUserYield(userShares, delta, 0);

        // Invariant: user's owed amount should be proportional to their share
        // userOwed ≈ distribution * userShares / totalShares (with rounding)
        uint256 expected = (distribution * userShares) / totalShares;

        // Two sequential WAD operations (wadDiv then wadMul) introduce rounding.
        // Use relative tolerance of 0.001% (1e13 out of 1e18) for realistic amounts.
        if (expected > 0) {
            assertApproxEqRel(userOwed, expected, 1e13, "User yield should be proportional");
        } else {
            assertEq(userOwed, 0, "Zero expected means zero owed");
        }
    }
}
