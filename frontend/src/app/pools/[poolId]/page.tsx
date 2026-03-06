"use client";

import { use } from "react";
import { type Address } from "viem";
import Link from "next/link";
import { usePoolAddress } from "@/hooks/useCDSPoolFactory";
import { PoolDetail } from "@/components/pools/PoolDetail";

export default function PoolDetailPage({ params }: { params: Promise<{ poolId: string }> }) {
  const { poolId } = use(params);
  const id = BigInt(poolId);
  const { data: poolAddress, isLoading } = usePoolAddress(id);

  if (isLoading) {
    return <div className="text-zinc-500">Loading pool...</div>;
  }

  if (!poolAddress || poolAddress === "0x0000000000000000000000000000000000000000") {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">Pool Not Found</h2>
        <Link href="/pools" className="text-[var(--accent)] hover:text-[var(--accent)] text-sm">
          Back to pools
        </Link>
      </div>
    );
  }

  return (
    <div>
      <Link href="/pools" className="text-sm text-zinc-500 hover:text-zinc-300 mb-4 block">
        &larr; Back to pools
      </Link>
      <PoolDetail poolAddress={poolAddress as Address} />
    </div>
  );
}
