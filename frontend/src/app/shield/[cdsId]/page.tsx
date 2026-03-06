"use client";

import { use } from "react";
import { type Address } from "viem";
import { useCDSAddress } from "@/hooks/useShieldFactory";
import { CDSDetail } from "@/components/shield/CDSDetail";
import Link from "next/link";

export default function CDSDetailPage({ params }: { params: Promise<{ cdsId: string }> }) {
  const { cdsId } = use(params);
  const id = parseInt(cdsId, 10);
  const { data: cdsAddress, isLoading } = useCDSAddress(BigInt(id));

  if (isLoading) {
    return <div className="text-zinc-500">Loading CDS contract...</div>;
  }

  if (!cdsAddress) {
    return <div className="text-zinc-500">CDS contract not found</div>;
  }

  const addr = cdsAddress as Address;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link href="/shield" className="text-zinc-500 hover:text-white text-sm">&larr; Back</Link>
        <h2 className="text-lg font-medium">CDS #{cdsId}</h2>
        <span className="text-xs text-zinc-500 font-mono">{addr}</span>
      </div>
      <CDSDetail cdsAddress={addr} />
    </div>
  );
}
