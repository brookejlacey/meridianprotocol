// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {YieldVault} from "../../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../../src/yield/YieldVaultFactory.sol";
import {StrategyRouter} from "../../src/yield/StrategyRouter.sol";
import {LPIncentiveGauge} from "../../src/yield/LPIncentiveGauge.sol";
import {ForgeFactory} from "../../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../../src/forge/ForgeVault.sol";
import {TrancheToken} from "../../src/forge/TrancheToken.sol";
import {CDSPool} from "../../src/shield/CDSPool.sol";
import {ICDSPool} from "../../src/interfaces/ICDSPool.sol";
import {CreditEventOracle} from "../../src/shield/CreditEventOracle.sol";
import {IForgeVault} from "../../src/interfaces/IForgeVault.sol";
import {MockYieldSource} from "../../src/mocks/MockYieldSource.sol";

contract YieldIntegrationTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant WEEK = 7 days;
    uint256 constant DAY = 1 days;
    uint256 constant YEAR = 365 days;

    MockYieldSource usdc;
    MockYieldSource rewardToken;
    ForgeFactory forgeFactory;
    ForgeVault forgeVault;
    CreditEventOracle oracle;
    CDSPool pool;
    YieldVaultFactory yvFactory;
    StrategyRouter router;
    LPIncentiveGauge gauge;

    YieldVault yvSenior;
    YieldVault yvMezz;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address gov = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address protocolAdmin = makeAddr("protocolAdmin");

    function setUp() public {
        usdc = new MockYieldSource("USDC", "USDC", 18);
        rewardToken = new MockYieldSource("REWARD", "RWD", 18);

        // --- Forge setup ---
        forgeFactory = new ForgeFactory(treasury, protocolAdmin, 0);
        uint256 nonce = vm.getNonce(address(forgeFactory));
        address predicted = vm.computeCreateAddress(address(forgeFactory), nonce);

        TrancheToken sr = new TrancheToken("Senior", "SR", predicted, 0);
        TrancheToken mz = new TrancheToken("Mezzanine", "MZ", predicted, 1);
        TrancheToken eq = new TrancheToken("Equity", "EQ", predicted, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(sr)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mz)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(eq)});

        address fv = forgeFactory.createVault(ForgeFactory.CreateVaultParams({
            underlyingAsset: address(usdc),
            trancheTokenAddresses: [address(sr), address(mz), address(eq)],
            trancheParams: params,
            distributionInterval: WEEK
        }));
        forgeVault = ForgeVault(fv);

        // --- YieldVaults ---
        yvFactory = new YieldVaultFactory(address(this));
        yvSenior = YieldVault(yvFactory.createYieldVault(fv, 0, "acSR", "acSR", DAY));
        yvMezz = YieldVault(yvFactory.createYieldVault(fv, 1, "acMZ", "acMZ", DAY));

        // --- CDS Pool ---
        oracle = new CreditEventOracle();
        ICDSPool.PoolTerms memory terms = ICDSPool.PoolTerms({
            referenceAsset: fv,
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        });
        pool = new CDSPool(terms, address(this), address(this), address(this), 0);

        // --- Gauge ---
        gauge = new LPIncentiveGauge(address(pool), address(rewardToken), gov);

        // --- Strategy Router ---
        router = new StrategyRouter(gov);

        // --- Funding ---
        usdc.mint(alice, 100_000_000e18);
        usdc.mint(bob, 100_000_000e18);
        rewardToken.mint(gov, 10_000_000e18);

        vm.prank(alice);
        usdc.approve(address(yvSenior), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(gov);
        rewardToken.approve(address(gauge), type(uint256).max);
    }

    /// @dev E2E: deposit → yield → compound → withdraw with profit
    function test_e2e_yieldVaultCompound() public {
        // Alice deposits into Senior YieldVault
        vm.prank(alice);
        yvSenior.deposit(500_000e18, alice);

        // Inject yield into ForgeVault
        usdc.mint(address(forgeVault), 50_000e18);
        vm.warp(block.timestamp + WEEK);
        forgeVault.triggerWaterfall();

        // Compound
        vm.warp(block.timestamp + DAY);
        uint256 harvested = yvSenior.compound();
        assertGt(harvested, 0, "Yield harvested");

        // Share price should have appreciated
        // With _decimalsOffset()=3, shares are scaled by 10^3, so base share price
        // is ~1e15 (not 1e18). After compounding, it should exceed the base.
        (,,,uint256 sharePrice,) = yvSenior.getMetrics();
        assertGt(sharePrice, 1e15, "Share price > base (1e15 with decimalsOffset=3)");

        // Alice withdraws — should get more than deposited
        uint256 shares = yvSenior.balanceOf(alice);
        vm.prank(alice);
        uint256 withdrawn = yvSenior.redeem(shares, alice, alice);
        assertGt(withdrawn, 500_000e18, "Profit earned");
    }

    /// @dev E2E: strategy create → open position → rebalance → close
    function test_e2e_strategyRebalance() public {
        // Create two strategies
        address[] memory conservVaults = new address[](2);
        conservVaults[0] = address(yvSenior);
        conservVaults[1] = address(yvMezz);
        uint256[] memory conservAllocs = new uint256[](2);
        conservAllocs[0] = 8_000;
        conservAllocs[1] = 2_000;

        address[] memory balancedVaults = new address[](2);
        balancedVaults[0] = address(yvSenior);
        balancedVaults[1] = address(yvMezz);
        uint256[] memory balancedAllocs = new uint256[](2);
        balancedAllocs[0] = 5_000;
        balancedAllocs[1] = 5_000;

        vm.startPrank(gov);
        uint256 conservId = router.createStrategy("Conservative", conservVaults, conservAllocs);
        uint256 balancedId = router.createStrategy("Balanced", balancedVaults, balancedAllocs);
        vm.stopPrank();

        // Alice opens conservative position
        vm.prank(alice);
        uint256 posId = router.openPosition(conservId, 200_000e18);

        uint256 valueBefore = router.getPositionValue(posId);
        assertApproxEqRel(valueBefore, 200_000e18, 1e15, "Initial value");

        // Rebalance to balanced
        vm.prank(alice);
        router.rebalance(posId, balancedId);

        (,uint256 newSid,) = router.getPositionInfo(posId);
        assertEq(newSid, balancedId, "Switched to balanced");

        // Close position
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        router.closePosition(posId);
        uint256 received = usdc.balanceOf(alice) - balBefore;

        assertApproxEqRel(received, 200_000e18, 1e15, "Got back deposit");
    }

    /// @dev E2E: CDS pool deposit → gauge rewards → claim
    function test_e2e_gaugeRewards() public {
        // Alice and Bob deposit into CDS pool
        vm.prank(alice);
        pool.deposit(750_000e18);
        vm.prank(bob);
        pool.deposit(250_000e18);

        // Governance funds gauge
        vm.prank(gov);
        gauge.notifyRewardAmount(10_000e18, WEEK);

        // Checkpoint both LPs
        gauge.checkpoint(alice);
        gauge.checkpoint(bob);

        // Warp full week
        vm.warp(block.timestamp + WEEK);

        // Both claim rewards
        uint256 aliceBalBefore = rewardToken.balanceOf(alice);
        vm.prank(alice);
        gauge.claimReward();
        uint256 aliceReward = rewardToken.balanceOf(alice) - aliceBalBefore;

        uint256 bobBalBefore = rewardToken.balanceOf(bob);
        vm.prank(bob);
        gauge.claimReward();
        uint256 bobReward = rewardToken.balanceOf(bob) - bobBalBefore;

        // Alice should get ~75%, Bob ~25%
        assertApproxEqRel(aliceReward, 7_500e18, 1e15, "Alice 75%");
        assertApproxEqRel(bobReward, 2_500e18, 1e15, "Bob 25%");

        // Total should be ~10k
        assertApproxEqRel(aliceReward + bobReward, 10_000e18, 1e15, "Total distributed");
    }
}
