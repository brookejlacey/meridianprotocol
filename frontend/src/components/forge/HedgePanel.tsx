"use client";

import { useState } from "react";
import { type Address, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { useQuoteHedge, useInvestAndHedge } from "@/hooks/useHedgeRouter";
import { useTokenAllowance, useApproveToken } from "@/hooks/useApproveToken";
import { formatAmount, formatBps } from "@/lib/utils";

const HEDGE_ROUTER = process.env.NEXT_PUBLIC_HEDGE_ROUTER as Address | undefined;
const TRANCHE_NAMES = ["Senior", "Mezzanine", "Equity"] as const;

export function HedgePanel({ vaultAddress }: { vaultAddress: Address }) {
  const { address: userAddress } = useAccount();
  const [trancheId, setTrancheId] = useState(0);
  const [amount, setAmount] = useState("");
  const [cdsAddress, setCdsAddress] = useState("");
  const [tenorDays, setTenorDays] = useState("365");

  const parsedAmount = amount ? parseUnits(amount, 18) : 0n;
  const parsedTenor = BigInt(Number(tenorDays) || 365);

  const { data: quote } = useQuoteHedge(
    vaultAddress,
    parsedAmount > 0n ? parsedAmount : undefined,
    parsedAmount > 0n ? parsedTenor : undefined
  );

  const mockUSDC = process.env.NEXT_PUBLIC_MOCK_USDC as Address | undefined;
  const { data: allowance } = useTokenAllowance(mockUSDC, userAddress, HEDGE_ROUTER);
  const { approve, isPending: isApproving } = useApproveToken();
  const { investAndHedge, isPending, isConfirmed } = useInvestAndHedge();

  const estimatedPremium = quote ? quote[1] : 0n;
  const totalNeeded = parsedAmount + (estimatedPremium * 120n / 100n); // 20% buffer
  const needsApproval = allowance !== undefined && totalNeeded > 0n && allowance < totalNeeded;

  function handleSubmit() {
    if (!amount || !cdsAddress || !HEDGE_ROUTER) return;

    if (needsApproval && mockUSDC) {
      approve(mockUSDC, HEDGE_ROUTER);
      return;
    }

    const maxPremium = estimatedPremium * 120n / 100n; // 20% slippage buffer

    investAndHedge({
      vault: vaultAddress,
      trancheId,
      investAmount: parsedAmount,
      cds: cdsAddress as Address,
      maxPremium,
    });
  }

  if (!HEDGE_ROUTER) {
    return (
      <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
        <h3 className="text-sm font-medium text-zinc-400 mb-2">Invest & Hedge</h3>
        <p className="text-xs text-zinc-500">HedgeRouter not deployed. Set NEXT_PUBLIC_HEDGE_ROUTER in .env.local.</p>
      </div>
    );
  }

  return (
    <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <h3 className="text-sm font-medium text-zinc-400 mb-3">Invest & Hedge (Atomic)</h3>
      <div className="space-y-3">
        <div className="flex gap-1">
          {TRANCHE_NAMES.map((name, i) => (
            <button
              key={i}
              onClick={() => setTrancheId(i)}
              className={`text-xs px-2 py-1 rounded transition-colors ${
                trancheId === i
                  ? "bg-[var(--accent)] text-black"
                  : "bg-zinc-800 text-zinc-400 hover:text-white"
              }`}
            >
              {name}
            </button>
          ))}
        </div>

        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs text-zinc-500 block mb-1">Invest Amount</label>
            <input
              type="text"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="100000"
              className="w-full px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
            />
          </div>
          <div>
            <label className="text-xs text-zinc-500 block mb-1">Tenor (days)</label>
            <input
              type="text"
              value={tenorDays}
              onChange={(e) => setTenorDays(e.target.value)}
              placeholder="365"
              className="w-full px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none"
            />
          </div>
        </div>

        <div>
          <label className="text-xs text-zinc-500 block mb-1">CDS Contract Address</label>
          <input
            type="text"
            value={cdsAddress}
            onChange={(e) => setCdsAddress(e.target.value)}
            placeholder="0x..."
            className="w-full px-2 py-1 text-sm bg-zinc-900 border border-zinc-700 rounded focus:border-[var(--accent)] outline-none font-mono"
          />
        </div>

        {quote && parsedAmount > 0n && (
          <div className="p-2 bg-zinc-900 rounded text-xs space-y-1">
            <div className="flex justify-between">
              <span className="text-zinc-500">Indicative Spread</span>
              <span className="font-mono">{formatBps(Number(quote[0]))}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-zinc-500">Estimated Premium</span>
              <span className="font-mono">{formatAmount(quote[1])}</span>
            </div>
            <div className="flex justify-between border-t border-zinc-800 pt-1">
              <span className="text-zinc-500">Total Cost (invest + premium)</span>
              <span className="font-mono">{formatAmount(parsedAmount + quote[1])}</span>
            </div>
          </div>
        )}

        <button
          onClick={handleSubmit}
          disabled={isPending || isApproving || !amount || !cdsAddress}
          className="w-full px-3 py-2 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
        >
          {isPending
            ? "Executing..."
            : isApproving
            ? "Approving..."
            : needsApproval
            ? "Approve Token"
            : isConfirmed
            ? "Hedge Executed"
            : "Invest & Hedge"}
        </button>
      </div>
    </div>
  );
}
