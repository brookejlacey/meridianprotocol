"use client";

import Link from "next/link";
import { type IndexedVault } from "@/hooks/indexer/useIndexedVaults";
import { formatAmount } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Open: "bg-[var(--accent)]/15 text-[var(--accent)] border border-[var(--accent)]/20",
  Active: "bg-green-500/15 text-green-400 border border-green-500/20",
  Matured: "bg-yellow-500/15 text-yellow-400 border border-yellow-500/20",
  Closed: "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20",
};

export function VaultCard({ vault }: { vault: IndexedVault }) {
  const trancheCount = vault.tranches?.items?.length ?? 0;

  return (
    <Link
      href={`/forge/${vault.vaultId}`}
      className="group block rounded-2xl border border-[var(--card-border)] bg-[var(--card-bg)] overflow-hidden transition-all duration-300 hover:border-[var(--accent)]/30 hover:shadow-lg hover:shadow-[var(--accent)]/5 hover:scale-[1.01]"
    >
      {/* Accent bar */}
      <div className="h-[2px] bg-gradient-to-r from-blue-500 via-cyan-400 to-[var(--accent)]" />

      <div className="p-5">
        <div className="flex items-center justify-between mb-4">
          <span className="text-base font-semibold text-zinc-200">Vault #{vault.vaultId}</span>
          <span className={`text-xs px-2.5 py-0.5 rounded-full font-medium ${statusColor[vault.status] ?? "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20"}`}>
            {vault.status}
          </span>
        </div>

        <div className="space-y-2.5">
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Total Deposited</span>
            <span className="font-mono text-zinc-200 flex items-center gap-1.5">
              <span className="inline-block w-1.5 h-1.5 rounded-full bg-cyan-400" />
              ${formatAmount(BigInt(vault.totalDeposited))}
            </span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Yield Received</span>
            <span className="font-mono text-zinc-300">${formatAmount(BigInt(vault.totalYieldReceived))}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Yield Distributed</span>
            <span className="font-mono text-zinc-300">${formatAmount(BigInt(vault.totalYieldDistributed))}</span>
          </div>
        </div>

        {trancheCount > 0 && (
          <div className="mt-4 pt-3 border-t border-zinc-800">
            <span className="text-xs text-zinc-500">{trancheCount} Tranche{trancheCount !== 1 ? "s" : ""}</span>
          </div>
        )}
      </div>
    </Link>
  );
}
