"use client";

import { useIndexedPools } from "@/hooks/indexer/useIndexedPools";
import { PoolCard } from "@/components/pools/PoolCard";

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
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">CDS AMM Pools</h2>
            <p className="text-sm text-zinc-500 mt-1">Automated credit protection with bonding curve pricing</p>
          </div>
          <span className="text-sm text-zinc-500 bg-zinc-800/50 px-3 py-1 rounded-full">{pools.length} pool{pools.length !== 1 ? "s" : ""}</span>
        </div>
        <div className="mt-4 h-[1px] bg-gradient-to-r from-orange-500/40 via-amber-400/40 to-transparent" />
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {pools.map((pool) => (
          <PoolCard key={pool.poolId} pool={pool} />
        ))}
      </div>
    </div>
  );
}
