"use client";

import Link from "next/link";
import { type Address } from "viem";
import {
  usePoolTerms,
  usePoolStatus,
  useTotalAssets,
  useUtilizationRate,
  useCurrentSpread,
  useTotalProtectionSold,
} from "@/hooks/useCDSPool";
import { formatAmount, formatWadPercent, formatRatio, PoolStatus, shortenAddress } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Active: "bg-green-500/20 text-green-400",
  Triggered: "bg-red-500/20 text-red-400",
  Settled: "bg-[var(--accent)]/15 text-[var(--accent)]",
  Expired: "bg-zinc-500/20 text-zinc-400",
};

export function PoolCard({ poolId, poolAddress }: { poolId: number; poolAddress: Address }) {
  const { data: terms } = usePoolTerms(poolAddress);
  const { data: status } = usePoolStatus(poolAddress);
  const { data: totalAssets } = useTotalAssets(poolAddress);
  const { data: utilization } = useUtilizationRate(poolAddress);
  const { data: spread } = useCurrentSpread(poolAddress);
  const { data: protectionSold } = useTotalProtectionSold(poolAddress);

  const statusLabel = status !== undefined ? PoolStatus[status as keyof typeof PoolStatus] ?? "Unknown" : "...";
  const maturitySec = terms ? Number(terms.maturity) : 0;
  const nowSec = Math.floor(Date.now() / 1000);
  const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;

  // Utilization bar width (0-100%)
  const utilPct = utilization !== undefined ? Math.min(Number(utilization) / 1e16, 100) : 0;
  const utilColor = utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500";

  return (
    <Link
      href={`/pools/${poolId}`}
      className="block p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] hover:border-zinc-600 transition-colors"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-sm font-medium text-zinc-400">Pool #{poolId}</span>
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${statusColor[statusLabel] ?? "bg-zinc-500/20 text-zinc-400"}`}>
          {statusLabel}
        </span>
      </div>

      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Reference Asset</span>
          <span className="font-mono">{terms ? shortenAddress(terms.referenceAsset) : "..."}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Total Liquidity</span>
          <span className="font-mono">{totalAssets !== undefined ? formatAmount(totalAssets) : "..."}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Protection Sold</span>
          <span className="font-mono">{protectionSold !== undefined ? formatAmount(protectionSold) : "..."}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Current Spread</span>
          <span className="font-mono text-[var(--accent)]">{spread !== undefined ? formatWadPercent(spread) : "..."}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Time to Maturity</span>
          <span className="font-mono">{daysLeft > 0 ? `${daysLeft}d` : "Expired"}</span>
        </div>

        {/* Utilization Bar */}
        <div>
          <div className="flex justify-between text-xs mb-1">
            <span className="text-zinc-500">Utilization</span>
            <span className="text-zinc-400">{utilPct.toFixed(1)}%</span>
          </div>
          <div className="h-1.5 bg-zinc-800 rounded-full overflow-hidden">
            <div className={`h-full rounded-full transition-all ${utilColor}`} style={{ width: `${utilPct}%` }} />
          </div>
        </div>
      </div>
    </Link>
  );
}
