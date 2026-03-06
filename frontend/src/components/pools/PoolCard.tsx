"use client";

import Link from "next/link";
import { type IndexedPool } from "@/hooks/indexer/useIndexedPools";
import { formatAmount, formatWadPercent, shortenAddress } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Active: "bg-green-500/15 text-green-400 border border-green-500/20",
  Triggered: "bg-red-500/15 text-red-400 border border-red-500/20",
  Settled: "bg-[var(--accent)]/15 text-[var(--accent)] border border-[var(--accent)]/20",
  Expired: "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20",
};

export function PoolCard({ pool }: { pool: IndexedPool }) {
  const maturitySec = Number(BigInt(pool.maturity));
  const nowSec = Math.floor(Date.now() / 1000);
  const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;

  // Utilization bar width (0-100%)
  const utilPct = Math.min(Number(BigInt(pool.utilizationRate)) / 1e16, 100);
  const utilColor = utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500";

  return (
    <Link
      href={`/pools/${pool.poolId}`}
      className="group block rounded-2xl border border-[var(--card-border)] bg-[var(--card-bg)] overflow-hidden transition-all duration-300 hover:border-orange-500/30 hover:shadow-lg hover:shadow-orange-500/5 hover:scale-[1.01]"
    >
      {/* Accent bar */}
      <div className="h-[2px] bg-gradient-to-r from-orange-500 to-amber-400" />

      <div className="p-5">
        <div className="flex items-center justify-between mb-4">
          <span className="text-base font-semibold text-zinc-200">Pool #{pool.poolId}</span>
          <span className={`text-xs px-2.5 py-0.5 rounded-full font-medium ${statusColor[pool.status] ?? "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20"}`}>
            {pool.status}
          </span>
        </div>

        <div className="space-y-2.5">
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Reference Asset</span>
            <span className="font-mono text-zinc-300">{shortenAddress(pool.referenceAsset)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Total Liquidity</span>
            <span className="font-mono text-zinc-200 flex items-center gap-1.5">
              <span className="inline-block w-1.5 h-1.5 rounded-full bg-amber-400" />
              ${formatAmount(BigInt(pool.totalLiquidity))}
            </span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Protection Sold</span>
            <span className="font-mono text-zinc-300">${formatAmount(BigInt(pool.protectionSold))}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Current Spread</span>
            <span className="font-mono text-[var(--accent)]">{formatWadPercent(BigInt(pool.currentSpread))}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Time to Maturity</span>
            <span className="font-mono text-zinc-300">{daysLeft > 0 ? `${daysLeft}d` : "Expired"}</span>
          </div>

          {/* Utilization Bar */}
          <div className="pt-1">
            <div className="flex justify-between text-xs mb-1.5">
              <span className="text-zinc-500">Utilization</span>
              <span className="text-zinc-400">{utilPct.toFixed(1)}%</span>
            </div>
            <div className="h-1.5 bg-zinc-800 rounded-full overflow-hidden">
              <div className={`h-full rounded-full transition-all ${utilColor}`} style={{ width: `${Math.min(utilPct, 100)}%` }} />
            </div>
          </div>
        </div>
      </div>
    </Link>
  );
}
