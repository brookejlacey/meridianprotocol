import { type Address } from "viem";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

function env(key: string): Address {
  return (process.env[key] || ZERO) as Address;
}

export const CHAIN_ID = 43113; // Avalanche Fuji

// --- Core Factories ---
export const FORGE_FACTORY = env("NEXT_PUBLIC_FORGE_FACTORY");
export const SHIELD_FACTORY = env("NEXT_PUBLIC_SHIELD_FACTORY");
export const CDS_POOL_FACTORY = env("NEXT_PUBLIC_CDS_POOL_FACTORY");
export const NEXUS_HUB = env("NEXT_PUBLIC_NEXUS_HUB");
export const NEXUS_VAULT = env("NEXT_PUBLIC_NEXUS_VAULT");

// --- Tokens ---
export const MOCK_USDC = env("NEXT_PUBLIC_MOCK_USDC");

// --- Routers & Composability ---
export const HEDGE_ROUTER = env("NEXT_PUBLIC_HEDGE_ROUTER");
export const POOL_ROUTER = env("NEXT_PUBLIC_POOL_ROUTER");
export const FLASH_REBALANCER = env("NEXT_PUBLIC_FLASH_REBALANCER");
export const LIQUIDATION_BOT = env("NEXT_PUBLIC_LIQUIDATION_BOT");

// --- Yield ---
export const YIELD_VAULT_FACTORY = env("NEXT_PUBLIC_YIELD_VAULT_FACTORY");
export const STRATEGY_ROUTER = env("NEXT_PUBLIC_STRATEGY_ROUTER");
export const LP_GAUGE = env("NEXT_PUBLIC_LP_GAUGE");

// --- Oracles ---
export const CREDIT_ORACLE = env("NEXT_PUBLIC_CREDIT_ORACLE");
export const COLLATERAL_ORACLE = env("NEXT_PUBLIC_COLLATERAL_ORACLE");
export const SHIELD_PRICER = env("NEXT_PUBLIC_SHIELD_PRICER");

// --- Backwards-compatible accessor ---
type ContractAddresses = {
  forgeFactory: Address;
  shieldFactory: Address;
  cdsPoolFactory: Address;
  nexusHub: Address;
  nexusVault: Address;
};

export function getAddresses(): ContractAddresses {
  return {
    forgeFactory: FORGE_FACTORY,
    shieldFactory: SHIELD_FACTORY,
    cdsPoolFactory: CDS_POOL_FACTORY,
    nexusHub: NEXUS_HUB,
    nexusVault: NEXUS_VAULT,
  };
}
