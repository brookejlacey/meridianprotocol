"use client";

import Link from "next/link";
import { type IndexedCDS } from "@/hooks/indexer/useIndexedCDS";
import { formatAmount, formatBps, shortenAddress } from "@/lib/utils";

const statusColor: Record<string, string> = {
  Active: "bg-green-500/15 text-green-400 border border-green-500/20",
  Triggered: "bg-red-500/15 text-red-400 border border-red-500/20",
  Settled: "bg-[var(--accent)]/15 text-[var(--accent)] border border-[var(--accent)]/20",
  Expired: "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20",
};

export function CDSCard({ cds }: { cds: IndexedCDS }) {
  const maturitySec = Number(cds.maturity);
  const nowSec = Math.floor(Date.now() / 1000);
  const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;
  const isMatched = !!cds.buyer && !!cds.seller;

  return (
    <Link
      href={`/shield/${cds.cdsId}`}
      className="group block rounded-2xl border border-[var(--card-border)] bg-[var(--card-bg)] overflow-hidden transition-all duration-300 hover:border-purple-500/30 hover:shadow-lg hover:shadow-purple-500/5 hover:scale-[1.01]"
    >
      {/* Accent bar */}
      <div className="h-[2px] bg-gradient-to-r from-purple-500 to-pink-400" />

      <div className="p-5">
        <div className="flex items-center justify-between mb-4">
          <span className="text-base font-semibold text-zinc-200">CDS #{cds.cdsId}</span>
          <div className="flex gap-1.5">
            <span className={`text-xs px-2.5 py-0.5 rounded-full font-medium ${statusColor[cds.status] ?? "bg-zinc-500/15 text-zinc-400 border border-zinc-500/20"}`}>
              {cds.status}
            </span>
            {isMatched && (
              <span className="text-xs px-2.5 py-0.5 rounded-full bg-purple-500/15 text-purple-400 border border-purple-500/20 font-medium">
                Matched
              </span>
            )}
          </div>
        </div>

        <div className="space-y-2.5">
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Reference Asset</span>
            <span className="font-mono text-zinc-300">{shortenAddress(cds.referenceVaultId)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Protection Amount</span>
            <span className="font-mono text-zinc-200">${formatAmount(BigInt(cds.protectionAmount))}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Premium Rate</span>
            <span className="font-mono text-purple-400">{formatBps(Number(cds.premiumRate))}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Time to Maturity</span>
            <span className="font-mono text-zinc-300">{daysLeft > 0 ? `${daysLeft}d` : "Expired"}</span>
          </div>
        </div>
      </div>
    </Link>
  );
}
