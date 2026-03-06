"use client";

import FadeIn from "@/components/FadeIn";

const problems = [
  {
    stat: "6+",
    label: "intermediaries per deal",
    description:
      "A single tokenized CLO needs originators, trustees, rating agencies, servicers, custodians, and lawyers. Takes months to close.",
  },
  {
    stat: "Zero",
    label: "onchain CDS markets",
    description:
      "Credit default swaps don't exist in DeFi. There is no way to hedge structured credit risk onchain.",
  },
  {
    stat: "$100M+",
    label: "minimum investment",
    description:
      "Traditional structured credit is inaccessible. High minimums, opaque pricing, and zero composability with DeFi.",
  },
];

const competitors = [
  { name: "Aave / Compound", gap: "Lending only, no tranching or risk segmentation" },
  { name: "Uniswap / Curve", gap: "Spot swaps only, can't price credit derivatives" },
  { name: "Traditional CLOs", gap: "Months to close, 6+ intermediaries, no composability" },
  { name: "Galaxy Digital", gap: "One-off $75M deal, not repeatable infrastructure" },
];

export default function Problem() {
  return (
    <section id="problem" className="section relative overflow-hidden">
      {/* Slow spinning gradient */}
      <div className="spinning-gradient" style={{ opacity: 0.9 }} />
      <div className="relative z-10 max-w-6xl mx-auto">
        <FadeIn>
          <p className="text-accent text-sm font-semibold uppercase tracking-widest mb-4 text-center">
            The Problem
          </p>
          <h2 className="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight text-center mb-4 leading-tight">
            $13 trillion in structured credit,<br className="hidden md:block" />
            <span className="text-muted">zero onchain infrastructure</span>
          </h2>
          <p className="text-foreground/50 text-center text-lg max-w-2xl mx-auto mb-16">
            Banks bundle loans, slice them into risk layers, and sell them. But the
            entire process runs on phone calls, paper contracts, and weeks of settlement.
          </p>
        </FadeIn>

        {/* Problem cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16">
          {problems.map((p, i) => (
            <FadeIn key={i} delay={0.1 + i * 0.1}>
              <div className="p-6 rounded-2xl border border-white/5 bg-surface/60 hover:border-accent/15 transition-all h-full">
                <div className="text-4xl font-bold text-accent mb-1">{p.stat}</div>
                <div className="text-sm text-accent/70 font-medium uppercase tracking-wide mb-3">
                  {p.label}
                </div>
                <p className="text-foreground/60 text-sm leading-relaxed">
                  {p.description}
                </p>
              </div>
            </FadeIn>
          ))}
        </div>

        {/* Competitor grid */}
        <FadeIn delay={0.4}>
          <div className="rounded-2xl border border-white/5 bg-surface/40 p-6 md:p-8">
            <p className="text-xs text-accent font-semibold uppercase tracking-widest mb-6">
              Why existing solutions fall short
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {competitors.map((c, i) => (
                <div key={i} className="flex items-start gap-3 p-3 rounded-xl bg-white/[0.02]">
                  <div className="w-5 h-5 rounded-full border border-red-500/30 bg-red-500/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                      <path d="M2.5 2.5 L7.5 7.5 M7.5 2.5 L2.5 7.5" stroke="#ef4444" strokeWidth="1.5" strokeLinecap="round" />
                    </svg>
                  </div>
                  <div>
                    <span className="text-sm font-semibold">{c.name}</span>
                    <p className="text-xs text-foreground/50 mt-0.5">{c.gap}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </FadeIn>
      </div>
    </section>
  );
}
