// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "@forge-std/Script.sol";
import {AIRiskOracle} from "../src/ai/AIRiskOracle.sol";
import {AIStrategyOptimizer} from "../src/ai/AIStrategyOptimizer.sol";
import {AIKeeper} from "../src/ai/AIKeeper.sol";
import {AICreditEventDetector} from "../src/ai/AICreditEventDetector.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {ShieldPricer} from "../src/shield/ShieldPricer.sol";

/// @title DeployAI
/// @notice Deploys all 4 AI components and wires them to existing protocol contracts.
/// @dev Requires existing protocol deployment addresses in environment variables.
///
///      Run: forge script script/DeployAI.s.sol --rpc-url fuji --broadcast
///
///      Post-deploy actions (manual):
///      1. CreditEventOracle.setReporter(detectorAddress, true)
///      2. ShieldPricer.setRiskOracle(riskOracleAddress)
///      3. Set AI updater/agent/monitor/detector addresses
contract DeployAI is Script {
    // --- Deployed contract addresses (from env or hardcoded) ---
    address creditOracle;
    address poolFactory;
    address nexusHub;
    address strategyRouter;
    address shieldPricer;

    // --- AI contracts ---
    AIRiskOracle riskOracle;
    AIStrategyOptimizer strategyOptimizer;
    AIKeeper aiKeeper;
    AICreditEventDetector creditEventDetector;

    function run() external {
        // Load existing addresses from environment
        creditOracle = vm.envOr("CREDIT_ORACLE", address(0));
        poolFactory = vm.envOr("POOL_FACTORY", address(0));
        nexusHub = vm.envOr("NEXUS_HUB", address(0));
        strategyRouter = vm.envOr("STRATEGY_ROUTER", address(0));
        shieldPricer = vm.envOr("SHIELD_PRICER", address(0));

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        _deployRiskOracle(deployer);
        _deployStrategyOptimizer(deployer);
        _deployKeeper(deployer);
        _deployCreditEventDetector(deployer);

        vm.stopBroadcast();

        _logAddresses();
    }

    function _deployRiskOracle(address deployer) internal {
        riskOracle = new AIRiskOracle(
            1 days,   // maxScoreAge: 24 hours
            0.1e18    // maxScoreChange: 10% max PD delta per update
        );
        console.log("AIRiskOracle deployed at:", address(riskOracle));

        // Wire to ShieldPricer if available
        if (shieldPricer != address(0)) {
            // Note: ShieldPricer.setRiskOracle must be called by its owner
            console.log("  -> Call ShieldPricer.setRiskOracle(%s)", address(riskOracle));
        }
    }

    function _deployStrategyOptimizer(address deployer) internal {
        if (strategyRouter != address(0)) {
            strategyOptimizer = new AIStrategyOptimizer(
                strategyRouter,
                deployer,    // governance = deployer initially
                7 days,      // proposalExpiry
                5000         // minConfidence = 50%
            );
            console.log("AIStrategyOptimizer deployed at:", address(strategyOptimizer));
            console.log("  -> Transfer StrategyRouter governance to optimizer for createStrategy access");
        } else {
            console.log("SKIP: AIStrategyOptimizer (no STRATEGY_ROUTER set)");
        }
    }

    function _deployKeeper(address deployer) internal {
        if (nexusHub != address(0) && creditOracle != address(0) && poolFactory != address(0)) {
            aiKeeper = new AIKeeper(
                nexusHub,
                creditOracle,
                poolFactory,
                1 days   // maxPriorityAge
            );
            console.log("AIKeeper deployed at:", address(aiKeeper));
        } else {
            console.log("SKIP: AIKeeper (missing NEXUS_HUB, CREDIT_ORACLE, or POOL_FACTORY)");
        }
    }

    function _deployCreditEventDetector(address deployer) internal {
        if (creditOracle != address(0)) {
            creditEventDetector = new AICreditEventDetector(
                creditOracle,
                deployer,  // governance = deployer initially
                9000,      // 90% auto-report threshold
                6 hours,   // timelock duration
                3,         // max 3 reports per window
                1 hours    // rate limit window
            );
            console.log("AICreditEventDetector deployed at:", address(creditEventDetector));
            console.log("  -> Call CreditEventOracle.setReporter(%s, true)", address(creditEventDetector));
        } else {
            console.log("SKIP: AICreditEventDetector (no CREDIT_ORACLE set)");
        }
    }

    function _logAddresses() internal pure {
        console.log("\n=== Post-Deploy Checklist ===");
        console.log("1. ShieldPricer.setRiskOracle(riskOracleAddress)");
        console.log("2. CreditEventOracle.setReporter(detectorAddress, true)");
        console.log("3. AIRiskOracle.setUpdater(aiBackendAddress, true)");
        console.log("4. AIStrategyOptimizer.setAIAgent(aiAgentAddress, true)");
        console.log("5. AIKeeper.setAIMonitor(aiMonitorAddress, true)");
        console.log("6. AICreditEventDetector.setDetector(aiDetectorAddress, true)");
        console.log("7. Transfer StrategyRouter governance to AIStrategyOptimizer");
    }
}
