// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

// Mocks
import {MockYieldSource} from "../src/mocks/MockYieldSource.sol";
import {MockTeleporter} from "../src/mocks/MockTeleporter.sol";

// Forge
import {ForgeFactory} from "../src/forge/ForgeFactory.sol";
import {EncryptedTrancheToken} from "../src/forge/EncryptedTrancheToken.sol";
import {IForgeVault} from "../src/interfaces/IForgeVault.sol";

// Shield
import {ShieldFactory} from "../src/shield/ShieldFactory.sol";
import {CreditEventOracle} from "../src/shield/CreditEventOracle.sol";
import {ShieldPricer} from "../src/shield/ShieldPricer.sol";

// Nexus
import {CollateralOracle} from "../src/nexus/CollateralOracle.sol";
import {NexusHub} from "../src/nexus/NexusHub.sol";
import {NexusVault} from "../src/nexus/NexusVault.sol";

/// @title DeployFuji
/// @notice Deploys the entire Meridian protocol to Avalanche Fuji testnet.
/// @dev Run: forge script script/DeployFuji.s.sol --rpc-url fuji --broadcast
contract DeployFuji is Script {
    bytes32 constant FUJI_CHAIN_ID = bytes32(uint256(43113));

    // Deployed addresses stored as state to avoid stack-too-deep
    MockYieldSource public underlying;
    MockTeleporter public teleporter;
    CollateralOracle public collateralOracle;
    CreditEventOracle public creditOracle;
    ShieldPricer public pricer;
    NexusHub public nexusHub;
    NexusVault public nexusVault;
    ForgeFactory public forgeFactory;
    ShieldFactory public shieldFactory;
    EncryptedTrancheToken public seniorToken;
    EncryptedTrancheToken public mezzToken;
    EncryptedTrancheToken public equityToken;
    address public vault;
    address public cds;
    address public deployer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        _deployBase();
        _deployNexus();
        _deployFactories();
        _deployForgeVault();
        _deployCDS();
        _configure();

        vm.stopBroadcast();

        _logAddresses();
    }

    function _deployBase() internal {
        underlying = new MockYieldSource("Mock USDC", "mUSDC", 18);
        teleporter = new MockTeleporter(FUJI_CHAIN_ID);
        collateralOracle = new CollateralOracle();
        creditOracle = new CreditEventOracle();
        pricer = new ShieldPricer(
            ShieldPricer.PricingParams({
                baseRateBps: 50,
                riskMultiplierBps: 2000,
                utilizationKinkBps: 8000,
                utilizationSurchargeBps: 500,
                tenorScalerBps: 100,
                maxSpreadBps: 5000
            })
        );
    }

    function _deployNexus() internal {
        nexusHub = new NexusHub(
            address(collateralOracle),
            address(teleporter),
            1.1e18, // 110% liquidation threshold
            500 // 5% liquidation penalty
        );
        nexusVault = new NexusVault(
            address(collateralOracle),
            address(teleporter),
            FUJI_CHAIN_ID,
            address(nexusHub),
            300 // 5-minute attestation interval
        );
    }

    function _deployFactories() internal {
        forgeFactory = new ForgeFactory(deployer, deployer, 0);
        shieldFactory = new ShieldFactory();
    }

    function _deployForgeVault() internal {
        // Predict vault address from factory's CREATE nonce
        address predictedVault = vm.computeCreateAddress(
            address(forgeFactory),
            vm.getNonce(address(forgeFactory))
        );

        // Deploy tranche tokens pointing to predicted vault
        seniorToken = new EncryptedTrancheToken("Senior Tranche", "SR-01", predictedVault, 0);
        mezzToken = new EncryptedTrancheToken("Mezzanine Tranche", "MZ-01", predictedVault, 1);
        equityToken = new EncryptedTrancheToken("Equity Tranche", "EQ-01", predictedVault, 2);

        address[3] memory tokenAddrs =
            [address(seniorToken), address(mezzToken), address(equityToken)];

        IForgeVault.TrancheParams[3] memory trancheParams = [
            IForgeVault.TrancheParams({targetApr: 500, allocationPct: 70, token: address(seniorToken)}),
            IForgeVault.TrancheParams({targetApr: 1200, allocationPct: 20, token: address(mezzToken)}),
            IForgeVault.TrancheParams({targetApr: 0, allocationPct: 10, token: address(equityToken)})
        ];

        vault = forgeFactory.createVault(
            ForgeFactory.CreateVaultParams({
                underlyingAsset: address(underlying),
                trancheTokenAddresses: tokenAddrs,
                trancheParams: trancheParams,
                distributionInterval: 3600 // 1 hour for testnet
            })
        );

        require(vault == predictedVault, "DeployFuji: vault address mismatch");
    }

    function _deployCDS() internal {
        cds = shieldFactory.createCDS(
            ShieldFactory.CreateCDSParams({
                referenceAsset: vault,
                protectionAmount: 100_000e18,
                premiumRate: 250, // 2.5% annual
                maturity: block.timestamp + 365 days,
                collateralToken: address(underlying),
                oracle: address(creditOracle),
                paymentInterval: 1 days // daily for testnet
            })
        );
    }

    function _configure() internal {
        // Register assets in CollateralOracle
        collateralOracle.registerAsset(address(underlying), 1e18, 9500); // USDC: $1, 95%
        collateralOracle.registerAsset(address(seniorToken), 1e18, 8500); // Senior: 85%
        collateralOracle.registerAsset(address(mezzToken), 1e18, 6000); // Mezz: 60%
        collateralOracle.registerAsset(address(equityToken), 1e18, 4000); // Equity: 40%

        // Register NexusVault in NexusHub
        nexusHub.registerVault(FUJI_CHAIN_ID, address(nexusVault));

        // Set credit event thresholds
        creditOracle.setThreshold(vault, 0.9e18); // impairment at 90%
        creditOracle.setDefaultThreshold(vault, 0.5e18); // default at 50%

        // Mint test USDC to deployer
        underlying.mint(deployer, 1_000_000e18);
    }

    function _logAddresses() internal view {
        console.log("");
        console.log("=== MERIDIAN PROTOCOL DEPLOYED ===");
        console.log("");
        console.log("--- Mocks ---");
        console.log("MockYieldSource (USDC):", address(underlying));
        console.log("MockTeleporter:        ", address(teleporter));
        console.log("");
        console.log("--- Oracles ---");
        console.log("CollateralOracle:      ", address(collateralOracle));
        console.log("CreditEventOracle:     ", address(creditOracle));
        console.log("ShieldPricer:          ", address(pricer));
        console.log("");
        console.log("--- Nexus ---");
        console.log("NexusHub:              ", address(nexusHub));
        console.log("NexusVault:            ", address(nexusVault));
        console.log("");
        console.log("--- Forge ---");
        console.log("ForgeFactory:          ", address(forgeFactory));
        console.log("ForgeVault #0:         ", vault);
        console.log("Senior Token (SR-01):  ", address(seniorToken));
        console.log("Mezzanine Token (MZ-01):", address(mezzToken));
        console.log("Equity Token (EQ-01):  ", address(equityToken));
        console.log("");
        console.log("--- Shield ---");
        console.log("ShieldFactory:         ", address(shieldFactory));
        console.log("CDS #0:                ", cds);
        console.log("");
        console.log("=== FRONTEND .env.local ===");
        console.log("NEXT_PUBLIC_FORGE_FACTORY=", address(forgeFactory));
        console.log("NEXT_PUBLIC_SHIELD_FACTORY=", address(shieldFactory));
        console.log("NEXT_PUBLIC_NEXUS_HUB=", address(nexusHub));
        console.log("NEXT_PUBLIC_NEXUS_VAULT=", address(nexusVault));
        console.log("NEXT_PUBLIC_MOCK_USDC=", address(underlying));
        console.log("NEXT_PUBLIC_CREDIT_ORACLE=", address(creditOracle));
        console.log("NEXT_PUBLIC_COLLATERAL_ORACLE=", address(collateralOracle));
        console.log("NEXT_PUBLIC_SHIELD_PRICER=", address(pricer));
    }
}
