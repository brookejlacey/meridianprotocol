"use client";

const strategies = [
  {
    name: "Conservative Senior",
    apy: "~4.5%",
    allocations: [
      { label: "Senior Vault #0", pct: 60, color: "from-green-500 to-emerald-500" },
      { label: "Senior Vault #1", pct: 40, color: "from-green-600 to-emerald-600" },
    ],
  },
  {
    name: "Balanced Growth",
    apy: "~8.2%",
    allocations: [
      { label: "Mezz Vault #0", pct: 40, color: "from-amber-500 to-yellow-500" },
      { label: "Mezz Vault #1", pct: 30, color: "from-amber-600 to-yellow-600" },
      { label: "Senior Vault #2", pct: 30, color: "from-green-500 to-emerald-500" },
    ],
  },
  {
    name: "High Yield Alpha",
    apy: "~14.8%",
    allocations: [
      { label: "Equity Vault #0", pct: 50, color: "from-rose-500 to-pink-500" },
      { label: "Equity Vault #1", pct: 30, color: "from-rose-600 to-pink-600" },
      { label: "Mezz Vault #2", pct: 20, color: "from-amber-500 to-yellow-500" },
    ],
  },
];

export default function StrategiesPage() {
  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h2 className="text-lg font-medium">Yield Strategies</h2>
        <p className="text-sm text-zinc-500">
          Auto-compounding vaults with multi-tranche allocation strategies
        </p>
      </div>

      {/* Strategies Grid */}
      <div>
        <h3 className="text-sm font-medium text-zinc-400 mb-3">
          Available Strategies ({strategies.length})
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {strategies.map((s) => (
            <div
              key={s.name}
              className="group relative bg-[var(--card-bg)] border border-[var(--card-border)] rounded-2xl overflow-hidden transition-shadow hover:shadow-[0_0_24px_rgba(16,185,129,0.08)]"
            >
              {/* Gradient accent bar */}
              <div className="h-1 w-full bg-gradient-to-r from-green-500 to-emerald-500" />

              <div className="p-5 space-y-4">
                {/* Title row */}
                <div className="flex items-center justify-between">
                  <h3 className="font-medium">{s.name}</h3>
                  <span className="text-xs px-2 py-0.5 rounded bg-green-900/50 text-green-400">
                    Active
                  </span>
                </div>

                {/* Projected APY */}
                <div className="text-center py-2">
                  <p className="text-xs uppercase tracking-wider text-zinc-500 mb-1">Projected APY</p>
                  <p className="text-2xl font-bold text-green-400">{s.apy}</p>
                </div>

                {/* Allocation bars */}
                <div className="space-y-3">
                  {s.allocations.map((a) => (
                    <div key={a.label}>
                      <div className="flex items-center justify-between text-sm mb-1">
                        <span className="text-zinc-400">{a.label}</span>
                        <span className="text-zinc-300 font-medium">{a.pct}%</span>
                      </div>
                      <div className="w-full h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                        <div
                          className={`h-full bg-gradient-to-r ${a.color} rounded-full`}
                          style={{ width: `${a.pct}%` }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Info Box */}
      <div className="bg-zinc-900/50 border border-zinc-800 rounded-2xl p-4 text-sm text-zinc-400">
        <p className="font-medium text-zinc-300 mb-2">How Yield Strategies Work</p>
        <ul className="space-y-1 list-disc list-inside">
          <li>Each YieldVault wraps a ForgeVault tranche with ERC-4626 auto-compounding</li>
          <li>Strategies split capital across multiple YieldVaults by BPS allocation</li>
          <li>Keepers call <code className="text-zinc-300">compound()</code> to harvest and reinvest yield</li>
          <li>Rebalance between strategies anytime without closing your position</li>
        </ul>
      </div>
    </div>
  );
}
