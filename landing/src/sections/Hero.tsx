"use client";

import FadeIn from "@/components/FadeIn";

export default function Hero() {
  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center overflow-hidden">
      {/* Gradient background */}
      <div className="absolute inset-0 bg-gradient-to-b from-[#041f1a] via-[#0a1e2e] to-[#0a0b0f]" />

      {/* Animated orbs */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="orb w-[600px] h-[600px] bg-accent/20 top-[-15%] left-[-10%]" style={{ animationDelay: "0s" }} />
        <div className="orb w-[500px] h-[500px] bg-accent/15 bottom-[-10%] right-[-5%]" style={{ animationDelay: "-7s" }} />
        <div className="orb w-[400px] h-[400px] bg-[#0066ff]/15 top-[30%] right-[15%]" style={{ animationDelay: "-13s" }} />
      </div>

      {/* Grid overlay */}
      <div className="absolute inset-0 grid-bg opacity-80" />

      {/* Content */}
      <div className="relative z-10 text-center max-w-5xl px-6 pt-24 pb-16">
        <FadeIn delay={0.1} duration={0.8}>
          <div className="inline-flex items-center gap-2 px-4 py-1.5 mb-8 rounded-full border border-accent/20 bg-accent/5 text-sm">
            <span className="w-2 h-2 rounded-full bg-accent animate-pulse" />
            <span className="text-accent font-medium">Live on Avalanche Fuji Testnet</span>
          </div>
        </FadeIn>

        <FadeIn delay={0.2} duration={0.8}>
          <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold tracking-[-0.03em] leading-[0.95] mb-6">
            The credit market{" "}
            <span className="gradient-text">infrastructure</span>{" "}
            layer for DeFi
          </h1>
        </FadeIn>

        <FadeIn delay={0.4} duration={0.8}>
          <p className="text-lg md:text-xl text-foreground/60 max-w-2xl mx-auto mb-10 leading-relaxed">
            Structured credit vaults, credit default swaps with AMM pricing,
            and cross-chain margin. Composable smart contracts bringing the
            $13 trillion credit market onchain.
          </p>
        </FadeIn>

        <FadeIn delay={0.6} duration={0.6}>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a
              href="https://app.meridianprotocol.xyz"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-3.5 text-base font-semibold bg-accent text-black rounded-xl hover:bg-accent/90 transition-all shadow-lg shadow-accent/20 hover:shadow-accent/30 hover:scale-[1.02]"
            >
              Launch App
            </a>
            <a
              href="#how-it-works"
              className="px-8 py-3.5 text-base font-medium text-foreground/80 rounded-xl border border-white/10 hover:border-white/25 hover:bg-white/5 transition-all"
            >
              See How It Works
            </a>
          </div>
        </FadeIn>
      </div>

      {/* Floating app mockup */}
      <FadeIn delay={0.8} duration={1}>
        <div className="relative z-10 w-full max-w-4xl mx-auto px-6 pb-12">
          <div className="float-gentle rounded-2xl border border-white/10 bg-[#0a0b0f]/80 backdrop-blur-xl shadow-2xl shadow-black/50 overflow-hidden">
            {/* Browser chrome */}
            <div className="flex items-center gap-2 px-4 py-3 border-b border-white/5 bg-white/[0.02]">
              <div className="flex gap-1.5">
                <div className="w-3 h-3 rounded-full bg-white/10" />
                <div className="w-3 h-3 rounded-full bg-white/10" />
                <div className="w-3 h-3 rounded-full bg-white/10" />
              </div>
              <div className="flex-1 mx-4">
                <div className="max-w-md mx-auto px-4 py-1.5 rounded-lg bg-white/5 text-xs text-muted text-center">
                  app.meridianprotocol.xyz
                </div>
              </div>
            </div>
            {/* App content mockup */}
            <div className="p-6 space-y-4">
              {/* Header bar mockup */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-accent to-[#0088ff]" />
                  <span className="text-sm font-semibold">Meridian Protocol</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="px-3 py-1 rounded-full bg-green-500/10 text-green-400 text-xs border border-green-500/20">Fuji</div>
                  <div className="px-3 py-1.5 rounded-lg bg-white/5 text-xs text-muted">0xD243...cCc8</div>
                </div>
              </div>
              {/* Nav tabs mockup */}
              <div className="flex gap-1 border-b border-white/5 pb-2">
                {["Forge", "Shield", "Pools", "Nexus", "Analytics"].map((t, i) => (
                  <div key={t} className={`px-3 py-1.5 rounded-md text-xs ${i === 0 ? "bg-accent/10 text-accent font-medium" : "text-muted"}`}>{t}</div>
                ))}
              </div>
              {/* Vault grid mockup */}
              <div className="grid grid-cols-3 gap-3">
                {[
                  { name: "Vault #0", tvl: "$1.7M", status: "Active", apr: "5-15%" },
                  { name: "Vault #1", tvl: "$5.2M", status: "Active", apr: "4-20%" },
                  { name: "Vault #2", tvl: "$850K", status: "Active", apr: "6-25%" },
                ].map((v) => (
                  <div key={v.name} className="p-3 rounded-xl border border-white/5 bg-white/[0.02]">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-medium text-muted">{v.name}</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-green-500/10 text-green-400">{v.status}</span>
                    </div>
                    <div className="text-lg font-bold mb-1">{v.tvl}</div>
                    <div className="text-[10px] text-muted">APR range: {v.apr}</div>
                    {/* Mini tranche bars */}
                    <div className="flex gap-0.5 mt-2 h-1.5 rounded-full overflow-hidden">
                      <div className="bg-blue-500 flex-[7]" />
                      <div className="bg-yellow-500 flex-[2]" />
                      <div className="bg-red-500 flex-1" />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </FadeIn>
    </section>
  );
}
