// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

// Mocks
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";
import {MockTeleporter} from "../src/mocks/MockTeleporter.sol";
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";

// Forge
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {ForgeVault} from "../src/forge/ForgeVault.sol";
import {TrancheToken} from "../src/forge/TrancheToken.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";

// Shield
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {ICreditEventOracle} from "../src/interfaces/ICreditEventOracle.sol";

// CDS AMM
import {CDSPool} from "../src/shield/CDSPool.sol";
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../src/interfaces/ICDSPool.sol";

// Nexus
import {CollateralOracle} from "../src/nexus/CollateralOracle.sol";
import {NexusHub} from "../src/nexus/NexusHub.sol";

// Composability
import {PoolRouter} from "../src/PoolRouter.sol";
import {FlashRebalancer} from "../src/FlashRebalancer.sol";
import {LiquidationBot} from "../src/LiquidationBot.sol";

// Yield Layer
import {YieldVault} from "../src/yield/YieldVault.sol";
import {YieldVaultFactory} from "../src/yield/YieldVaultFactory.sol";
import {StrategyRouter} from "../src/yield/StrategyRouter.sol";
import {LPIncentiveGauge} from "../src/yield/LPIncentiveGauge.sol";

/// @title Demo Script
/// @notice End-to-end demonstration of the Meridian protocol on a local fork.
/// @dev Run: forge script script/Demo.s.sol -vvvv
///
///   The script walks through the full lifecycle:
///   1. Deploy all infrastructure
///   2. Create a structured credit vault (Forge)
///   3. Invest across Senior/Mezzanine/Equity tranches
///   4. Generate & distribute yield via waterfall
///   5. Create CDS AMM pools (Shield)
///   6. Buy protection via the multi-pool router
///   7. Trigger a credit event and settle
///   8. Flash-rebalance a tranche position
///   9. Liquidation waterfall execution
///  10. Auto-compounding YieldVaults
///  11. Multi-strategy routing (Conservative → Aggressive)
///  12. LP incentive gauge reward mining
contract Demo is Script {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;
    uint256 constant WEEK = 7 days;

    // Infrastructure
    MockYieldSource usdc;
    MockFlashLender flashLender;
    CreditEventOracle oracle;
    CollateralOracle collateralOracle;
    MockTeleporter teleporter;

    // Factories
    ForgeFactory forgeFactory;
    CDSPoolFactory poolFactory;

    // Protocol
    NexusHub nexusHub;
    PoolRouter poolRouter;
    FlashRebalancer flashRebalancer;
    LiquidationBot liquidationBot;

    // Actors
    address deployer;
    address alice; // LP / Senior investor
    address bob;   // Protection buyer / Mezz investor
    address charlie; // Equity investor / Margin user

    function run() external {
        deployer = msg.sender;
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        charlie = vm.addr(0xC4A1);

        console.log("=================================================");
        console.log("  MERIDIAN PROTOCOL - END-TO-END DEMO");
        console.log("=================================================");
        console.log("");

        _step1_deployInfrastructure();
        _step2_createVault();
        _step3_investInTranches();
        _step4_generateYield();
        _step5_createCDSPools();
        _step6_buyProtectionRouted();
        _step7_creditEventAndSettle();
        _step8_flashRebalance();
        _step9_liquidationWaterfall();
        _step10_yieldVaults();
        _step11_strategyRouting();
        _step12_lpIncentiveGauge();

        console.log("");
        console.log("=================================================");
        console.log("  DEMO COMPLETE - All 12 protocol features exercised");
        console.log("=================================================");
    }

    // --- Stored for cross-step access ---
    ForgeVault vault;
    CDSPool pool1;
    CDSPool pool2;

    // Yield layer
    YieldVaultFactory yvFactory;
    StrategyRouter strategyRouter;
    YieldVault yvSenior;
    YieldVault yvMezz;
    YieldVault yvEquity;
    LPIncentiveGauge gauge;
    MockYieldSource rewardToken;

    function _step1_deployInfrastructure() internal {
        console.log("[Step 1] Deploying infrastructure...");

        usdc = new MockYieldSource("Mock USDC", "USDC", 18);
        flashLender = new MockFlashLender();
        oracle = new CreditEventOracle();
        teleporter = new MockTeleporter(bytes32(uint256(43113)));
        collateralOracle = new CollateralOracle();

        forgeFactory = new ForgeFactory(deployer, deployer, 0);
        poolFactory = new CDSPoolFactory(deployer, deployer, 0);

        nexusHub = new NexusHub(
            address(collateralOracle),
            address(teleporter),
            1.1e18,  // 110% liquidation threshold
            500      // 5% penalty
        );

        poolRouter = new PoolRouter(address(poolFactory), deployer);
        flashRebalancer = new FlashRebalancer(address(flashLender), deployer);
        liquidationBot = new LiquidationBot(
            address(oracle),
            address(poolFactory),
            address(nexusHub)
        );

        // Fund flash lender
        usdc.mint(address(flashLender), 50_000_000e18);

        // Fund actors
        usdc.mint(alice, 10_000_000e18);
        usdc.mint(bob, 10_000_000e18);
        usdc.mint(charlie, 10_000_000e18);

        // Register USDC in collateral oracle
        collateralOracle.registerAsset(address(usdc), 1e18, 10_000);

        console.log("  USDC:", address(usdc));
        console.log("  ForgeFactory:", address(forgeFactory));
        console.log("  CDSPoolFactory:", address(poolFactory));
        console.log("  NexusHub:", address(nexusHub));
        console.log("  PoolRouter:", address(poolRouter));
        console.log("  FlashRebalancer:", address(flashRebalancer));
        console.log("  LiquidationBot:", address(liquidationBot));
        console.log("");
    }

    function _step2_createVault() internal {
        console.log("[Step 2] Creating structured credit vault...");

        uint256 factoryNonce = vm.getNonce(address(forgeFactory));
        address predictedVault = vm.computeCreateAddress(address(forgeFactory), factoryNonce);

        TrancheToken senior = new TrancheToken("Senior", "SR", predictedVault, 0);
        TrancheToken mezz = new TrancheToken("Mezzanine", "MZ", predictedVault, 1);
        TrancheToken equity = new TrancheToken("Equity", "EQ", predictedVault, 2);

        IForgeVault.TrancheParams[3] memory params;
        params[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(senior)});
        params[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mezz)});
        params[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(equity)});

        address vaultAddr = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(senior), address(mezz), address(equity)],
                trancheParams: params,
                distributionInterval: WEEK
            })
        );
        vault = ForgeVault(vaultAddr);

        console.log("  Vault deployed:", vaultAddr);
        console.log("  Senior (5% APR, 70% allocation):", address(senior));
        console.log("  Mezzanine (10% APR, 20% allocation):", address(mezz));
        console.log("  Equity (15% APR, 10% allocation):", address(equity));
        console.log("");
    }

    function _step3_investInTranches() internal {
        console.log("[Step 3] Investors entering tranches...");

        // Alice -> Senior (700k)
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.invest(0, 700_000e18);
        vm.stopPrank();
        console.log("  Alice invested 700,000 USDC in Senior");

        // Bob -> Mezzanine (200k)
        vm.startPrank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vault.invest(1, 200_000e18);
        vm.stopPrank();
        console.log("  Bob invested 200,000 USDC in Mezzanine");

        // Charlie -> Equity (100k)
        vm.startPrank(charlie);
        usdc.approve(address(vault), type(uint256).max);
        vault.invest(2, 100_000e18);
        vm.stopPrank();
        console.log("  Charlie invested 100,000 USDC in Equity");

        IForgeVault.PoolMetrics memory metrics = vault.getPoolMetrics();
        console.log("  Total vault TVL:", metrics.totalDeposited / 1e18, "USDC");
        console.log("");
    }

    function _step4_generateYield() internal {
        console.log("[Step 4] Generating yield and distributing via waterfall...");

        // Simulate yield accrual
        usdc.mint(address(vault), 50_000e18); // 50k yield
        vm.warp(block.timestamp + WEEK);

        vault.triggerWaterfall();

        // Claims
        vm.prank(alice);
        uint256 aliceYield = vault.claimYield(0);
        vm.prank(bob);
        uint256 bobYield = vault.claimYield(1);
        vm.prank(charlie);
        uint256 charlieYield = vault.claimYield(2);

        console.log("  50,000 USDC yield generated");
        console.log("  Alice (Senior) claimed:", aliceYield / 1e18, "USDC");
        console.log("  Bob (Mezzanine) claimed:", bobYield / 1e18, "USDC");
        console.log("  Charlie (Equity) claimed:", charlieYield / 1e18, "USDC");
        console.log("  Waterfall priority: Senior gets paid first, Equity absorbs residual");
        console.log("");
    }

    function _step5_createCDSPools() internal {
        console.log("[Step 5] Creating CDS AMM pools...");

        // Pool 1: 2% base spread
        pool1 = CDSPool(poolFactory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: address(vault),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        })));

        // Pool 2: 4% base spread
        pool2 = CDSPool(poolFactory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: address(vault),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.04e18,
            slopeWad: 0.05e18
        })));

        // Alice provides liquidity to both pools
        vm.startPrank(alice);
        usdc.approve(address(pool1), type(uint256).max);
        usdc.approve(address(pool2), type(uint256).max);
        pool1.deposit(500_000e18);
        pool2.deposit(300_000e18);
        vm.stopPrank();

        console.log("  Pool 1 (2% base spread):", address(pool1));
        console.log("    Liquidity: 500,000 USDC");
        console.log("  Pool 2 (4% base spread):", address(pool2));
        console.log("    Liquidity: 300,000 USDC");
        console.log("");
    }

    function _step6_buyProtectionRouted() internal {
        console.log("[Step 6] Bob buys protection via multi-pool router...");

        // Quote through router (finds cheapest path)
        PoolRouter.RouteQuote memory quote = poolRouter.quoteRouted(address(vault), 600_000e18);
        console.log("  Requested: 600,000 USDC protection");
        console.log("  Quoted premium:", quote.totalPremium / 1e18, "USDC");
        console.log("  Pools used:", quote.pools.length);

        // Execute routed buy
        vm.startPrank(bob);
        usdc.approve(address(poolRouter), type(uint256).max);
        PoolRouter.FillResult[] memory results = poolRouter.buyProtectionRouted(
            address(vault),
            600_000e18,
            quote.totalPremium + 10_000e18 // slippage buffer
        );
        vm.stopPrank();

        for (uint256 i = 0; i < results.length; i++) {
            console.log("  Fill", i + 1);
            console.log("    Pool:", results[i].pool);
            console.log("    Notional:", results[i].notional / 1e18, "USDC");
            console.log("    Premium:", results[i].premium / 1e18, "USDC");
        }

        console.log("  Pool 1 utilization:", pool1.utilizationRate() * 100 / 1e18, "%");
        console.log("  Pool 2 utilization:", pool2.utilizationRate() * 100 / 1e18, "%");
        console.log("");
    }

    function _step7_creditEventAndSettle() internal {
        console.log("[Step 7] Credit event and CDS settlement...");

        // Oracle reports credit event
        oracle.reportCreditEvent(
            address(vault),
            ICreditEventOracle.EventType.Default,
            500_000e18
        );
        console.log("  Credit event reported: Default, 500,000 USDC loss amount");

        // LiquidationBot triggers all pools
        uint256 triggered = liquidationBot.triggerAllPoolsForVault(address(vault));
        console.log("  Pools triggered:", triggered);

        // Settle with 50% recovery
        uint256 settled = liquidationBot.settleAllPoolsForVault(address(vault), 0.5e18);
        console.log("  Pools settled:", settled, "(50% recovery rate)");

        console.log("  Pool 1 status:", uint256(pool1.getPoolStatus())); // 2 = Settled
        console.log("  Pool 2 status:", uint256(pool2.getPoolStatus())); // 2 = Settled
        console.log("");
    }

    function _step8_flashRebalance() internal {
        console.log("[Step 8] Flash rebalance: Alice moves Senior -> Equity...");

        // Create a fresh vault for this step (previous vault is entangled with settled CDS)
        uint256 factoryNonce = vm.getNonce(address(forgeFactory));
        address predictedVault2 = vm.computeCreateAddress(address(forgeFactory), factoryNonce);

        TrancheToken sr2 = new TrancheToken("Senior-2", "SR2", predictedVault2, 0);
        TrancheToken mz2 = new TrancheToken("Mezzanine-2", "MZ2", predictedVault2, 1);
        TrancheToken eq2 = new TrancheToken("Equity-2", "EQ2", predictedVault2, 2);

        IForgeVault.TrancheParams[3] memory params2;
        params2[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(sr2)});
        params2[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mz2)});
        params2[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(eq2)});

        address v2addr = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(sr2), address(mz2), address(eq2)],
                trancheParams: params2,
                distributionInterval: WEEK
            })
        );
        ForgeVault vault2 = ForgeVault(v2addr);

        // Alice invests in Senior
        vm.startPrank(alice);
        usdc.approve(v2addr, type(uint256).max);
        vault2.invest(0, 200_000e18);

        uint256 seniorBefore = vault2.getShares(alice, 0);
        uint256 equityBefore = vault2.getShares(alice, 2);

        // Approve rebalancer for senior tranche tokens
        sr2.approve(address(flashRebalancer), 50_000e18);

        // Flash rebalance 50k from Senior to Equity
        flashRebalancer.rebalance(v2addr, 0, 2, 50_000e18);
        vm.stopPrank();

        uint256 seniorAfter = vault2.getShares(alice, 0);
        uint256 equityAfter = vault2.getShares(alice, 2);

        console.log("  Vault 2:", v2addr);
        console.log("  Alice Senior before:", seniorBefore / 1e18, "-> after:", seniorAfter / 1e18);
        console.log("  Alice Equity before:", equityBefore / 1e18, "-> after:", equityAfter / 1e18);
        console.log("  Atomically moved 50,000 from Senior to Equity via flash loan");
        console.log("");
    }

    function _step9_liquidationWaterfall() internal {
        console.log("[Step 9] NexusHub margin liquidation...");

        // Charlie opens margin account and deposits
        vm.startPrank(charlie);
        usdc.approve(address(nexusHub), type(uint256).max);
        nexusHub.openMarginAccount();
        nexusHub.depositCollateral(address(usdc), 100_000e18);
        vm.stopPrank();

        console.log("  Charlie deposited 100,000 USDC as collateral");

        // Set obligation making Charlie unhealthy
        nexusHub.setObligation(charlie, 95_000e18);
        bool healthy = nexusHub.isHealthy(charlie);
        console.log("  Obligation set: 95,000 USDC");
        console.log("  Margin ratio: ~105% (below 110% threshold)");
        console.log("  Is healthy:", healthy);

        // Liquidation bot executes
        liquidationBot.liquidateAccount(charlie);
        console.log("  LiquidationBot.liquidateAccount() executed");
        console.log("  Post-liquidation obligation:", nexusHub.obligations(charlie) / 1e18, "USDC");
        console.log("");
    }

    // --- Vault3 used by Steps 10-11 ---
    ForgeVault vault3;

    function _step10_yieldVaults() internal {
        console.log("[Step 10] Auto-compounding YieldVaults...");

        // Create a fresh vault for yield demo
        uint256 factoryNonce = vm.getNonce(address(forgeFactory));
        address predictedVault3 = vm.computeCreateAddress(address(forgeFactory), factoryNonce);

        TrancheToken sr3 = new TrancheToken("Senior-3", "SR3", predictedVault3, 0);
        TrancheToken mz3 = new TrancheToken("Mezzanine-3", "MZ3", predictedVault3, 1);
        TrancheToken eq3 = new TrancheToken("Equity-3", "EQ3", predictedVault3, 2);

        IForgeVault.TrancheParams[3] memory params3;
        params3[0] = IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(sr3)});
        params3[1] = IForgeVault.TrancheParams({targetApr: 1000, allocationPct: 20, token: address(mz3)});
        params3[2] = IForgeVault.TrancheParams({targetApr: 1500, allocationPct: 10, token: address(eq3)});

        address v3addr = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(usdc),
                trancheTokenAddresses: [address(sr3), address(mz3), address(eq3)],
                trancheParams: params3,
                distributionInterval: WEEK
            })
        );
        vault3 = ForgeVault(v3addr);

        // Deploy YieldVault factory and create vaults for each tranche
        yvFactory = new YieldVaultFactory(deployer);
        address yvSeniorAddr = yvFactory.createYieldVault(v3addr, 0, "Auto-Compound Senior", "acSR", 1 hours);
        address yvMezzAddr = yvFactory.createYieldVault(v3addr, 1, "Auto-Compound Mezzanine", "acMZ", 1 hours);
        address yvEquityAddr = yvFactory.createYieldVault(v3addr, 2, "Auto-Compound Equity", "acEQ", 1 hours);
        yvSenior = YieldVault(yvSeniorAddr);
        yvMezz = YieldVault(yvMezzAddr);
        yvEquity = YieldVault(yvEquityAddr);

        console.log("  Vault 3:", v3addr);
        console.log("  YieldVault Senior:", yvSeniorAddr);
        console.log("  YieldVault Mezzanine:", yvMezzAddr);
        console.log("  YieldVault Equity:", yvEquityAddr);

        // Alice deposits 500k into Senior YieldVault (auto-compound)
        vm.startPrank(alice);
        usdc.approve(yvSeniorAddr, type(uint256).max);
        yvSenior.deposit(500_000e18, alice);
        vm.stopPrank();

        uint256 sharesBefore = yvSenior.balanceOf(alice);
        uint256 assetsBefore = yvSenior.totalAssets();
        console.log("  Alice deposited 500,000 USDC into Senior YieldVault");
        console.log("  Shares received:", sharesBefore / 1e18);
        console.log("  Total assets:", assetsBefore / 1e18, "USDC");

        // Simulate yield and compound
        usdc.mint(v3addr, 25_000e18); // 25k yield
        vm.warp(block.timestamp + WEEK);
        vault3.triggerWaterfall();

        // Compound (anyone can call)
        vm.warp(block.timestamp + 2 hours);
        uint256 harvested = yvSenior.compound();

        uint256 assetsAfter = yvSenior.totalAssets();
        console.log("  Yield generated: 25,000 USDC");
        console.log("  Compounded:", harvested / 1e18, "USDC (auto-reinvested)");
        console.log("  Total assets after:", assetsAfter / 1e18, "USDC");
        console.log("  Share price appreciated from 1.00 to", (yvSenior.convertToAssets(1e18) * 100) / 1e18, "/ 100");
        console.log("");
    }

    function _step11_strategyRouting() internal {
        console.log("[Step 11] Multi-strategy routing...");

        // Deploy strategy router (governance = deployer)
        strategyRouter = new StrategyRouter(deployer);

        // Create Conservative strategy: 80% Senior + 20% Mezz
        address[] memory conservVaults = new address[](2);
        conservVaults[0] = address(yvSenior);
        conservVaults[1] = address(yvMezz);
        uint256[] memory conservAllocs = new uint256[](2);
        conservAllocs[0] = 8_000;
        conservAllocs[1] = 2_000;
        vm.prank(deployer);
        uint256 conservId = strategyRouter.createStrategy("Conservative", conservVaults, conservAllocs);
        console.log("  Strategy 0: Conservative (80% Senior + 20% Mezz)");

        // Create Aggressive strategy: 30% Mezz + 70% Equity
        address[] memory aggroVaults = new address[](2);
        aggroVaults[0] = address(yvMezz);
        aggroVaults[1] = address(yvEquity);
        uint256[] memory aggroAllocs = new uint256[](2);
        aggroAllocs[0] = 3_000;
        aggroAllocs[1] = 7_000;
        vm.prank(deployer);
        uint256 aggroId = strategyRouter.createStrategy("Aggressive", aggroVaults, aggroAllocs);
        console.log("  Strategy 1: Aggressive (30% Mezz + 70% Equity)");

        // Bob opens a Conservative position
        vm.startPrank(bob);
        usdc.approve(address(strategyRouter), type(uint256).max);
        uint256 posId = strategyRouter.openPosition(conservId, 100_000e18);
        vm.stopPrank();

        uint256 posValue = strategyRouter.getPositionValue(posId);
        console.log("  Bob opened 100,000 USDC Conservative position (ID:", posId, ")");
        console.log("  Position value:", posValue / 1e18, "USDC");

        // Bob rebalances from Conservative to Aggressive
        vm.prank(bob);
        strategyRouter.rebalance(posId, aggroId);

        uint256 posValueAfter = strategyRouter.getPositionValue(posId);
        console.log("  Rebalanced: Conservative -> Aggressive");
        console.log("  Position value after rebalance:", posValueAfter / 1e18, "USDC");

        // Close position
        vm.prank(bob);
        uint256 amountOut = strategyRouter.closePosition(posId);
        console.log("  Closed position. Amount returned:", amountOut / 1e18, "USDC");
        console.log("");
    }

    function _step12_lpIncentiveGauge() internal {
        console.log("[Step 12] LP incentive gauge rewards...");

        // Create a fresh CDS pool for gauge demo
        CDSPool gaugePool = CDSPool(poolFactory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: address(vault3),
            collateralToken: address(usdc),
            oracle: address(oracle),
            maturity: block.timestamp + YEAR,
            baseSpreadWad: 0.03e18,
            slopeWad: 0.05e18
        })));

        // Deploy reward token and gauge
        rewardToken = new MockYieldSource("Meridian Rewards", "MRD", 18);
        gauge = new LPIncentiveGauge(address(gaugePool), address(rewardToken), deployer);

        console.log("  CDS Pool:", address(gaugePool));
        console.log("  Reward Token (MRD):", address(rewardToken));
        console.log("  Gauge:", address(gauge));

        // Alice provides LP liquidity
        vm.startPrank(alice);
        usdc.approve(address(gaugePool), type(uint256).max);
        gaugePool.deposit(200_000e18);
        vm.stopPrank();
        console.log("  Alice deposited 200,000 USDC as LP");

        // Charlie also provides LP liquidity
        vm.startPrank(charlie);
        usdc.approve(address(gaugePool), type(uint256).max);
        gaugePool.deposit(100_000e18);
        vm.stopPrank();
        console.log("  Charlie deposited 100,000 USDC as LP");

        console.log("  Alice LP shares:", gaugePool.sharesOf(alice) / 1e18);
        console.log("  Charlie LP shares:", gaugePool.sharesOf(charlie) / 1e18);

        // Fund gauge with rewards
        rewardToken.mint(deployer, 1_000_000e18);
        vm.startPrank(deployer);
        rewardToken.approve(address(gauge), type(uint256).max);
        gauge.notifyRewardAmount(100_000e18, 30 days);
        vm.stopPrank();
        console.log("  Gauge funded: 100,000 MRD over 30 days");

        // Time passes — 7 days of rewards
        vm.warp(block.timestamp + 7 days);

        uint256 aliceEarned = gauge.earned(alice);
        uint256 charlieEarned = gauge.earned(charlie);
        console.log("  After 7 days:");
        console.log("    Alice earned:", aliceEarned / 1e18, "MRD (~2/3 of rewards)");
        console.log("    Charlie earned:", charlieEarned / 1e18, "MRD (~1/3 of rewards)");

        // Alice claims
        vm.prank(alice);
        gauge.claimReward();
        console.log("  Alice claimed her MRD rewards");
        console.log("  Alice MRD balance:", rewardToken.balanceOf(alice) / 1e18);
        console.log("");
    }
}
