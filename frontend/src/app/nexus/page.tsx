"use client";

import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { NexusHubAbi } from "@/lib/contracts/abis/NexusHub";
import { getAddresses } from "@/lib/contracts/addresses";

const hubAddress = getAddresses().nexusHub;

const collateral = [
  { asset: "USDC", chain: "C-Chain", value: "$50,000", pct: 50 },
  { asset: "Senior Tranche Token", chain: "Forge Vault", value: "$30,000", pct: 30 },
  { asset: "AVAX", chain: "L1 via ICM", value: "$20,000", pct: 20 },
];

export default function NexusPage() {
  const { address, isConnected } = useAccount();
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  if (!isConnected) {
    return (
      <div className="text-center py-20">
        <h2 className="text-xl font-semibold mb-2">Connect Wallet</h2>
        <p className="text-zinc-500 text-sm mb-6">
          Connect your wallet to view your cross-chain margin account.
        </p>
        <ConnectButton />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h2 className="text-lg font-medium">Cross-Chain Margin</h2>
        <p className="text-sm text-zinc-500">
          Unified margin engine across Avalanche L1s via ICM/Teleporter
        </p>
      </div>

      {/* Margin Account Card */}
      <div className="relative bg-[var(--card-bg)] border border-[var(--card-border)] rounded-2xl overflow-hidden">
        {/* Gradient accent bar */}
        <div className="h-1 w-full bg-gradient-to-r from-cyan-500 to-blue-500" />

        <div className="p-6 space-y-6">
          {/* Health Factor */}
          <div className="text-center">
            <p className="text-xs uppercase tracking-wider text-zinc-500 mb-1">Health Factor</p>
            <p className="text-4xl font-bold text-green-400">1.85</p>
          </div>

          {/* Key Metrics */}
          <div className="grid grid-cols-3 gap-4 text-center">
            <div>
              <p className="text-xs text-zinc-500 mb-1">Total Collateral</p>
              <p className="text-lg font-semibold">$100,000</p>
            </div>
            <div>
              <p className="text-xs text-zinc-500 mb-1">Total Debt</p>
              <p className="text-lg font-semibold">$54,000</p>
            </div>
            <div>
              <p className="text-xs text-zinc-500 mb-1">Available to Borrow</p>
              <p className="text-lg font-semibold text-green-400">$46,000</p>
            </div>
          </div>

          {/* Collateral Breakdown */}
          <div>
            <h3 className="text-sm font-medium text-zinc-400 mb-3">Collateral Breakdown</h3>
            <div className="space-y-3">
              {collateral.map((c) => (
                <div key={c.asset}>
                  <div className="flex items-center justify-between text-sm mb-1">
                    <span>
                      {c.asset}{" "}
                      <span className="text-zinc-500 text-xs">({c.chain})</span>
                    </span>
                    <span className="font-medium">
                      {c.value}{" "}
                      <span className="text-zinc-500 text-xs">({c.pct}%)</span>
                    </span>
                  </div>
                  <div className="w-full h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-gradient-to-r from-cyan-500 to-blue-500 rounded-full"
                      style={{ width: `${c.pct}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Liquidation Threshold */}
          <div className="flex items-center justify-between bg-zinc-900/60 border border-zinc-800 rounded-xl px-4 py-3">
            <span className="text-sm text-zinc-400">Liquidation Threshold</span>
            <span className="text-sm font-semibold text-amber-400">110%</span>
          </div>

          {/* Open Account Button */}
          <button
            onClick={() =>
              writeContract({
                address: hubAddress,
                abi: NexusHubAbi,
                functionName: "openMarginAccount",
              })
            }
            disabled={isPending}
            className="w-full py-3 text-sm font-medium bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded-xl transition-colors"
          >
            {isPending ? "Opening..." : isSuccess ? "Account Opened!" : "Open Margin Account"}
          </button>
        </div>
      </div>
    </div>
  );
}
