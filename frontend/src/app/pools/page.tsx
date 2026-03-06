"use client";

import Link from "next/link";
import { useIndexedPools } from "@/hooks/indexer/useIndexedPools";
import { formatAmount, formatWadPercent, shortenAddress, formatDate } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Active: "bg-green-500/20 text-green-400",
  Triggered: "bg-red-500/20 text-red-400",
  Settled: "bg-[var(--accent)]/15 text-[var(--accent)]",
  Expired: "bg-zinc-500/20 text-zinc-400",
};

export default function PoolsPage() {
  const { data: pools, isLoading } = useIndexedPools();

  if (isLoading) {
    return <div className="text-zinc-500">Loading CDS pools...</div>;
  }

  if (!pools || pools.length === 0) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">No CDS AMM Pools Yet</h2>
        <p className="text-zinc-500 text-sm">
          No automated market maker pools have been created. Deploy a CDSPoolFactory and create a pool to get started.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-lg font-medium">CDS AMM Pools</h2>
          <p className="text-sm text-zinc-500">Automated credit protection with bonding curve pricing</p>
        </div>
        <span className="text-sm text-zinc-500">{pools.length} pool{pools.length !== 1 ? "s" : ""}</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {pools.map((pool) => {
          const utilPct = Number(BigInt(pool.utilizationRate)) / 1e16;
          const utilColor = utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500";
          const maturitySec = Number(BigInt(pool.maturity));
          const nowSec = Math.floor(Date.now() / 1000);
          const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;

          return (
            <Link
              key={pool.poolId}
              href={`/pools/${pool.poolId}`}
              className="block p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] hover:border-zinc-600 transition-colors"
            >
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-medium text-zinc-400">Pool #{pool.poolId}</span>
                <span className={`text-xs px-2 py-0.5 rounded font-medium ${statusColor[pool.status] ?? "bg-zinc-500/20 text-zinc-400"}`}>
                  {pool.status}
                </span>
              </div>

              <div className="space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-zinc-500">Reference Asset</span>
                  <span className="font-mono">{shortenAddress(pool.referenceAsset)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-zinc-500">Total Liquidity</span>
                  <span className="font-mono">{formatAmount(BigInt(pool.totalLiquidity))}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-zinc-500">Protection Sold</span>
                  <span className="font-mono">{formatAmount(BigInt(pool.protectionSold))}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-zinc-500">Current Spread</span>
                  <span className="font-mono text-[var(--accent)]">{formatWadPercent(BigInt(pool.currentSpread))}</span>
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
                    <div className={`h-full rounded-full transition-all ${utilColor}`} style={{ width: `${Math.min(utilPct, 100)}%` }} />
                  </div>
                </div>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
