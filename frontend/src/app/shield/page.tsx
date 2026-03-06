"use client";

import { useIndexedCDS } from "@/hooks/indexer/useIndexedCDS";
import { CDSCard } from "@/components/shield/CDSCard";

export default function ShieldPage() {
  const { data: contracts, isLoading } = useIndexedCDS();

  if (isLoading) {
    return <div className="text-zinc-500">Loading CDS contracts...</div>;
  }

  if (!contracts || contracts.length === 0) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">No CDS Contracts Yet</h2>
        <p className="text-zinc-500 text-sm">
          No credit default swaps have been created. Deploy contracts to Fuji and create a CDS to get started.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Credit Default Swaps</h2>
            <p className="text-sm text-zinc-500 mt-1">Bilateral credit protection contracts with automated settlement</p>
          </div>
          <span className="text-sm text-zinc-500 bg-zinc-800/50 px-3 py-1 rounded-full">{contracts.length} contract{contracts.length !== 1 ? "s" : ""}</span>
        </div>
        <div className="mt-4 h-[1px] bg-gradient-to-r from-purple-500/40 via-pink-400/40 to-transparent" />
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {contracts.map((cds) => (
          <CDSCard key={cds.id} cds={cds} />
        ))}
      </div>
    </div>
  );
}
