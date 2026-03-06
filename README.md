# Meridian Protocol

Onchain institutional credit infrastructure on Avalanche. Six composable protocol layers spanning structured credit, credit default swaps, cross-chain margin, and AI-driven risk management — 35+ contracts, 692 tests, deployed on Fuji testnet.
https://meridianprotocol.xyz

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      AI LAYER                           │
│  AIRiskOracle │ AIStrategyOptimizer │ AIKeeper │ Detector│
├─────────────────────────────────────────────────────────┤
│                    YIELD LAYER                          │
│  YieldVault (ERC4626) │ StrategyRouter │ LPIncentiveGauge│
├─────────────────────────────────────────────────────────┤
│                 COMPOSABILITY LAYER                     │
│  HedgeRouter │ PoolRouter │ FlashRebalancer │ LiqBot    │
├─────────────────────────────────────────────────────────┤
│     FORGE          │     SHIELD       │     NEXUS       │
│  Structured Credit │  Credit Default  │  Cross-Chain    │
│  Vaults + Tranches │  Swaps + AMM     │  Margin Engine  │
└─────────────────────────────────────────────────────────┘
                         │
                    Avalanche C-Chain
                    (+ L1 subnets via ICM)
```

**Forge** — Structured credit vaults with senior/mezzanine/equity tranches and waterfall yield distribution

**Shield** — Credit default swaps: bilateral OTC contracts and an AMM with bonding-curve pricing

**Nexus** — Cross-chain margin engine with multi-asset collateral and liquidation via Avalanche ICM

**Composability** — HedgeRouter, PoolRouter, FlashRebalancer, and LiquidationBot for atomic multi-protocol operations

**Yield** — ERC4626 auto-compounding vaults, multi-strategy router, and Synthetix-style LP incentive gauges

**AI** — Risk oracle, strategy optimizer, keeper, and credit event detector with circuit breakers, timelocks, and governance veto

## Getting Started

### Smart Contracts

```bash
forge build
forge test                                    # 692 tests, 10k fuzz runs
forge script script/Demo.s.sol -vv            # 12-step E2E walkthrough
```

### Frontend (Next.js + wagmi)

```bash
cd frontend && npm install && npm run dev     # localhost:3000
```

### Indexer (Ponder)

```bash
cd indexer && pnpm install && pnpm dev        # localhost:42069
```

### Deploy to Fuji

```bash
forge script script/DeployFuji.s.sol --rpc-url fuji --broadcast
```

Requires `.env` with `DEPLOYER_PRIVATE_KEY`.

## Deployed Contracts (Fuji)

| Contract | Address |
|----------|---------|
| ForgeFactory | `0x52614038F825FbA5BE78ECf3eA0e3e0b21961d29` |
| ShieldFactory | `0x9A9e51c6A91573dEFf7657baB7570EF4888Aaa3A` |
| NexusHub | `0xE6bb9535bd754A993dc04E83279f92980F7ad9F4` |
| HedgeRouter | `0x736fE313dEff821b71d1c2334DA95cC0eFf0B98c` |
| CDSPoolFactory | `0xEc82dd21231dAcbA07f1C4F06B84Cf7bc6b4C24c` |
| YieldVaultFactory | `0x2F08A87D18298dF9A795a941cf493a602a9ea68C` |
| MockUSDC | `0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f` |

Chain: Avalanche Fuji (43113) · Deployer: `0xD243eB302C08511743B0050cE77c02C80FeccCc8`

## Stack

Solidity 0.8.27 · Foundry · Next.js · wagmi/viem · Ponder · OpenZeppelin
