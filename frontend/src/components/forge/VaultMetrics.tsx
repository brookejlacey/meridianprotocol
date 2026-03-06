"use client";

import { type Address } from "viem";
import { usePoolMetrics, usePoolStatus, useVaultOriginator } from "@/hooks/useForgeVault";
import { formatAmount, formatDate, shortenAddress, VaultStatus } from "@/lib/utils";

export function VaultMetrics({ vaultAddress }: { vaultAddress: Address }) {
  const { data: metrics, isLoading } = usePoolMetrics(vaultAddress);
  const { data: status } = usePoolStatus(vaultAddress);
  const { data: originator } = useVaultOriginator(vaultAddress);

  if (isLoading) {
    return <div className="text-zinc-500">Loading vault metrics...</div>;
  }

  const statusLabel = status !== undefined ? VaultStatus[status as keyof typeof VaultStatus] ?? "Unknown" : "Unknown";

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <MetricBox label="Status" value={statusLabel} />
      <MetricBox label="Originator" value={originator ? shortenAddress(originator) : "..."} />
      <MetricBox label="Total Deposited" value={metrics ? formatAmount(metrics.totalDeposited) : "..."} />
      <MetricBox label="Yield Received" value={metrics ? formatAmount(metrics.totalYieldReceived) : "..."} />
      <MetricBox label="Yield Distributed" value={metrics ? formatAmount(metrics.totalYieldDistributed) : "..."} />
      <MetricBox label="Last Distribution" value={metrics ? formatDate(metrics.lastDistribution) : "..."} />
    </div>
  );
}

function MetricBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="text-xs text-zinc-500 mb-1">{label}</div>
      <div className="text-sm font-mono font-medium">{value}</div>
    </div>
  );
}
