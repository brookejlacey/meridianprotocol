"use client";

import Link from "next/link";

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

const colorMap: Record<string, { border: string; bg: string; text: string; dot: string; gradient: string }> = {
  blue: {
    border: "border-[var(--accent)]/30",
    bg: "bg-[var(--accent)]/10",
    text: "text-[var(--accent)]",
    dot: "bg-blue-500",
    gradient: "from-blue-500 to-cyan-400",
  },
  emerald: {
    border: "border-emerald-500/30",
    bg: "bg-emerald-500/10",
    text: "text-emerald-400",
    dot: "bg-emerald-500",
    gradient: "from-emerald-500 to-teal-400",
  },
  purple: {
    border: "border-purple-500/30",
    bg: "bg-purple-500/10",
    text: "text-purple-400",
    dot: "bg-purple-500",
    gradient: "from-purple-500 to-pink-400",
  },
};

export default function Home() {
  return (
    <div className="pb-12">
      {/* ── Demo Walkthrough ── */}
      <section id="walkthrough" className="pt-20 pb-4 max-w-3xl mx-auto relative overflow-hidden">
        {/* Spinning gradient background */}
        <div className="spinning-gradient" style={{ animationDuration: "40s", opacity: 0.5 }} />
        <div className="orb" style={{ width: 400, height: 400, top: "-10%", left: "-10%", background: "rgba(0,212,170,0.2)" }} />
        <div className="orb" style={{ width: 300, height: 300, bottom: "5%", right: "-8%", background: "rgba(0,136,255,0.15)", animationDelay: "-8s" }} />
        <p className="relative z-10 text-center text-[var(--accent)] text-sm font-semibold uppercase tracking-widest mb-3">
          Demo Walkthrough
        </p>
        <h2 className="relative z-10 text-center text-3xl md:text-4xl font-bold tracking-tight mb-3">
          Follow the guided walkthrough
        </h2>
        <p className="relative z-10 text-center text-sm text-zinc-500 mb-10 max-w-lg mx-auto">
          Follow these steps to experience the full protocol. You&apos;ll need test AVAX for gas and MockUSDC (from our faucet) for transactions.
        </p>

        <div className="relative z-10 space-y-4">
          {walkthrough.map((item) => (
            <div
              key={item.step}
              className="group border border-zinc-800/80 rounded-2xl p-5 bg-zinc-900/30 hover:border-[var(--accent)]/30 hover:bg-zinc-900/60 transition-all duration-300"
            >
              <div className="flex items-start gap-4">
                <div
                  className="flex-shrink-0 w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold text-white"
                  style={{
                    background: "linear-gradient(135deg, #00d4aa 0%, #0088ff 100%)",
                  }}
                >
                  {item.step}
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-semibold text-white mb-1">{item.title}</h3>
                  <p className="text-sm text-zinc-400 mb-2">{item.description}</p>
                  <p className="text-xs text-zinc-600 italic">{item.highlight}</p>
                  {item.action && (
                    <Link
                      href={item.action.href}
                      className="inline-block mt-3 px-4 py-1.5 text-xs font-medium text-black bg-[var(--accent)] rounded-full hover:opacity-90 transition-all shadow-sm shadow-[var(--accent)]/20"
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

      {/* ── Protocol Architecture ── */}
      <section className="pt-20 pb-4 relative overflow-hidden">
        {/* Dot grid + radial pulse */}
        <div className="absolute inset-0 dot-grid-bg" />
        <div className="radial-pulse" />
        <div className="orb" style={{ width: 350, height: 350, top: "20%", right: "-12%", background: "rgba(0,212,170,0.18)", animationDelay: "-4s" }} />

        <div className="relative z-10">
          <p className="text-center text-[var(--accent)] text-sm font-semibold uppercase tracking-widest mb-3">
            Architecture
          </p>
          <h2 className="text-center text-3xl md:text-4xl font-bold tracking-tight mb-8">
            Protocol Architecture
          </h2>

          <div className="max-w-3xl mx-auto bg-zinc-900/60 border border-zinc-800 rounded-2xl p-6 font-mono text-sm text-zinc-400 backdrop-blur-sm">
            <div className="border border-zinc-700/60 rounded-xl p-3 mb-2 text-center hover:border-red-500/30 hover:shadow-[0_0_20px_rgba(239,68,68,0.05)] transition-all duration-300">
              <span className="text-red-400 font-semibold">AI LAYER</span>
              <span className="text-zinc-600"> | </span>
              RiskOracle | StrategyOptimizer | CreditDetector | Keeper
            </div>
            <div className="border border-zinc-700/60 rounded-xl p-3 mb-2 text-center hover:border-yellow-500/30 hover:shadow-[0_0_20px_rgba(234,179,8,0.05)] transition-all duration-300">
              <span className="text-yellow-400 font-semibold">YIELD LAYER</span>
              <span className="text-zinc-600"> | </span>
              YieldVault (ERC4626) | StrategyRouter | LPIncentiveGauge
            </div>
            <div className="border border-zinc-700/60 rounded-xl p-3 mb-2 text-center hover:border-orange-500/30 hover:shadow-[0_0_20px_rgba(249,115,22,0.05)] transition-all duration-300">
              <span className="text-orange-400 font-semibold">COMPOSABILITY LAYER</span>
              <span className="text-zinc-600"> | </span>
              HedgeRouter | PoolRouter | FlashRebalancer | LiqBot
            </div>
            <div className="grid grid-cols-3 gap-2">
              <div className="border border-[var(--accent)]/30 rounded-xl p-3 text-center hover:border-[var(--accent)]/60 hover:shadow-[0_0_20px_rgba(0,212,170,0.08)] transition-all duration-300">
                <div className="text-[var(--accent)] font-bold">FORGE</div>
                <div className="text-xs">Structured Credit</div>
              </div>
              <div className="border border-emerald-500/30 rounded-xl p-3 text-center hover:border-emerald-500/60 hover:shadow-[0_0_20px_rgba(16,185,129,0.08)] transition-all duration-300">
                <div className="text-emerald-400 font-bold">SHIELD</div>
                <div className="text-xs">Credit Default Swaps</div>
              </div>
              <div className="border border-purple-500/30 rounded-xl p-3 text-center hover:border-purple-500/60 hover:shadow-[0_0_20px_rgba(168,85,247,0.08)] transition-all duration-300">
                <div className="text-purple-400 font-bold">NEXUS</div>
                <div className="text-xs">Cross-Chain Margin</div>
              </div>
            </div>
            <div className="text-center mt-3 text-xs text-zinc-600">
              Avalanche C-Chain + L1 subnets via ICM/Teleporter
            </div>
          </div>
        </div>
      </section>

      {/* ── Core Protocol Layers ── */}
      <section className="pt-20 pb-4 relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#041f1a]/50 to-transparent pointer-events-none" />
        <div className="spinning-gradient" style={{ animationDuration: "35s", opacity: 0.4 }} />
        <div className="orb" style={{ width: 400, height: 400, bottom: "-15%", left: "-10%", background: "rgba(0,136,255,0.15)", animationDelay: "-10s" }} />
        <div className="orb" style={{ width: 300, height: 300, top: "10%", right: "-8%", background: "rgba(0,212,170,0.15)", animationDelay: "-15s" }} />

        <p className="relative z-10 text-center text-[var(--accent)] text-sm font-semibold uppercase tracking-widest mb-3">
          Core Layers
        </p>
        <h2 className="relative z-10 text-center text-3xl md:text-4xl font-bold tracking-tight mb-8">
          Core Protocol Layers
        </h2>

        <div className="relative z-10 grid grid-cols-1 md:grid-cols-3 gap-6">
          {layers.map((layer) => {
            const c = colorMap[layer.color];
            return (
              <Link
                key={layer.name}
                href={layer.href}
                className={`block border ${c.border} rounded-2xl overflow-hidden hover:shadow-lg transition-all duration-300 group`}
                style={{
                  background: "rgba(24,24,27,0.4)",
                }}
              >
                {/* Gradient accent bar */}
                <div
                  className={`h-1 bg-gradient-to-r ${c.gradient}`}
                />
                <div className="p-6">
                  <div className="flex items-center gap-2 mb-1">
                    <div className={`w-2.5 h-2.5 rounded-full ${c.dot}`} />
                    <h3 className={`text-lg font-bold ${c.text}`}>{layer.name}</h3>
                  </div>
                  <p className="text-xs text-zinc-500 mb-3">{layer.subtitle}</p>
                  <p className="text-sm text-zinc-400 mb-4 leading-relaxed">{layer.description}</p>
                  <ul className="space-y-2">
                    {layer.features.map((f) => (
                      <li key={f} className="text-xs text-zinc-500 flex items-center gap-2">
                        <span className={`w-1.5 h-1.5 rounded-full ${c.dot} opacity-60`} />
                        {f}
                      </li>
                    ))}
                  </ul>
                  <div className={`mt-5 text-xs font-medium ${c.text} opacity-0 group-hover:opacity-100 transition-opacity duration-300`}>
                    Explore {layer.name} &rarr;
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      </section>

      {/* ── Composability Grid ── */}
      <section className="pt-20 pb-4 relative overflow-hidden">
        <div className="absolute inset-0 shimmer-bg" />
        <div className="orb" style={{ width: 350, height: 350, top: "15%", left: "-10%", background: "rgba(0,212,170,0.15)", animationDelay: "-6s" }} />
        <div className="orb" style={{ width: 250, height: 250, bottom: "10%", right: "-6%", background: "rgba(0,136,255,0.12)", animationDelay: "-12s" }} />

        <p className="relative z-10 text-center text-[var(--accent)] text-sm font-semibold uppercase tracking-widest mb-3">
          Composability
        </p>
        <h2 className="relative z-10 text-center text-3xl md:text-4xl font-bold tracking-tight mb-8">
          Composability & Automation
        </h2>

        <div className="relative z-10 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {composability.map((item) => (
            <div
              key={item.name}
              className="border border-zinc-800/80 rounded-2xl p-5 bg-zinc-900/30 hover:border-[var(--accent)]/30 hover:bg-zinc-900/50 transition-all duration-300 group"
            >
              <div className="flex items-center gap-2 mb-2">
                <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)] opacity-60 group-hover:opacity-100 transition-opacity" />
                <h3 className="text-sm font-semibold text-zinc-200">{item.name}</h3>
              </div>
              <p className="text-xs text-zinc-500 leading-relaxed">{item.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ── Tech Stack ── */}
      <section className="text-center pt-20 pb-4 relative overflow-hidden">
        <div className="absolute inset-0 dot-grid-bg" style={{ opacity: 0.4 }} />
        <div className="orb" style={{ width: 300, height: 300, top: "-20%", right: "10%", background: "rgba(0,212,170,0.12)", animationDelay: "-3s" }} />

        <p className="relative z-10 text-center text-[var(--accent)] text-sm font-semibold uppercase tracking-widest mb-3">
          Technology
        </p>
        <h2 className="relative z-10 text-3xl md:text-4xl font-bold tracking-tight mb-8">
          Built With
        </h2>
        <div className="relative z-10 flex flex-wrap justify-center gap-3">
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
              className="px-4 py-1.5 text-xs rounded-full border border-zinc-800 text-zinc-400 hover:border-[var(--accent)]/40 hover:text-[var(--accent)] transition-all duration-300 cursor-default"
            >
              {tech}
            </span>
          ))}
        </div>
      </section>

      {/* ── Footer CTA ── */}
      <section className="text-center pt-20 pb-4 relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#041f1a]/30 to-transparent pointer-events-none" />
        <div className="orb" style={{ width: 350, height: 350, top: "0%", left: "20%", background: "rgba(0,212,170,0.12)", animationDelay: "-7s" }} />

        {/* Gradient separator */}
        <div
          className="h-px max-w-md mx-auto mb-10"
          style={{
            background: "linear-gradient(90deg, transparent, rgba(0,212,170,0.4), transparent)",
          }}
        />
        <p className="relative z-10 text-zinc-400 text-sm mb-6 max-w-md mx-auto leading-relaxed">
          Deployed on Avalanche Fuji Testnet. Connect your wallet to interact with live contracts.
        </p>
        <div className="relative z-10 flex flex-wrap justify-center gap-3">
          <Link
            href="/forge"
            className="px-6 py-2.5 bg-[var(--accent)] hover:opacity-90 text-black text-sm font-semibold rounded-xl transition-all shadow-lg shadow-[var(--accent)]/20 hover:shadow-[var(--accent)]/30 hover:scale-[1.02]"
          >
            Start with Forge
          </Link>
          <Link
            href="/pools"
            className="px-6 py-2.5 text-zinc-300 text-sm font-medium rounded-xl border border-white/10 hover:border-white/25 hover:bg-white/5 transition-all"
          >
            Explore CDS Pools
          </Link>
          <Link
            href="/strategies"
            className="px-6 py-2.5 text-zinc-300 text-sm font-medium rounded-xl border border-white/10 hover:border-white/25 hover:bg-white/5 transition-all"
          >
            Yield Strategies
          </Link>
        </div>
      </section>

    </div>
  );
}
