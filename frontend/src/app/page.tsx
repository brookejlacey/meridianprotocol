"use client";

import Link from "next/link";

const stats = [
  { label: "Smart Contracts", value: "35+" },
  { label: "Tests Passing", value: "692" },
  { label: "Protocol Layers", value: "6" },
  { label: "Fuzz Runs", value: "10,000" },
];

const layers = [
  {
    name: "Forge",
    subtitle: "Structured Credit",
    href: "/forge",
    description:
      "Institutional-grade credit vaults with senior/mezzanine/equity tranches. Waterfall yield distribution prioritizes senior holders. Invest, earn, and withdraw with full tranche isolation.",
    features: ["Senior/Mezz/Equity tranches", "Waterfall yield distribution", "Pull-based yield claiming"],
    color: "blue",
  },
  {
    name: "Shield",
    subtitle: "Credit Default Swaps",
    href: "/shield",
    description:
      "Hedge credit risk with bilateral OTC swaps or trade on bonding-curve AMM pools. Automated premium streaming, oracle-triggered settlements, and multi-pool routing.",
    features: ["Bonding curve AMM pricing", "Oracle-triggered settlement", "Multi-pool routing (PoolRouter)"],
    color: "emerald",
  },
  {
    name: "Nexus",
    subtitle: "Cross-Chain Margin",
    href: "/nexus",
    description:
      "Unified margin engine across Avalanche L1s via ICM/Teleporter. Multi-asset collateral with risk-weighted pricing, cross-chain balance attestations, and permissionless liquidation.",
    features: ["Multi-asset collateral", "Cross-chain attestations", "Permissionless liquidation"],
    color: "purple",
  },
];

const composability = [
  {
    name: "HedgeRouter",
    description: "Atomic invest-and-hedge in a single transaction",
  },
  {
    name: "FlashRebalancer",
    description: "Flash-loan-powered cross-tranche position rebalancing",
  },
  {
    name: "PoolRouter",
    description: "Greedy cheapest-first fill across multiple CDS pools",
  },
  {
    name: "LiquidationBot",
    description: "Full waterfall keeper: oracle > trigger > settle > liquidate",
  },
  {
    name: "YieldVault",
    description: "ERC4626 auto-compounding wrappers for tranche tokens",
  },
  {
    name: "StrategyRouter",
    description: "Multi-vault yield optimization with BPS allocations",
  },
];

const walkthrough = [
  {
    step: 1,
    title: "Connect Your Wallet",
    description: "Click the Connect button in the top-right corner. Select your wallet (MetaMask, etc.) and connect to the Avalanche Fuji testnet.",
    action: null,
    highlight: "Make sure you're on Fuji (chain ID 43113). The app will prompt you to switch if needed.",
  },
  {
    step: 2,
    title: "Get Test USDC",
    description: "Click the green \"Faucet 100k USDC\" button in the header. This mints 100,000 MockUSDC to your wallet for testing.",
    action: null,
    highlight: "You can click Faucet multiple times. You'll also need test AVAX for gas. Get it from the Avalanche Fuji faucet.",
  },
  {
    step: 3,
    title: "Invest in a Structured Credit Vault",
    description: "Navigate to Forge and click Vault #0. Choose a tranche (Senior at 5% APR, Mezzanine at 8%, or Equity at 15%), enter an amount, approve USDC, and invest.",
    action: { label: "Go to Forge", href: "/forge" },
    highlight: "Senior gets paid first (lowest risk), Equity gets paid last but earns the highest yield.",
  },
  {
    step: 4,
    title: "Trigger Waterfall & Claim Yield",
    description: "On the vault detail page, click \"Trigger Waterfall Distribution\" to distribute accrued yield. Then click \"Claim\" on your tranche to collect earnings.",
    action: { label: "View Vault #0", href: "/forge/0" },
    highlight: "Waterfall pays Senior first, then Mezzanine, then Equity, mimicking real-world structured credit.",
  },
  {
    step: 5,
    title: "Explore Credit Default Swaps",
    description: "Go to Shield to see active CDS contracts. View the contract details to see buyer/seller positions, collateral posted, and premium payments.",
    action: { label: "Go to Shield", href: "/shield" },
    highlight: "CDS contracts let you buy or sell credit protection on structured credit vaults.",
  },
  {
    step: 6,
    title: "Browse CDS AMM Pools",
    description: "Visit Pools to see bonding-curve-priced AMM pools. View utilization rates, current spreads, and provide liquidity to earn premium yield.",
    action: { label: "Go to Pools", href: "/pools" },
    highlight: "Spread increases as utilization rises. The bonding curve creates natural supply/demand equilibrium.",
  },
  {
    step: 7,
    title: "Open a Cross-Chain Margin Account",
    description: "Go to Nexus and click \"Open Margin Account\". Then deposit collateral to see your health factor, collateral breakdown, and liquidation threshold.",
    action: { label: "Go to Nexus", href: "/nexus" },
    highlight: "Nexus unifies collateral across Avalanche L1s via ICM/Teleporter for capital efficiency.",
  },
  {
    step: 8,
    title: "View Protocol Analytics",
    description: "Check the Analytics dashboard for protocol-wide metrics: total TVL, yield generated, tranche capital distribution, CDS pool breakdown, and key rates.",
    action: { label: "View Analytics", href: "/analytics" },
    highlight: "Analytics aggregates data across all Forge vaults, Shield CDS contracts, and AMM pools.",
  },
];

const colorMap: Record<string, { border: string; bg: string; text: string; dot: string }> = {
  blue: {
    border: "border-[var(--accent)]/30",
    bg: "bg-[var(--accent)]/10",
    text: "text-[var(--accent)]",
    dot: "bg-blue-500",
  },
  emerald: {
    border: "border-emerald-500/30",
    bg: "bg-emerald-500/10",
    text: "text-emerald-400",
    dot: "bg-emerald-500",
  },
  purple: {
    border: "border-purple-500/30",
    bg: "bg-purple-500/10",
    text: "text-purple-400",
    dot: "bg-purple-500",
  },
};

export default function Home() {
  return (
    <div className="space-y-16 pb-12">
      {/* Hero */}
      <section className="text-center pt-8">
        <h1 className="text-4xl font-bold tracking-tight mb-3">
          Meridian Protocol
        </h1>
        <p className="text-lg text-zinc-400 max-w-2xl mx-auto mb-2">
          Onchain institutional credit infrastructure on Avalanche
        </p>
        <p className="text-sm text-zinc-500 max-w-xl mx-auto mb-8">
          Structured credit vaults, credit default swap AMMs, and cross-chain margin, composed into a unified protocol with atomic operations, auto-compounding yield, and permissionless liquidation.
        </p>

        {/* Stats bar */}
        <div className="flex justify-center gap-8 mb-8">
          {stats.map((stat) => (
            <div key={stat.label} className="text-center">
              <div className="text-2xl font-bold text-white">{stat.value}</div>
              <div className="text-xs text-zinc-500">{stat.label}</div>
            </div>
          ))}
        </div>

        <div className="flex justify-center gap-3">
          <Link
            href="/forge"
            className="px-5 py-2.5 bg-[var(--accent)] hover:bg-[var(--accent-hover)] text-white text-sm font-medium rounded-lg transition-colors"
          >
            Launch App
          </Link>
          <a
            href="#walkthrough"
            className="px-5 py-2.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-sm font-medium rounded-lg border border-zinc-700 transition-colors"
          >
            Demo Walkthrough
          </a>
        </div>
      </section>

      {/* Demo Walkthrough */}
      <section id="walkthrough">
        <h2 className="text-center text-sm font-medium text-zinc-500 uppercase tracking-wider mb-2">
          Demo Walkthrough
        </h2>
        <p className="text-center text-sm text-zinc-500 mb-8 max-w-lg mx-auto">
          Follow these steps to experience the full protocol. You&apos;ll need test AVAX for gas and MockUSDC (from our faucet) for transactions.
        </p>
        <div className="max-w-2xl mx-auto space-y-4">
          {walkthrough.map((item) => (
            <div
              key={item.step}
              className="border border-zinc-800 rounded-lg p-5 bg-zinc-900/30 hover:bg-zinc-900/60 transition-colors"
            >
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-[var(--accent)]/20 border border-[var(--accent)]/30 flex items-center justify-center text-sm font-bold text-[var(--accent)]">
                  {item.step}
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-semibold text-white mb-1">{item.title}</h3>
                  <p className="text-sm text-zinc-400 mb-2">{item.description}</p>
                  <p className="text-xs text-zinc-600 italic">{item.highlight}</p>
                  {item.action && (
                    <Link
                      href={item.action.href}
                      className="inline-block mt-3 px-3 py-1.5 text-xs font-medium text-[var(--accent)] bg-[var(--accent)]/10 border border-[var(--accent)]/20 rounded hover:bg-[var(--accent-hover)]/20 transition-colors"
                    >
                      {item.action.label} &rarr;
                    </Link>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Architecture */}
      <section>
        <h2 className="text-center text-sm font-medium text-zinc-500 uppercase tracking-wider mb-6">
          Protocol Architecture
        </h2>
        <div className="max-w-3xl mx-auto bg-zinc-900/50 border border-zinc-800 rounded-xl p-6 font-mono text-sm text-zinc-400">
          <div className="border border-zinc-700 rounded-lg p-3 mb-2 text-center">
            <span className="text-red-400">AI LAYER</span>
            <span className="text-zinc-600"> | </span>
            RiskOracle | StrategyOptimizer | CreditDetector | Keeper
          </div>
          <div className="border border-zinc-700 rounded-lg p-3 mb-2 text-center">
            <span className="text-yellow-400">YIELD LAYER</span>
            <span className="text-zinc-600"> | </span>
            YieldVault (ERC4626) | StrategyRouter | LPIncentiveGauge
          </div>
          <div className="border border-zinc-700 rounded-lg p-3 mb-2 text-center">
            <span className="text-orange-400">COMPOSABILITY LAYER</span>
            <span className="text-zinc-600"> | </span>
            HedgeRouter | PoolRouter | FlashRebalancer | LiqBot
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="border border-[var(--accent)]/30 rounded-lg p-3 text-center">
              <div className="text-[var(--accent)] font-bold">FORGE</div>
              <div className="text-xs">Structured Credit</div>
            </div>
            <div className="border border-emerald-500/30 rounded-lg p-3 text-center">
              <div className="text-emerald-400 font-bold">SHIELD</div>
              <div className="text-xs">Credit Default Swaps</div>
            </div>
            <div className="border border-purple-500/30 rounded-lg p-3 text-center">
              <div className="text-purple-400 font-bold">NEXUS</div>
              <div className="text-xs">Cross-Chain Margin</div>
            </div>
          </div>
          <div className="text-center mt-3 text-xs text-zinc-600">
            Avalanche C-Chain + L1 subnets via ICM/Teleporter
          </div>
        </div>
      </section>

      {/* Core Layers */}
      <section>
        <h2 className="text-center text-sm font-medium text-zinc-500 uppercase tracking-wider mb-6">
          Core Protocol Layers
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {layers.map((layer) => {
            const c = colorMap[layer.color];
            return (
              <Link
                key={layer.name}
                href={layer.href}
                className={`block border ${c.border} rounded-xl p-6 hover:bg-zinc-900/50 transition-colors group`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <div className={`w-2 h-2 rounded-full ${c.dot}`} />
                  <h3 className={`text-lg font-bold ${c.text}`}>{layer.name}</h3>
                </div>
                <p className="text-xs text-zinc-500 mb-3">{layer.subtitle}</p>
                <p className="text-sm text-zinc-400 mb-4">{layer.description}</p>
                <ul className="space-y-1.5">
                  {layer.features.map((f) => (
                    <li key={f} className="text-xs text-zinc-500 flex items-center gap-2">
                      <span className={`w-1 h-1 rounded-full ${c.dot} opacity-60`} />
                      {f}
                    </li>
                  ))}
                </ul>
                <div className={`mt-4 text-xs ${c.text} opacity-0 group-hover:opacity-100 transition-opacity`}>
                  Explore {layer.name} &rarr;
                </div>
              </Link>
            );
          })}
        </div>
      </section>

      {/* Composability Grid */}
      <section>
        <h2 className="text-center text-sm font-medium text-zinc-500 uppercase tracking-wider mb-6">
          Composability & Automation
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {composability.map((item) => (
            <div
              key={item.name}
              className="border border-zinc-800 rounded-lg p-4 bg-zinc-900/30"
            >
              <h3 className="text-sm font-semibold text-zinc-200 mb-1">{item.name}</h3>
              <p className="text-xs text-zinc-500">{item.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Tech Stack */}
      <section className="text-center">
        <h2 className="text-sm font-medium text-zinc-500 uppercase tracking-wider mb-4">
          Built With
        </h2>
        <div className="flex flex-wrap justify-center gap-3">
          {[
            "Solidity 0.8.27",
            "Foundry",
            "OpenZeppelin v5",
            "Avalanche ICM",
            "Next.js 15",
            "wagmi/viem",
            "RainbowKit",
            "Ponder Indexer",
            "ERC4626",
            "Claude AI",
          ].map((tech) => (
            <span
              key={tech}
              className="px-3 py-1 text-xs rounded-full border border-zinc-800 text-zinc-400"
            >
              {tech}
            </span>
          ))}
        </div>
      </section>

      {/* Footer CTA */}
      <section className="text-center border-t border-zinc-800 pt-8">
        <p className="text-zinc-500 text-sm mb-4">
          Deployed on Avalanche Fuji Testnet. Connect your wallet to interact with live contracts.
        </p>
        <div className="flex justify-center gap-3">
          <Link
            href="/forge"
            className="px-4 py-2 bg-[var(--accent)] hover:bg-[var(--accent-hover)] text-white text-sm font-medium rounded-lg transition-colors"
          >
            Start with Forge
          </Link>
          <Link
            href="/pools"
            className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-sm font-medium rounded-lg border border-zinc-700 transition-colors"
          >
            Explore CDS Pools
          </Link>
          <Link
            href="/strategies"
            className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-sm font-medium rounded-lg border border-zinc-700 transition-colors"
          >
            Yield Strategies
          </Link>
        </div>
      </section>
    </div>
  );
}
