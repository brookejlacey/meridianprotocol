"use client";

import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useHasAccount } from "@/hooks/useNexusHub";
import { AccountOverview } from "@/components/nexus/AccountOverview";
import { CollateralTable, DepositNewAsset } from "@/components/nexus/CollateralTable";
import { NexusHubAbi } from "@/lib/contracts/abis/NexusHub";
import { getAddresses } from "@/lib/contracts/addresses";

const hubAddress = getAddresses().nexusHub;

export default function NexusPage() {
  const { address, isConnected } = useAccount();
  const { data: hasAccount, isLoading } = useHasAccount(address);

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  if (!isConnected) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">Connect Wallet</h2>
        <p className="text-zinc-500 text-sm">Connect your wallet to view your margin account.</p>
      </div>
    );
  }

  if (isLoading) {
    return <div className="text-zinc-500">Loading account...</div>;
  }

  if (!hasAccount) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">No Margin Account</h2>
        <p className="text-zinc-500 text-sm mb-4">
          Open a margin account to deposit collateral and track your cross-chain positions.
        </p>
        <button
          onClick={() =>
            writeContract({
              address: hubAddress,
              abi: NexusHubAbi,
              functionName: "openMarginAccount",
            })
          }
          disabled={isPending}
          className="px-4 py-2 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
        >
          {isPending ? "Opening..." : isSuccess ? "Account Opened!" : "Open Margin Account"}
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h2 className="text-lg font-medium">Margin Account</h2>
      <AccountOverview user={address!} />
      <CollateralTable user={address!} />
      <DepositNewAsset />
    </div>
  );
}
