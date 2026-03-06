"use client";

import { useState } from "react";
import { type Address, parseUnits } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useTrancheParams, useClaimableYield } from "@/hooks/useForgeVault";
import { useTokenAllowance, useApproveToken } from "@/hooks/useApproveToken";
import { ForgeVaultAbi } from "@/lib/contracts/abis/ForgeVault";
import { formatAmount, formatBps } from "@/lib/utils";

const TRANCHE_NAMES = ["Senior", "Mezzanine", "Equity"] as const;

export function TrancheTable({ vaultAddress }: { vaultAddress: Address }) {
  return (
    <div className="space-y-3">
      <h3 className="text-sm font-medium text-zinc-400">Tranches</h3>
      <div className="space-y-2">
        {[0, 1, 2].map((id) => (
          <TrancheRow key={id} vaultAddress={vaultAddress} trancheId={id} />
        ))}
      </div>
    </div>
  );
}

function TrancheRow({ vaultAddress, trancheId }: { vaultAddress: Address; trancheId: number }) {
  const { address: userAddress } = useAccount();
  const { data: params } = useTrancheParams(vaultAddress, trancheId);
  const { data: claimable } = useClaimableYield(vaultAddress, userAddress, trancheId);
  const { data: allowance } = useTokenAllowance(
    params?.token as Address | undefined,
    userAddress,
    vaultAddress
  );

  const [action, setAction] = useState<"invest" | "claim" | "withdraw" | null>(null);
  const [amount, setAmount] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });
  const { approve, isPending: isApproving } = useApproveToken();

  const needsApproval = action === "invest" && allowance !== undefined && amount &&
    allowance < parseUnits(amount, 18);

  function handleSubmit() {
    if (!amount && action !== "claim") return;
    const parsedAmount = action !== "claim" ? parseUnits(amount, 18) : 0n;

    if (action === "invest") {
      if (needsApproval && params) {
        approve(params.token as Address, vaultAddress);
        return;
      }
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "invest",
        args: [trancheId, parsedAmount],
      });
    } else if (action === "claim") {
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "claimYield",
        args: [trancheId],
      });
    } else if (action === "withdraw") {
      writeContract({
        address: vaultAddress,
        abi: ForgeVaultAbi,
        functionName: "withdraw",
        args: [trancheId, parsedAmount],
      });
    }
  }

  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="flex items-center justify-between mb-2">
        <span className="font-medium text-sm">{TRANCHE_NAMES[trancheId]}</span>
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
          <div className="font-mono">{params ? formatBps(params.targetApr) : "..."}</div>
        </div>
        <div>
          <span className="text-zinc-500">Allocation</span>
          <div className="font-mono">{params ? formatBps(params.allocationPct) : "..."}</div>
        </div>
        <div>
          <span className="text-zinc-500">Claimable</span>
          <div className="font-mono">{claimable !== undefined ? formatAmount(claimable) : "..."}</div>
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
