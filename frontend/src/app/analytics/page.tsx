"use client";

import { useProtocolMetrics, usePoolAnalytics } from "@/hooks/useAnalytics";
import { usePoolCount, usePoolAddress } from "@/hooks/useCDSPoolFactory";
import { formatAmount, formatWadPercent, PoolStatus } from "@/lib/utils";
import { type Address } from "viem";

function MetricCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg p-4">
      <p className="text-xs text-zinc-500 uppercase tracking-wide">{label}</p>
      <p className="text-xl font-semibold mt-1">{value}</p>
      {sub && <p className="text-xs text-zinc-400 mt-1">{sub}</p>}
    </div>
  );
}

function PoolRow({ poolId }: { poolId: number }) {
  const { data: addr } = usePoolAddress(BigInt(poolId));
  const poolAddr = addr as Address | undefined;
  const m = usePoolAnalytics(poolAddr);

  if (!m.enabled) return null;

  const statusLabel =
    m.status !== undefined
      ? PoolStatus[m.status as keyof typeof PoolStatus] ?? "Unknown"
      : "...";

  return (
    <tr className="border-b border-[var(--card-border)]">
      <td className="py-2 px-3 text-sm font-mono text-zinc-400">#{poolId}</td>
      <td className="py-2 px-3 text-sm">
        <span
          className={`px-2 py-0.5 rounded text-xs ${
            statusLabel === "Active"
              ? "bg-green-900/50 text-green-400"
              : statusLabel === "Triggered"
              ? "bg-red-900/50 text-red-400"
              : "bg-zinc-800 text-zinc-400"
          }`}
        >
          {statusLabel}
        </span>
      </td>
      <td className="py-2 px-3 text-sm text-right">
        {formatAmount(m.totalAssets)}
      </td>
      <td className="py-2 px-3 text-sm text-right">
        {formatAmount(m.totalProtection)}
      </td>
      <td className="py-2 px-3 text-sm text-right">
        {formatWadPercent(m.utilization)}
      </td>
      <td className="py-2 px-3 text-sm text-right">
        {formatWadPercent(m.spread)}
      </td>
    </tr>
  );
}

function PoolTable() {
  const { data: count } = usePoolCount();
  const poolCount = count ? Number(count) : 0;

  if (poolCount === 0) {
    return (
      <p className="text-sm text-zinc-500">No AMM pools deployed yet.</p>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left">
        <thead>
          <tr className="border-b border-[var(--card-border)] text-xs text-zinc-500 uppercase">
            <th className="py-2 px-3">Pool</th>
            <th className="py-2 px-3">Status</th>
            <th className="py-2 px-3 text-right">TVL</th>
            <th className="py-2 px-3 text-right">Protection Sold</th>
            <th className="py-2 px-3 text-right">Utilization</th>
            <th className="py-2 px-3 text-right">Spread</th>
          </tr>
        </thead>
        <tbody>
          {Array.from({ length: poolCount }, (_, i) => (
            <PoolRow key={i} poolId={i} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TranchePie({
  senior,
  mezz,
  equity,
}: {
  senior: bigint;
  mezz: bigint;
  equity: bigint;
}) {
  const total = senior + mezz + equity;
  if (total === 0n) {
    return <p className="text-sm text-zinc-500">No tranche data</p>;
  }
  const pct = (v: bigint) => Number((v * 10000n) / total) / 100;
  const seniorPct = pct(senior);
  const mezzPct = pct(mezz);
  const equityPct = pct(equity);

  return (
    <div className="space-y-2">
      <BarSegment label="Senior" pct={seniorPct} color="bg-blue-500" amount={senior} />
      <BarSegment label="Mezzanine" pct={mezzPct} color="bg-yellow-500" amount={mezz} />
      <BarSegment label="Equity" pct={equityPct} color="bg-red-500" amount={equity} />
    </div>
  );
}

function BarSegment({
  label,
  pct,
  color,
  amount,
}: {
  label: string;
  pct: number;
  color: string;
  amount: bigint;
}) {
  return (
    <div>
      <div className="flex justify-between text-xs mb-1">
        <span className="text-zinc-400">{label}</span>
        <span className="text-zinc-300">
          {formatAmount(amount)} ({pct.toFixed(1)}%)
        </span>
      </div>
      <div className="w-full bg-zinc-800 rounded-full h-2.5">
        <div
          className={`${color} h-2.5 rounded-full transition-all`}
          style={{ width: `${Math.max(pct, 1)}%` }}
        />
      </div>
    </div>
  );
}

export default function AnalyticsPage() {
  const { data: metrics, isLoading, error } = useProtocolMetrics();

  if (isLoading) {
    return <div className="text-zinc-500">Loading protocol analytics...</div>;
  }

  if (error || !metrics) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">Analytics Unavailable</h2>
        <p className="text-sm text-zinc-500">
          Could not load data. Make sure the Ponder indexer is running (cd indexer && pnpm dev).
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div>
        <h2 className="text-lg font-medium">Protocol Analytics</h2>
        <p className="text-sm text-zinc-500">
          Real-time aggregate metrics across Forge, Shield, and CDS pools
        </p>
      </div>

      {/* Top-level KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard
          label="Total Vault TVL"
          value={`$${formatAmount(metrics.totalVaultTVL)}`}
          sub={`${metrics.vaultCount} vault${metrics.vaultCount !== 1 ? "s" : ""} (${metrics.activeVaults} active)`}
        />
        <MetricCard
          label="Yield Generated"
          value={`$${formatAmount(metrics.totalYieldGenerated)}`}
          sub={`$${formatAmount(metrics.totalYieldDistributed)} distributed`}
        />
        <MetricCard
          label="Bilateral CDS Protection"
          value={`$${formatAmount(metrics.totalProtectionBilateral)}`}
          sub={`${metrics.cdsCount} contract${metrics.cdsCount !== 1 ? "s" : ""} (${metrics.activeCDS} active)`}
        />
        <MetricCard
          label="CDS Collateral Posted"
          value={`$${formatAmount(metrics.totalCollateralPosted)}`}
          sub={`$${formatAmount(metrics.totalPremiumsPaid)} premiums paid`}
        />
      </div>

      {/* Weighted APR + Tranche Breakdown */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg p-5">
          <h3 className="text-sm font-medium text-zinc-400 mb-4">
            Tranche Capital Distribution
          </h3>
          <TranchePie
            senior={metrics.seniorTVL}
            mezz={metrics.mezzTVL}
            equity={metrics.equityTVL}
          />
        </div>
        <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg p-5">
          <h3 className="text-sm font-medium text-zinc-400 mb-3">
            Key Rates
          </h3>
          <div className="space-y-4">
            <div className="flex justify-between items-center">
              <span className="text-sm text-zinc-400">Weighted Avg APR</span>
              <span className="text-lg font-semibold">
                {metrics.weightedAvgApr.toFixed(2)}%
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-zinc-400">Yield Capture Rate</span>
              <span className="text-lg font-semibold">
                {metrics.totalYieldGenerated > 0n
                  ? (
                      (Number(metrics.totalYieldDistributed) /
                        Number(metrics.totalYieldGenerated)) *
                      100
                    ).toFixed(1) + "%"
                  : "N/A"}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-zinc-400">
                Protection/TVL Ratio
              </span>
              <span className="text-lg font-semibold">
                {metrics.totalVaultTVL > 0n
                  ? (
                      (Number(metrics.totalProtectionBilateral) /
                        Number(metrics.totalVaultTVL)) *
                      100
                    ).toFixed(1) + "%"
                  : "N/A"}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* CDS AMM Pool Table */}
      <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg p-5">
        <h3 className="text-sm font-medium text-zinc-400 mb-4">
          CDS AMM Pool Breakdown
        </h3>
        <PoolTable />
      </div>
    </div>
  );
}
