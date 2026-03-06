"use client";

import { use, useState } from "react";
import { type Address, parseUnits } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useIndexedVaults, type IndexedTranche } from "@/hooks/indexer/useIndexedVaults";
import { useTokenAllowance, useApproveToken } from "@/hooks/useApproveToken";
import { ForgeVaultAbi } from "@/lib/contracts/abis/ForgeVault";
import { formatAmount, shortenAddress, formatDate } from "@/lib/utils";
import Link from "next/link";

const TRANCHE_NAMES = ["Senior", "Mezzanine", "Equity"] as const;

function formatStaticAmount(value: string): string {
  return formatAmount(BigInt(value));
}

function formatApr(value: string): string {
  const pct = Number(BigInt(value)) / 1e16;
  return pct.toFixed(2) + "%";
}

export default function VaultDetailPage({ params }: { params: Promise<{ vaultId: string }> }) {
  const { vaultId } = use(params);
  const { data: vaults, isLoading } = useIndexedVaults();

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const vault = vaults?.find((v) => v.vaultId === vaultId);

  if (isLoading) {
    return <div className="text-zinc-500">Loading vault...</div>;
  }

  if (!vault) {
    return <div className="text-zinc-500">Vault not found</div>;
  }

  const addr = vault.id as Address;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link href="/forge" className="text-zinc-500 hover:text-white text-sm">&larr; Back</Link>
        <h2 className="text-lg font-medium">Vault #{vaultId}</h2>
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${
          vault.status === "Active" ? "bg-green-500/20 text-green-400" :
          vault.status === "Matured" ? "bg-[var(--accent)]/15 text-[var(--accent)]" :
          "bg-zinc-500/20 text-zinc-400"
        }`}>
          {vault.status}
        </span>
      </div>
      <div className="text-xs text-zinc-500 font-mono -mt-4">{addr}</div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <MetricBox label="Status" value={vault.status} />
        <MetricBox label="Originator" value={shortenAddress(vault.originator)} />
        <MetricBox label="Total Deposited" value={formatStaticAmount(vault.totalDeposited)} />
        <MetricBox label="Yield Received" value={formatStaticAmount(vault.totalYieldReceived)} />
        <MetricBox label="Yield Distributed" value={formatStaticAmount(vault.totalYieldDistributed)} />
        <MetricBox label="Last Distribution" value={formatDate(BigInt(vault.lastDistribution))} />
      </div>

      {/* Tranches */}
      <div className="space-y-3">
        <h3 className="text-sm font-medium text-zinc-400">Tranches</h3>
        <div className="space-y-2">
          {vault.tranches.items.map((tranche) => (
            <TrancheRow key={tranche.trancheId} vaultAddress={addr} tranche={tranche} />
          ))}
        </div>
      </div>

      {/* Waterfall Trigger */}
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

function MetricBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="text-xs text-zinc-500 mb-1">{label}</div>
      <div className="text-sm font-mono font-medium">{value}</div>
    </div>
  );
}

function TrancheRow({ vaultAddress, tranche }: { vaultAddress: Address; tranche: IndexedTranche }) {
  const { address: userAddress } = useAccount();
  const { approve, isPending: isApproving } = useApproveToken();
  const { data: allowance } = useTokenAllowance(
    tranche.tokenAddress as Address,
    userAddress,
    vaultAddress
  );

  const [action, setAction] = useState<"invest" | "claim" | "withdraw" | null>(null);
  const [amount, setAmount] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const needsApproval = action === "invest" && allowance !== undefined && amount &&
    allowance < parseUnits(amount, 18);

  function handleSubmit() {
    if (!amount && action !== "claim") return;
    const parsedAmount = action !== "claim" ? parseUnits(amount, 18) : 0n;

    if (action === "invest") {
      if (needsApproval) {
        approve(tranche.tokenAddress as Address, vaultAddress);
        return;
      }
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "invest",
        args: [tranche.trancheId, parsedAmount],
      });
    } else if (action === "claim") {
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "claimYield",
        args: [tranche.trancheId],
      });
    } else if (action === "withdraw") {
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "withdraw",
        args: [tranche.trancheId, parsedAmount],
      });
    }
  }

  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="flex items-center justify-between mb-2">
        <span className="font-medium text-sm">{TRANCHE_NAMES[tranche.trancheId]}</span>
        <div className="flex gap-1">
          {(["invest", "claim", "withdraw"] as const).map((a) => (
            <button
              key={a}
              onClick={() => setAction(action === a ? null : a)}
              className={`text-xs px-2 py-1 rounded transition-colors ${
                action === a
                  ? "bg-[var(--accent)] text-black"
                  : "bg-zinc-800 text-zinc-400 hover:text-white"
              }`}
            >
              {a.charAt(0).toUpperCase() + a.slice(1)}
            </button>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-3 gap-2 text-xs">
        <div>
          <span className="text-zinc-500">Target APR</span>
          <div className="font-mono">{formatApr(tranche.targetApr)}</div>
        </div>
        <div>
          <span className="text-zinc-500">Allocation</span>
          <div className="font-mono">{tranche.allocationPct}%</div>
        </div>
        <div>
          <span className="text-zinc-500">Total Invested</span>
          <div className="font-mono">{formatStaticAmount(tranche.totalInvested)}</div>
        </div>
      </div>
      {action && (
        <div className="mt-2 flex gap-2">
          {action !== "claim" && (
            <input
              type="text"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="Amount"
              className="flex-1 px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
            />
          )}
          <button
            onClick={handleSubmit}
            disabled={isPending || isApproving}
            className="px-3 py-1 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
          >
            {isPending ? "Pending..." : isApproving ? "Approving..." : needsApproval ? "Approve" : isSuccess ? "Done" : "Submit"}
          </button>
        </div>
      )}
    </div>
  );
}
