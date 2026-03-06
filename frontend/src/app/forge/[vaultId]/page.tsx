"use client";

import { use } from "react";
import { type Address } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useVaultAddress } from "@/hooks/useForgeFactory";
import { VaultMetrics } from "@/components/forge/VaultMetrics";
import { TrancheTable } from "@/components/forge/TrancheTable";
import { HedgePanel } from "@/components/forge/HedgePanel";
import { ForgeVaultAbi } from "@/lib/contracts/abis/ForgeVault";
import Link from "next/link";

export default function VaultDetailPage({ params }: { params: Promise<{ vaultId: string }> }) {
  const { vaultId } = use(params);
  const id = parseInt(vaultId, 10);
  const { data: vaultAddress, isLoading } = useVaultAddress(BigInt(id));

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  if (isLoading) {
    return <div className="text-zinc-500">Loading vault...</div>;
  }

  if (!vaultAddress) {
    return <div className="text-zinc-500">Vault not found</div>;
  }

  const addr = vaultAddress as Address;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link href="/forge" className="text-zinc-500 hover:text-white text-sm">&larr; Back</Link>
        <h2 className="text-lg font-medium">Vault #{vaultId}</h2>
        <span className="text-xs text-zinc-500 font-mono">{addr}</span>
      </div>

      <VaultMetrics vaultAddress={addr} />
      <TrancheTable vaultAddress={addr} />
      <HedgePanel vaultAddress={addr} />

      <div className="pt-4 border-t border-[var(--card-border)]">
        <button
          onClick={() =>
            writeContract({
              address: addr,
              abi: ForgeVaultAbi,
              functionName: "triggerWaterfall",
            })
          }
          disabled={isPending}
          className="px-4 py-2 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
        >
          {isPending ? "Triggering..." : isSuccess ? "Waterfall Triggered" : "Trigger Waterfall Distribution"}
        </button>
      </div>
    </div>
  );
}
