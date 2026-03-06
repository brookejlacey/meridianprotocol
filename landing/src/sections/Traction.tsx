"use client";

import FadeIn from "@/components/FadeIn";

const roadmap = [
  { text: "Tranched credit vaults with waterfall yield", done: true },
  { text: "Onchain CDS with AMM bonding curve pricing", done: true },
  { text: "Cross-chain margin engine via ICM/Teleporter", done: true },
  { text: "AI risk oracle + credit event detection", done: true },
  { text: "ERC4626 auto-compounding yield vaults", done: true },
  { text: "Atomic invest-and-hedge router (HedgeRouter)", done: true },
  { text: "Multi-pool routing + flash rebalancing", done: true },
  { text: "LP incentive gauge rewards", done: true },
  { text: "eERC encrypted positions (full ZK proofs)", done: false },
  { text: "Mainnet deployment + security audit", done: false },
];

export default function Traction() {
  return (
    <section id="traction" className="section relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#041f1a]/35 to-transparent pointer-events-none" />
      <div className="spinning-gradient" style={{ animationDuration: "40s", opacity: 0.7 }} />

      <div className="relative z-10 max-w-5xl mx-auto">
        <FadeIn>
          <p className="text-accent text-sm font-semibold uppercase tracking-widest mb-4 text-center">
            Progress
          </p>
          <h2 className="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight text-center mb-4 leading-tight">
            Built, tested, and<br className="hidden md:block" />
            <span className="gradient-text">deployed on Fuji</span>
          </h2>
          <p className="text-foreground/50 text-center text-lg max-w-2xl mx-auto mb-16">
            Not a whitepaper. Not a mockup. A working protocol with 35+ contracts, 692 tests,
            and a live frontend you can interact with today.
          </p>
        </FadeIn>

        {/* Roadmap */}
        <FadeIn delay={0.2}>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-2 max-w-3xl mx-auto mb-14">
            {roadmap.map((item, i) => (
              <div key={i} className="flex items-center gap-3 py-2">
                {item.done ? (
                  <div className="w-5 h-5 rounded-full bg-accent/10 border border-accent/30 flex items-center justify-center flex-shrink-0">
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <path d="M2.5 6 L5 8.5 L9.5 3.5" stroke="#00d4aa" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </div>
                ) : (
                  <div className="w-5 h-5 rounded-full border border-white/10 flex items-center justify-center flex-shrink-0">
                    <div className="w-1.5 h-1.5 rounded-full bg-muted" />
                  </div>
                )}
                <span className={`text-sm ${item.done ? "text-foreground/70" : "text-muted"}`}>
                  {item.text}
                </span>
              </div>
            ))}
          </div>
        </FadeIn>

        {/* CTA buttons */}
        <FadeIn delay={0.4}>
          <div className="flex flex-wrap items-center justify-center gap-4">
            <a
              href="https://app.meridianprotocol.xyz"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-accent text-black text-sm font-semibold hover:bg-accent/90 transition-all shadow-lg shadow-accent/20"
            >
              <span className="w-2 h-2 rounded-full bg-black/30" />
              Try the Live App
            </a>
            <a
              href="https://github.com/brookejlacey/meridianprotocol"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl border border-white/10 text-foreground/70 text-sm font-medium hover:border-white/20 hover:text-foreground transition-all"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
              </svg>
              View Source
            </a>
            <a
              href="https://subnets-test.avax.network/c-chain/address/0xD243eB302C08511743B0050cE77c02C80FeccCc8"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl border border-white/10 text-foreground/70 text-sm font-medium hover:border-white/20 hover:text-foreground transition-all"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M12 3 L21 18 H3 Z" strokeLinejoin="round" />
              </svg>
              Fuji Explorer
            </a>
          </div>
        </FadeIn>
      </div>
    </section>
  );
}
