"use client";

import { useState } from "react";
import { type Address, parseUnits } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useUserAssets, useLocalDeposit } from "@/hooks/useNexusHub";
import { useApproveToken, useTokenAllowance } from "@/hooks/useApproveToken";
import { NexusHubAbi } from "@/lib/contracts/abis/NexusHub";
import { getAddresses } from "@/lib/contracts/addresses";
import { formatAmount, shortenAddress } from "@/lib/utils";

const hubAddress = getAddresses().nexusHub;

export function CollateralTable({ user }: { user: Address }) {
  const { data: assets } = useUserAssets(user);

  if (!assets || assets.length === 0) {
    return (
      <div className="text-sm text-zinc-500 p-4 border border-[var(--card-border)] rounded-lg bg-[var(--card-bg)]">
        No collateral deposited yet. Use the deposit form below.
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-medium text-zinc-400">Deposited Collateral</h3>
      {assets.map((asset) => (
        <AssetRow key={asset} user={user} asset={asset as Address} />
      ))}
    </div>
  );
}

function AssetRow({ user, asset }: { user: Address; asset: Address }) {
  const { data: balance } = useLocalDeposit(user, asset);
  const [action, setAction] = useState<"deposit" | "withdraw" | null>(null);
  const [amount, setAmount] = useState("");

  const { data: allowance } = useTokenAllowance(asset, user, hubAddress);
  const { approve, isPending: isApproving } = useApproveToken();
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const parsedAmount = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = action === "deposit" && allowance !== undefined && parsedAmount > allowance;

  function handleSubmit() {
    if (!amount) return;
    if (action === "deposit") {
      if (needsApproval) {
        approve(asset, hubAddress);
        return;
      }
      writeContract({
        address: hubAddress,
        abi: NexusHubAbi,
        functionName: "depositCollateral",
        args: [asset, parsedAmount],
      });
    } else if (action === "withdraw") {
      writeContract({
        address: hubAddress,
        abi: NexusHubAbi,
        functionName: "withdrawCollateral",
        args: [asset, parsedAmount],
      });
    }
  }

  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="flex items-center justify-between">
        <div>
          <span className="text-sm font-mono">{shortenAddress(asset)}</span>
          <span className="ml-2 text-sm text-zinc-400">
            {balance !== undefined ? formatAmount(balance) : "..."}
          </span>
        </div>
        <div className="flex gap-1">
          {(["deposit", "withdraw"] as const).map((a) => (
            <button
              key={a}
              onClick={() => setAction(action === a ? null : a)}
              className={`text-xs px-2 py-1 rounded transition-colors ${
                action === a ? "bg-[var(--accent)] text-black" : "bg-zinc-800 text-zinc-400 hover:text-white"
              }`}
            >
              {a.charAt(0).toUpperCase() + a.slice(1)}
            </button>
          ))}
        </div>
      </div>
      {action && (
        <div className="mt-2 flex gap-2">
          <input
            type="text" value={amount} onChange={(e) => setAmount(e.target.value)}
            placeholder="Amount"
            className="flex-1 px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
          />
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

export function DepositNewAsset() {
  const { address: userAddress } = useAccount();
  const [assetAddress, setAssetAddress] = useState("");
  const [amount, setAmount] = useState("");

  const asset = assetAddress as Address | undefined;
  const { data: allowance } = useTokenAllowance(
    assetAddress.length === 42 ? (assetAddress as Address) : undefined,
    userAddress,
    hubAddress
  );
  const { approve, isPending: isApproving } = useApproveToken();
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const parsedAmount = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = allowance !== undefined && parsedAmount > allowance;

  function handleSubmit() {
    if (!assetAddress || !amount) return;
    if (needsApproval) {
      approve(assetAddress as Address, hubAddress);
      return;
    }
    writeContract({
      address: hubAddress,
      abi: NexusHubAbi,
      functionName: "depositCollateral",
      args: [assetAddress as Address, parsedAmount],
    });
  }

  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <h4 className="text-sm text-zinc-400 mb-2">Deposit New Asset</h4>
      <div className="flex gap-2 flex-wrap">
        <input
          type="text" value={assetAddress} onChange={(e) => setAssetAddress(e.target.value)}
          placeholder="Asset address (0x...)"
          className="flex-1 min-w-48 px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
        />
        <input
          type="text" value={amount} onChange={(e) => setAmount(e.target.value)}
          placeholder="Amount"
          className="w-32 px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
        />
        <button
          onClick={handleSubmit}
          disabled={isPending || isApproving || !assetAddress || !amount}
          className="px-3 py-1 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
        >
          {isPending ? "Pending..." : isApproving ? "Approving..." : needsApproval ? "Approve" : isSuccess ? "Done" : "Deposit"}
        </button>
      </div>
    </div>
  );
}
