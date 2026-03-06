"use client";

import { usePoolCount, usePoolAddress } from "@/hooks/useCDSPoolFactory";
import { PoolCard } from "@/components/pools/PoolCard";
import { type Address } from "viem";

function PoolItem({ poolId }: { poolId: number }) {
  const { data: poolAddress } = usePoolAddress(BigInt(poolId));
  if (!poolAddress || poolAddress === "0x0000000000000000000000000000000000000000") return null;
  return <PoolCard poolId={poolId} poolAddress={poolAddress as Address} />;
}

export default function PoolsPage() {
  const { data: count, isLoading } = usePoolCount();

  if (isLoading) {
    return <div className="text-zinc-500">Loading CDS pools...</div>;
  }

  const poolCount = count ? Number(count) : 0;

  if (poolCount === 0) {
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
        <span className="text-sm text-zinc-500">{poolCount} pool{poolCount !== 1 ? "s" : ""}</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: poolCount }, (_, i) => (
          <PoolItem key={i} poolId={i} />
        ))}
      </div>
    </div>
  );
}
