"use client";

import Link from "next/link";
import { type IndexedVault } from "@/hooks/indexer/useIndexedVaults";
import { formatAmount } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Open: "bg-[var(--accent)]/15 text-[var(--accent)]",
  Active: "bg-green-500/20 text-green-400",
  Matured: "bg-yellow-500/20 text-yellow-400",
  Closed: "bg-zinc-500/20 text-zinc-400",
};

export function VaultCard({ vault }: { vault: IndexedVault }) {
  return (
    <Link
      href={`/forge/${vault.vaultId}`}
      className="block p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] hover:border-zinc-600 transition-colors"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-sm font-medium text-zinc-400">Vault #{vault.vaultId}</span>
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${statusColor[vault.status] ?? "bg-zinc-500/20 text-zinc-400"}`}>
          {vault.status}
        </span>
      </div>
      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Total Deposited</span>
          <span className="font-mono">{formatAmount(BigInt(vault.totalDeposited))}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Yield Received</span>
          <span className="font-mono">{formatAmount(BigInt(vault.totalYieldReceived))}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Yield Distributed</span>
          <span className="font-mono">{formatAmount(BigInt(vault.totalYieldDistributed))}</span>
        </div>
      </div>
    </Link>
  );
}
