"use client";

import Link from "next/link";
import { type IndexedCDS } from "@/hooks/indexer/useIndexedCDS";
import { formatAmount, formatBps, shortenAddress } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Active: "bg-green-500/20 text-green-400",
  Triggered: "bg-red-500/20 text-red-400",
  Settled: "bg-[var(--accent)]/15 text-[var(--accent)]",
  Expired: "bg-zinc-500/20 text-zinc-400",
};

export function CDSCard({ cds }: { cds: IndexedCDS }) {
  const maturitySec = Number(cds.maturity);
  const nowSec = Math.floor(Date.now() / 1000);
  const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;
  const isMatched = !!cds.buyer && !!cds.seller;

  return (
    <Link
      href={`/shield/${cds.cdsId}`}
      className="block p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] hover:border-zinc-600 transition-colors"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-sm font-medium text-zinc-400">CDS #{cds.cdsId}</span>
        <div className="flex gap-1">
          <span className={`text-xs px-2 py-0.5 rounded font-medium ${statusColor[cds.status] ?? "bg-zinc-500/20 text-zinc-400"}`}>
            {cds.status}
          </span>
          {isMatched && (
            <span className="text-xs px-2 py-0.5 rounded bg-purple-500/20 text-purple-400 font-medium">
              Matched
            </span>
          )}
        </div>
      </div>
      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Reference Asset</span>
          <span className="font-mono">{shortenAddress(cds.referenceVaultId)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Protection Amount</span>
          <span className="font-mono">{formatAmount(BigInt(cds.protectionAmount))}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Premium Rate</span>
          <span className="font-mono">{formatBps(Number(cds.premiumRate))}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-zinc-500">Time to Maturity</span>
          <span className="font-mono">{daysLeft > 0 ? `${daysLeft}d` : "Expired"}</span>
        </div>
      </div>
    </Link>
  );
}
