// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

// CDS AMM
import {CDSPoolFactory} from "../src/shield/CDSPoolFactory.sol";
import {ICDSPool} from "../src/interfaces/ICDSPool.sol";

// Composability
import {PoolRouter} from "../src/PoolRouter.sol";
import {FlashRebalancer} from "../src/FlashRebalancer.sol";
import {LiquidationBot} from "../src/LiquidationBot.sol";
import {HedgeRouter} from "../src/HedgeRouter.sol";

// Yield
import {YieldVaultFactory} from "../src/yield/YieldVaultFactory.sol";
import {StrategyRouter} from "../src/yield/StrategyRouter.sol";
import {LPIncentiveGauge} from "../src/yield/LPIncentiveGauge.sol";

// Mocks
import {MockFlashLender} from "../src/mocks/MockFlashLender.sol";
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";

/// @title DeployPhase5
/// @notice Deploys CDS AMM, composability routers, and yield layer to Fuji.
/// @dev Requires Phase 1 addresses from .env (ForgeFactory, ShieldFactory, etc.)
///      Run: forge script script/DeployPhase5.s.sol --rpc-url fuji --broadcast
contract DeployPhase5 is Script {
    // --- Pre-existing addresses from Phase 1 deploy ---
    address forgeFactory;
    address shieldFactory;
    address nexusHub;
    address creditOracle;
    address shieldPricer;
    address underlying; // MockUSDC
    address forgeVault; // First ForgeVault

    // --- New deployments ---
    CDSPoolFactory public poolFactory;
    MockFlashLender public flashLender;
    PoolRouter public poolRouter;
    FlashRebalancer public flashRebalancer;
    LiquidationBot public liquidationBot;
    YieldVaultFactory public yvFactory;
    StrategyRouter public strategyRouter;
    // LPIncentiveGauge deployed per-pool

    // YieldVault addresses
    address public yvSenior;
    address public yvMezz;
    address public yvEquity;

    // CDS Pool for the first vault
    address public cdsPool;

    // Gauge
    LPIncentiveGauge public gauge;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load existing addresses
        forgeFactory = vm.envAddress("NEXT_PUBLIC_FORGE_FACTORY");
        shieldFactory = vm.envAddress("NEXT_PUBLIC_SHIELD_FACTORY");
        nexusHub = vm.envAddress("NEXT_PUBLIC_NEXUS_HUB");
        creditOracle = vm.envAddress("NEXT_PUBLIC_CREDIT_ORACLE");
        shieldPricer = vm.envAddress("NEXT_PUBLIC_SHIELD_PRICER");
        underlying = vm.envAddress("NEXT_PUBLIC_MOCK_USDC");

        // ForgeVault #0 address (first vault created by factory)
        forgeVault = vm.envOr("NEXT_PUBLIC_FORGE_VAULT_0", address(0));

        console.log("Deployer:", deployer);
        console.log("Existing ForgeFactory:", forgeFactory);
        console.log("Existing MockUSDC:", underlying);

        vm.startBroadcast(deployerPrivateKey);

        _deployCDSInfra(deployer);
        _deployComposability(deployer);
        _deployYieldLayer(deployer);
        _createCDSPool();
        _createYieldVaults();
        _createStrategies();
        _deployGauge(deployer);

        vm.stopBroadcast();

        _logAddresses();
    }

    function _deployCDSInfra(address deployer) internal {
        console.log("");
        console.log("[1/7] Deploying CDS AMM infrastructure...");
        poolFactory = new CDSPoolFactory(deployer, deployer, 0);
        flashLender = new MockFlashLender();

        // Fund flash lender with MockUSDC
        MockYieldSource(underlying).mint(address(flashLender), 10_000_000e18);

        console.log("  CDSPoolFactory:", address(poolFactory));
        console.log("  MockFlashLender:", address(flashLender));
    }

    function _deployComposability(address deployer) internal {
        console.log("[2/7] Deploying composability routers...");
        poolRouter = new PoolRouter(address(poolFactory), deployer);
        flashRebalancer = new FlashRebalancer(address(flashLender), deployer);
        liquidationBot = new LiquidationBot(
            creditOracle,
            address(poolFactory),
            nexusHub
        );

        console.log("  PoolRouter:", address(poolRouter));
        console.log("  FlashRebalancer:", address(flashRebalancer));
        console.log("  LiquidationBot:", address(liquidationBot));
    }

    function _deployYieldLayer(address deployer) internal {
        console.log("[3/7] Deploying yield layer...");
        yvFactory = new YieldVaultFactory(deployer);
        strategyRouter = new StrategyRouter(deployer);

        console.log("  YieldVaultFactory:", address(yvFactory));
        console.log("  StrategyRouter:", address(strategyRouter));
    }

    function _createCDSPool() internal {
        console.log("[4/7] Creating CDS AMM pool for ForgeVault #0...");

        if (forgeVault == address(0)) {
            console.log("  SKIPPED: NEXT_PUBLIC_FORGE_VAULT_0 not set");
            return;
        }

        cdsPool = poolFactory.createPool(CDSPoolFactory.CreatePoolParams({
            referenceAsset: forgeVault,
            collateralToken: underlying,
            oracle: creditOracle,
            maturity: block.timestamp + 365 days,
            baseSpreadWad: 0.02e18,
            slopeWad: 0.05e18
        }));

        console.log("  CDSPool #0:", cdsPool);
    }

    function _createYieldVaults() internal {
        console.log("[5/7] Creating YieldVaults for each tranche...");

        if (forgeVault == address(0)) {
            console.log("  SKIPPED: NEXT_PUBLIC_FORGE_VAULT_0 not set");
            return;
        }

        yvSenior = yvFactory.createYieldVault(forgeVault, 0, "Auto-Compound Senior", "acSR", 1 hours);
        yvMezz = yvFactory.createYieldVault(forgeVault, 1, "Auto-Compound Mezzanine", "acMZ", 1 hours);
        yvEquity = yvFactory.createYieldVault(forgeVault, 2, "Auto-Compound Equity", "acEQ", 1 hours);

        console.log("  YieldVault Senior:", yvSenior);
        console.log("  YieldVault Mezzanine:", yvMezz);
        console.log("  YieldVault Equity:", yvEquity);
    }

    function _createStrategies() internal {
        console.log("[6/7] Creating allocation strategies...");

        if (yvSenior == address(0)) {
            console.log("  SKIPPED: YieldVaults not deployed");
            return;
        }

        // Conservative: 80% Senior + 20% Mezz
        address[] memory conservVaults = new address[](2);
        conservVaults[0] = yvSenior;
        conservVaults[1] = yvMezz;
        uint256[] memory conservAllocs = new uint256[](2);
        conservAllocs[0] = 8_000;
        conservAllocs[1] = 2_000;
        strategyRouter.createStrategy("Conservative", conservVaults, conservAllocs);
        console.log("  Strategy 0: Conservative (80% Senior + 20% Mezz)");

        // Balanced: 50% Senior + 30% Mezz + 20% Equity
        address[] memory balancedVaults = new address[](3);
        balancedVaults[0] = yvSenior;
        balancedVaults[1] = yvMezz;
        balancedVaults[2] = yvEquity;
        uint256[] memory balancedAllocs = new uint256[](3);
        balancedAllocs[0] = 5_000;
        balancedAllocs[1] = 3_000;
        balancedAllocs[2] = 2_000;
        strategyRouter.createStrategy("Balanced", balancedVaults, balancedAllocs);
        console.log("  Strategy 1: Balanced (50% Senior + 30% Mezz + 20% Equity)");

        // Aggressive: 30% Mezz + 70% Equity
        address[] memory aggroVaults = new address[](2);
        aggroVaults[0] = yvMezz;
        aggroVaults[1] = yvEquity;
        uint256[] memory aggroAllocs = new uint256[](2);
        aggroAllocs[0] = 3_000;
        aggroAllocs[1] = 7_000;
        strategyRouter.createStrategy("Aggressive", aggroVaults, aggroAllocs);
        console.log("  Strategy 2: Aggressive (30% Mezz + 70% Equity)");
    }

    function _deployGauge(address deployer) internal {
        console.log("[7/7] Deploying LP incentive gauge...");

        if (cdsPool == address(0)) {
            console.log("  SKIPPED: CDS Pool not deployed");
            return;
        }

        // Deploy a reward token for the gauge
        MockYieldSource rewardToken = new MockYieldSource("Meridian Rewards", "MRD", 18);
        gauge = new LPIncentiveGauge(cdsPool, address(rewardToken), deployer);

        // Mint reward tokens and fund gauge
        rewardToken.mint(deployer, 1_000_000e18);
        rewardToken.approve(address(gauge), type(uint256).max);
        gauge.notifyRewardAmount(100_000e18, 30 days);

        console.log("  RewardToken (MRD):", address(rewardToken));
        console.log("  LPIncentiveGauge:", address(gauge));
        console.log("  Funded: 100,000 MRD over 30 days");
    }

    function _logAddresses() internal view {
        console.log("");
        console.log("=== PHASE 5 DEPLOYED ===");
        console.log("");
        console.log("--- CDS AMM ---");
        console.log("CDSPoolFactory:", address(poolFactory));
        console.log("CDSPool #0:", cdsPool);
        console.log("MockFlashLender:", address(flashLender));
        console.log("");
        console.log("--- Composability ---");
        console.log("PoolRouter:", address(poolRouter));
        console.log("FlashRebalancer:", address(flashRebalancer));
        console.log("LiquidationBot:", address(liquidationBot));
        console.log("");
        console.log("--- Yield ---");
        console.log("YieldVaultFactory:", address(yvFactory));
        console.log("YieldVault Senior:", yvSenior);
        console.log("YieldVault Mezzanine:", yvMezz);
        console.log("YieldVault Equity:", yvEquity);
        console.log("StrategyRouter:", address(strategyRouter));
        console.log("LPIncentiveGauge:", address(gauge));
        console.log("");
        console.log("=== ADD TO frontend/.env.local ===");
        console.log("NEXT_PUBLIC_CDS_POOL_FACTORY=", address(poolFactory));
        console.log("NEXT_PUBLIC_POOL_ROUTER=", address(poolRouter));
        console.log("NEXT_PUBLIC_FLASH_REBALANCER=", address(flashRebalancer));
        console.log("NEXT_PUBLIC_LIQUIDATION_BOT=", address(liquidationBot));
        console.log("NEXT_PUBLIC_YIELD_VAULT_FACTORY=", address(yvFactory));
        console.log("NEXT_PUBLIC_STRATEGY_ROUTER=", address(strategyRouter));
        console.log("NEXT_PUBLIC_LP_GAUGE=", address(gauge));
    }
}
