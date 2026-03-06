"use client";

import FadeIn from "@/components/FadeIn";

const stats = [
  { value: "35+", label: "Smart Contracts" },
  { value: "692", label: "Tests Passing" },
  { value: "6", label: "Protocol Layers" },
  { value: "10K", label: "Fuzz Runs" },
  { value: "$13T", label: "Target Market" },
];

export default function Stats() {
  return (
    <section className="relative py-16 border-y border-white/5 bg-surface/50 overflow-hidden">
      <div className="absolute inset-0 dot-grid-bg" />
      <div className="relative z-10 max-w-6xl mx-auto px-6">
        <FadeIn direction="none">
          <div className="flex flex-wrap items-center justify-center gap-8 md:gap-16">
            {stats.map((stat) => (
              <div key={stat.label} className="text-center">
                <div className="text-2xl md:text-3xl font-bold text-accent">
                  {stat.value}
                </div>
                <div className="text-xs text-muted uppercase tracking-wider mt-1">
                  {stat.label}
                </div>
              </div>
            ))}
          </div>
        </FadeIn>
      </div>
    </section>
  );
}
