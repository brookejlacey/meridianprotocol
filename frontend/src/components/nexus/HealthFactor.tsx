"use client";

import { formatRatio } from "@/lib/utils";

export function HealthFactor({ ratio, isHealthy }: { ratio: bigint | undefined; isHealthy: boolean | undefined }) {
  if (ratio === undefined) {
    return <div className="text-zinc-500 text-sm">Loading...</div>;
  }

  const isMax = ratio === BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
  const pct = isMax ? Infinity : Number(ratio) / 1e16; // ratio in WAD -> percentage

  let color = "bg-green-500";
  let textColor = "text-green-400";
  let label = "Healthy";

  if (!isMax) {
    if (pct < 110) {
      color = "bg-red-500";
      textColor = "text-red-400";
      label = "Liquidatable";
    } else if (pct < 150) {
      color = "bg-yellow-500";
      textColor = "text-yellow-400";
      label = "Warning";
    }
  }

  const barWidth = isMax ? 100 : Math.min(pct / 2, 100); // scale: 200% = full bar

  return (
    <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm text-zinc-400">Health Factor</span>
        <span className={`text-sm font-medium ${textColor}`}>{label}</span>
      </div>
      <div className="flex items-center gap-3">
        <div className="flex-1 h-2 bg-zinc-800 rounded-full overflow-hidden">
          <div className={`h-full ${color} rounded-full transition-all`} style={{ width: `${barWidth}%` }} />
        </div>
        <span className="text-sm font-mono font-medium w-20 text-right">{formatRatio(ratio)}</span>
      </div>
    </div>
  );
}
