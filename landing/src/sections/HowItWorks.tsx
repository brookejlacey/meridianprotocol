"use client";

import FadeIn from "@/components/FadeIn";

const steps = [
  {
    num: "01",
    title: "Create a Vault",
    description: "Originator deploys a ForgeVault with 3 tranches: Senior (safest, lowest return), Mezzanine (middle), Equity (riskiest, highest return). One transaction replaces months of coordination.",
    accent: "from-blue-500 to-cyan-400",
  },
  {
    num: "02",
    title: "Invest in Tranches",
    description: "Investors deposit USDC into their preferred risk tier. The vault mints tranche tokens representing their position in the waterfall priority.",
    accent: "from-green-500 to-emerald-400",
  },
  {
    num: "03",
    title: "Yield Distributes Automatically",
    description: "Anyone triggers the waterfall. Yield flows in strict priority: Senior first, then Mezzanine, then Equity gets the remainder. Enforced by smart contract.",
    accent: "from-yellow-500 to-amber-400",
  },
  {
    num: "04",
    title: "Hedge with CDS",
    description: "Buy credit protection on any vault via Shield's AMM pools. Bonding curve pricing auto-adjusts with demand. One click for a fully hedged position via HedgeRouter.",
    accent: "from-purple-500 to-pink-400",
  },
  {
    num: "05",
    title: "Manage Cross-Chain Margin",
    description: "Nexus unifies collateral across Avalanche L1s. Tranche tokens, AVAX, and L1 assets all count toward your margin position via ICM/Teleporter.",
    accent: "from-orange-500 to-red-400",
  },
  {
    num: "06",
    title: "AI Monitors Everything",
    description: "AI agents score vault risk, detect credit events, and automate operations. Every action has a timelock and governance veto. AI proposes, smart contracts enforce, humans can veto.",
    accent: "from-accent to-[#0088ff]",
  },
];

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="section relative overflow-hidden">
      {/* Shimmer + grid */}
      <div className="absolute inset-0 grid-bg opacity-70" />
      <div className="absolute inset-0 shimmer-bg" />
      <div className="relative z-10 max-w-5xl mx-auto">
        <FadeIn>
          <p className="text-accent text-sm font-semibold uppercase tracking-widest mb-4 text-center">
            How It Works
          </p>
          <h2 className="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight text-center mb-4 leading-tight">
            From vault to yield<br className="hidden md:block" />
            <span className="text-muted">in six onchain steps</span>
          </h2>
          <p className="text-foreground/50 text-center text-lg max-w-2xl mx-auto mb-16">
            Every step is an onchain transaction. Nothing happens offchain except AI inference.
          </p>
        </FadeIn>

        <div className="space-y-4">
          {steps.map((step, i) => (
            <FadeIn key={i} delay={0.05 + i * 0.05}>
              <div className="group flex gap-5 md:gap-8 p-5 md:p-6 rounded-2xl border border-white/5 bg-surface/50 hover:border-accent/15 transition-all">
                <div className={`flex-shrink-0 w-12 h-12 rounded-xl bg-gradient-to-br ${step.accent} flex items-center justify-center`}>
                  <span className="text-sm font-bold text-black">{step.num}</span>
                </div>
                <div>
                  <h3 className="text-lg font-bold mb-1">{step.title}</h3>
                  <p className="text-foreground/50 text-sm leading-relaxed">{step.description}</p>
                </div>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}
