"use client";

import { useState } from "react";
import { type Address, parseUnits, formatUnits } from "viem";
import { useAccount } from "wagmi";
import {
  usePoolTerms,
  usePoolStatus,
  useTotalAssets,
  useTotalShares,
  useUtilizationRate,
  useCurrentSpread,
  useTotalProtectionSold,
  useSharesOf,
  useConvertToAssets,
  useQuoteProtection,
  usePoolDeposit,
  usePoolWithdraw,
  usePoolBuyProtection,
} from "@/hooks/useCDSPool";
import { useApproveToken } from "@/hooks/useApproveToken";
import { formatAmount, formatWadPercent, PoolStatus, shortenAddress, formatDate } from "@/lib/utils";

export function PoolDetail({ poolAddress }: { poolAddress: Address }) {
  const { address: userAddress } = useAccount();

  // Pool state
  const { data: terms } = usePoolTerms(poolAddress);
  const { data: status } = usePoolStatus(poolAddress);
  const { data: totalAssets } = useTotalAssets(poolAddress);
  const { data: totalShares } = useTotalShares(poolAddress);
  const { data: utilization } = useUtilizationRate(poolAddress);
  const { data: spread } = useCurrentSpread(poolAddress);
  const { data: protectionSold } = useTotalProtectionSold(poolAddress);

  // User LP state
  const { data: userShares } = useSharesOf(poolAddress, userAddress);
  const { data: userAssetsValue } = useConvertToAssets(poolAddress, userShares);

  // Form state
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawShares, setWithdrawShares] = useState("");
  const [protectionNotional, setProtectionNotional] = useState("");

  // Quote
  const notionalBn = protectionNotional ? parseUnits(protectionNotional, 18) : undefined;
  const { data: quote } = useQuoteProtection(poolAddress, notionalBn);

  // Write hooks
  const { approve, isPending: isApproving } = useApproveToken();
  const { deposit, isPending: isDepositing, isConfirming: isConfirmingDeposit } = usePoolDeposit();
  const { withdraw, isPending: isWithdrawing, isConfirming: isConfirmingWithdraw } = usePoolWithdraw();
  const { buyProtection, isPending: isBuying, isConfirming: isConfirmingBuy } = usePoolBuyProtection();

  const statusLabel = status !== undefined ? PoolStatus[status as keyof typeof PoolStatus] ?? "Unknown" : "...";
  const isActive = statusLabel === "Active";
  const utilPct = utilization !== undefined ? Math.min(Number(utilization) / 1e16, 100) : 0;
  const utilColor = utilPct > 80 ? "text-red-400" : utilPct > 50 ? "text-yellow-400" : "text-green-400";

  const handleDeposit = async () => {
    if (!terms || !depositAmount) return;
    const amount = parseUnits(depositAmount, 18);
    await approve(terms.collateralToken as Address, poolAddress);
    deposit(poolAddress, amount);
    setDepositAmount("");
  };

  const handleWithdraw = async () => {
    if (!withdrawShares) return;
    const shares = parseUnits(withdrawShares, 18);
    withdraw(poolAddress, shares);
    setWithdrawShares("");
  };

  const handleBuyProtection = async () => {
    if (!terms || !protectionNotional || quote === undefined) return;
    const notional = parseUnits(protectionNotional, 18);
    const maxPremium = quote + quote / 20n; // 5% slippage
    await approve(terms.collateralToken as Address, poolAddress);
    buyProtection(poolAddress, notional, maxPremium);
    setProtectionNotional("");
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-medium">CDS AMM Pool</h2>
          <p className="text-sm text-zinc-500 font-mono">{shortenAddress(poolAddress, 8)}</p>
        </div>
        <span className={`text-xs px-3 py-1 rounded font-medium ${
          isActive ? "bg-green-500/20 text-green-400" : "bg-zinc-500/20 text-zinc-400"
        }`}>
          {statusLabel}
        </span>
      </div>

      {/* Pool Metrics Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard
          label="Total Liquidity"
          value={totalAssets !== undefined ? formatAmount(totalAssets) : "..."}
        />
        <MetricCard
          label="Protection Sold"
          value={protectionSold !== undefined ? formatAmount(protectionSold) : "..."}
        />
        <MetricCard
          label="Current Spread"
          value={spread !== undefined ? formatWadPercent(spread) : "..."}
          className="text-[var(--accent)]"
        />
        <MetricCard
          label="Utilization"
          value={`${utilPct.toFixed(1)}%`}
          className={utilColor}
        />
      </div>

      {/* Utilization Gauge */}
      <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
        <div className="flex justify-between text-sm mb-2">
          <span className="text-zinc-400">Pool Utilization</span>
          <span className={`font-mono font-medium ${utilColor}`}>{utilPct.toFixed(1)}%</span>
        </div>
        <div className="h-3 bg-zinc-800 rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-500 ${
              utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500"
            }`}
            style={{ width: `${utilPct}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-zinc-600 mt-1">
          <span>0%</span>
          <span>50%</span>
          <span>95% max</span>
        </div>
      </div>

      {/* Pool Info */}
      <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] space-y-2">
        <h3 className="text-sm font-medium mb-3 text-zinc-300">Pool Terms</h3>
        <InfoRow label="Reference Asset" value={terms ? shortenAddress(terms.referenceAsset) : "..."} />
        <InfoRow label="Base Spread" value={terms ? formatWadPercent(terms.baseSpreadWad) : "..."} />
        <InfoRow label="Curve Slope" value={terms ? formatWadPercent(terms.slopeWad) : "..."} />
        <InfoRow label="Maturity" value={terms ? formatDate(terms.maturity) : "..."} />
        <InfoRow label="Total LP Shares" value={totalShares !== undefined ? formatAmount(totalShares) : "..."} />
      </div>

      {/* Your LP Position */}
      {userAddress && (
        <div className="p-4 rounded-lg border border-[var(--accent)]/30 bg-[var(--accent)]/5 space-y-2">
          <h3 className="text-sm font-medium mb-3 text-[var(--accent)]">Your LP Position</h3>
          <InfoRow label="Your Shares" value={userShares !== undefined ? formatAmount(userShares) : "0.00"} />
          <InfoRow
            label="Share Value"
            value={userAssetsValue !== undefined ? formatAmount(userAssetsValue) : "0.00"}
            className="text-green-400"
          />
        </div>
      )}

      {/* Action Panels */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* LP Deposit */}
        <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <h3 className="text-sm font-medium mb-3 text-zinc-300">Provide Liquidity</h3>
          <input
            type="text"
            placeholder="Amount to deposit"
            value={depositAmount}
            onChange={(e) => setDepositAmount(e.target.value)}
            className="w-full px-3 py-2 rounded bg-zinc-800 border border-zinc-700 text-sm font-mono mb-3 focus:border-[var(--accent)] focus:outline-none"
          />
          <button
            onClick={handleDeposit}
            disabled={!isActive || !depositAmount || isDepositing || isConfirmingDeposit || isApproving}
            className="w-full px-4 py-2 rounded bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
          >
            {isApproving ? "Approving..." : isDepositing ? "Depositing..." : isConfirmingDeposit ? "Confirming..." : "Deposit"}
          </button>
        </div>

        {/* LP Withdraw */}
        <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <h3 className="text-sm font-medium mb-3 text-zinc-300">Withdraw Liquidity</h3>
          <input
            type="text"
            placeholder="Shares to withdraw"
            value={withdrawShares}
            onChange={(e) => setWithdrawShares(e.target.value)}
            className="w-full px-3 py-2 rounded bg-zinc-800 border border-zinc-700 text-sm font-mono mb-2 focus:border-[var(--accent)] focus:outline-none"
          />
          {userShares !== undefined && userShares > 0n && (
            <button
              onClick={() => setWithdrawShares(formatUnits(userShares!, 18))}
              className="text-xs text-[var(--accent)] hover:text-[var(--accent)] mb-2"
            >
              Max: {formatAmount(userShares)}
            </button>
          )}
          <button
            onClick={handleWithdraw}
            disabled={!withdrawShares || isWithdrawing || isConfirmingWithdraw}
            className="w-full px-4 py-2 rounded bg-zinc-700 hover:bg-zinc-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
          >
            {isWithdrawing ? "Withdrawing..." : isConfirmingWithdraw ? "Confirming..." : "Withdraw"}
          </button>
        </div>
      </div>

      {/* Buy Protection */}
      {isActive && (
        <div className="p-4 rounded-lg border border-purple-500/30 bg-purple-500/5">
          <h3 className="text-sm font-medium mb-3 text-purple-300">Buy Protection</h3>
          <input
            type="text"
            placeholder="Protection notional"
            value={protectionNotional}
            onChange={(e) => setProtectionNotional(e.target.value)}
            className="w-full px-3 py-2 rounded bg-zinc-800 border border-zinc-700 text-sm font-mono mb-3 focus:border-purple-500 focus:outline-none"
          />
          {quote !== undefined && notionalBn && notionalBn > 0n && (
            <div className="p-3 rounded bg-zinc-800/50 mb-3 space-y-1">
              <div className="flex justify-between text-xs">
                <span className="text-zinc-400">Quoted Premium</span>
                <span className="font-mono text-purple-300">{formatAmount(quote)}</span>
              </div>
              <div className="flex justify-between text-xs">
                <span className="text-zinc-400">Effective Spread</span>
                <span className="font-mono text-purple-300">
                  {spread !== undefined ? formatWadPercent(spread) : "..."}
                </span>
              </div>
            </div>
          )}
          <button
            onClick={handleBuyProtection}
            disabled={!protectionNotional || quote === undefined || isBuying || isConfirmingBuy || isApproving}
            className="w-full px-4 py-2 rounded bg-purple-600 hover:bg-purple-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
          >
            {isApproving ? "Approving..." : isBuying ? "Buying..." : isConfirmingBuy ? "Confirming..." : "Buy Protection"}
          </button>
        </div>
      )}
    </div>
  );
}

function MetricCard({ label, value, className = "" }: { label: string; value: string; className?: string }) {
  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <p className="text-xs text-zinc-500 mb-1">{label}</p>
      <p className={`text-lg font-mono font-medium ${className}`}>{value}</p>
    </div>
  );
}

function InfoRow({ label, value, className = "" }: { label: string; value: string; className?: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-zinc-500">{label}</span>
      <span className={`font-mono ${className}`}>{value}</span>
    </div>
  );
}
