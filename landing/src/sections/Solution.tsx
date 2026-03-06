"use client";

import { useState } from "react";
import FadeIn from "@/components/FadeIn";

const layers = [
  {
    id: "forge",
    name: "Forge",
    label: "Structured Credit Vaults",
    color: "from-blue-500 to-cyan-400",
    description:
      "Create tranched credit vaults with automated waterfall yield distribution. Senior gets paid first, Equity absorbs losses. What takes 6+ intermediaries and months in tradfi happens in one transaction.",
    features: [
      "3-tranche waterfall: Senior, Mezzanine, Equity",
      "Automated yield distribution in priority order",
      "MasterChef-style O(1) gas claiming",
      "Configurable APR targets and allocation percentages",
    ],
    mockup: (
      <div className="p-5 rounded-xl border border-white/5 bg-white/[0.02]">
        <div className="flex items-center justify-between mb-4">
          <span className="text-sm font-semibold">Vault #0 / Waterfall Distribution</span>
          <span className="text-[10px] px-2 py-0.5 rounded bg-green-500/10 text-green-400 border border-green-500/20">Active</span>
        </div>
        <div className="space-y-3">
          {[
            { name: "Senior", pct: 70, apr: "5%", color: "bg-blue-500", tvl: "$1.0M" },
            { name: "Mezzanine", pct: 20, apr: "8%", color: "bg-yellow-500", tvl: "$500K" },
            { name: "Equity", pct: 10, apr: "15%+", color: "bg-red-500", tvl: "$200K" },
          ].map((t) => (
            <div key={t.name}>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-muted">{t.name} ({t.pct}%)</span>
                <span className="text-foreground/70">{t.tvl} @ {t.apr}</span>
              </div>
              <div className="h-2 bg-white/5 rounded-full overflow-hidden">
                <div className={`h-full ${t.color} rounded-full`} style={{ width: `${t.pct}%` }} />
              </div>
            </div>
          ))}
        </div>
        <div className="mt-4 pt-3 border-t border-white/5 flex items-center justify-between">
          <span className="text-xs text-muted">Total TVL: $1.7M</span>
          <div className="px-3 py-1.5 rounded-lg bg-accent/10 text-accent text-xs font-medium">Trigger Waterfall</div>
        </div>
      </div>
    ),
  },
  {
    id: "shield",
    name: "Shield",
    label: "Credit Default Swaps",
    color: "from-purple-500 to-pink-400",
    description:
      "The first onchain CDS protocol. Buy protection on any vault, sell protection to earn premiums. AMM pools with bonding curve pricing create natural supply/demand equilibrium. No order books needed.",
    features: [
      "Bilateral CDS + AMM pool models",
      "Bonding curve: spread = base + slope * u\u00B2 / (1-u)",
      "Oracle-triggered settlement with timelock",
      "Governance veto on false positive credit events",
    ],
    mockup: (
      <div className="p-5 rounded-xl border border-white/5 bg-white/[0.02]">
        <div className="flex items-center justify-between mb-4">
          <span className="text-sm font-semibold">CDS AMM Pool / Bonding Curve</span>
          <span className="text-[10px] px-2 py-0.5 rounded bg-purple-500/10 text-purple-400 border border-purple-500/20">Novel</span>
        </div>
        <div className="space-y-3">
          <div className="flex justify-between text-xs">
            <span className="text-muted">Utilization</span>
            <span className="text-foreground/70">42%</span>
          </div>
          <div className="h-3 bg-white/5 rounded-full overflow-hidden">
            <div className="h-full bg-gradient-to-r from-green-500 via-yellow-500 to-red-500 rounded-full" style={{ width: "42%" }} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="p-2.5 rounded-lg bg-white/[0.03]">
              <div className="text-[10px] text-muted">Current Spread</div>
              <div className="text-sm font-semibold text-accent">2.8%</div>
            </div>
            <div className="p-2.5 rounded-lg bg-white/[0.03]">
              <div className="text-[10px] text-muted">Total Liquidity</div>
              <div className="text-sm font-semibold">$800K</div>
            </div>
            <div className="p-2.5 rounded-lg bg-white/[0.03]">
              <div className="text-[10px] text-muted">Protection Sold</div>
              <div className="text-sm font-semibold">$336K</div>
            </div>
            <div className="p-2.5 rounded-lg bg-white/[0.03]">
              <div className="text-[10px] text-muted">LP Yield</div>
              <div className="text-sm font-semibold text-green-400">12.4%</div>
            </div>
          </div>
        </div>
      </div>
    ),
  },
  {
    id: "nexus",
    name: "Nexus",
    label: "Cross-Chain Margin",
    color: "from-orange-500 to-amber-400",
    description:
      "Unify collateral across Avalanche L1s with ICM/Teleporter. Tranche tokens, AVAX, and L1 assets count as one margin position. Automated liquidation at 110% health factor.",
    features: [
      "Cross-chain collateral attestations via ICM/Teleporter",
      "Unified margin across multiple Avalanche L1s",
      "Automated liquidation with configurable thresholds",
      "Tranche tokens accepted as collateral",
    ],
    mockup: (
      <div className="p-5 rounded-xl border border-white/5 bg-white/[0.02]">
        <div className="flex items-center justify-between mb-4">
          <span className="text-sm font-semibold">Margin Account</span>
          <span className="text-[10px] px-2 py-0.5 rounded bg-green-500/10 text-green-400 border border-green-500/20">Healthy</span>
        </div>
        <div className="space-y-3">
          <div className="flex justify-between items-center p-3 rounded-lg bg-white/[0.03]">
            <span className="text-xs text-muted">Health Factor</span>
            <span className="text-xl font-bold text-green-400">1.85</span>
          </div>
          <div className="space-y-2">
            {[
              { asset: "USDC (C-Chain)", amount: "$50,000", pct: 50 },
              { asset: "Senior Tranche", amount: "$30,000", pct: 30 },
              { asset: "AVAX (L1)", amount: "$20,000", pct: 20 },
            ].map((a) => (
              <div key={a.asset} className="flex items-center justify-between text-xs">
                <span className="text-muted">{a.asset}</span>
                <span className="text-foreground/70">{a.amount}</span>
              </div>
            ))}
          </div>
          <div className="pt-2 border-t border-white/5 flex justify-between text-xs">
            <span className="text-muted">Liquidation threshold</span>
            <span className="text-orange-400">110%</span>
          </div>
        </div>
      </div>
    ),
  },
];

export default function Solution() {
  const [activeTab, setActiveTab] = useState(0);
  const active = layers[activeTab];

  return (
    <section id="solution" className="section relative overflow-hidden">
      {/* Radial pulse + gradient wash */}
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#041f1a]/20 to-transparent pointer-events-none" />
      <div className="radial-pulse" />
      <div className="orb w-[400px] h-[400px] bg-accent/10 top-[10%] right-[-10%]" style={{ animationDelay: "-5s" }} />
      <div className="orb w-[300px] h-[300px] bg-[#0088ff]/10 bottom-[10%] left-[-8%]" style={{ animationDelay: "-12s" }} />

      <div className="relative z-10 max-w-6xl mx-auto">
        <FadeIn>
          <p className="text-accent text-sm font-semibold uppercase tracking-widest mb-4 text-center">
            The Solution
          </p>
          <h2 className="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight text-center mb-4 leading-tight">
            Three composable layers,<br className="hidden md:block" />
            <span className="gradient-text">one protocol</span>
          </h2>
          <p className="text-foreground/50 text-center text-lg max-w-2xl mx-auto mb-12">
            Each layer solves a gap no existing protocol covers. Together they form
            the complete infrastructure for institutional credit markets.
          </p>
        </FadeIn>

        {/* Tabs */}
        <FadeIn delay={0.2}>
          <div className="flex items-center justify-center gap-2 mb-10">
            {layers.map((layer, i) => (
              <button
                key={layer.id}
                onClick={() => setActiveTab(i)}
                className={`px-5 py-2.5 rounded-xl text-sm font-medium transition-all cursor-pointer ${
                  activeTab === i
                    ? "bg-accent/10 text-accent border border-accent/20"
                    : "text-muted hover:text-foreground border border-transparent hover:bg-white/5"
                }`}
              >
                {layer.name}
              </button>
            ))}
          </div>
        </FadeIn>

        {/* Content */}
        <FadeIn delay={0.3} key={active.id}>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">
            {/* Left: Description */}
            <div>
              <div className={`inline-flex px-3 py-1 rounded-full text-xs font-semibold bg-gradient-to-r ${active.color} text-black mb-4`}>
                {active.label}
              </div>
              <p className="text-foreground/70 text-base leading-relaxed mb-6">
                {active.description}
              </p>
              <ul className="space-y-3">
                {active.features.map((f, i) => (
                  <li key={i} className="flex items-start gap-3 text-sm text-foreground/60">
                    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" className="text-accent flex-shrink-0 mt-0.5">
                      <path d="M4 9 L7.5 12.5 L14 5.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    {f}
                  </li>
                ))}
              </ul>
            </div>

            {/* Right: Mockup */}
            <div className="float-gentle">
              {active.mockup}
            </div>
          </div>
        </FadeIn>
      </div>
    </section>
  );
}
