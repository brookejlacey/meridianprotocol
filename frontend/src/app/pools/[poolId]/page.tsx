"use client";

import { use, useState } from "react";
import { type Address, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { useIndexedPoolDetail } from "@/hooks/indexer/useIndexedPools";
import { useApproveToken } from "@/hooks/useApproveToken";
import { usePoolDeposit, usePoolWithdraw, usePoolBuyProtection } from "@/hooks/useCDSPool";
import { formatAmount, formatWadPercent, shortenAddress, formatDate } from "@/lib/utils";
import Link from "next/link";

function formatStaticAmount(value: string): string {
  return formatAmount(BigInt(value));
}

export default function PoolDetailPage({ params }: { params: Promise<{ poolId: string }> }) {
  const { poolId } = use(params);
  const { data: pool, isLoading } = useIndexedPoolDetail(poolId);

  if (isLoading) {
    return <div className="text-zinc-500">Loading pool...</div>;
  }

  if (!pool) {
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
      <PoolDetailView pool={pool} />
    </div>
  );
}

function PoolDetailView({ pool }: { pool: NonNullable<ReturnType<typeof useIndexedPoolDetail>["data"]> }) {
  const { address: userAddress } = useAccount();
  const poolAddress = pool.id as Address;
  const collateralToken = pool.collateralToken as Address;

  const isActive = pool.status === "Active";
  const utilPct = Number(BigInt(pool.utilizationRate)) / 1e16;
  const utilColor = utilPct > 80 ? "text-red-400" : utilPct > 50 ? "text-yellow-400" : "text-green-400";
  const utilBarColor = utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500";

  // Form state
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawShares, setWithdrawShares] = useState("");
  const [protectionNotional, setProtectionNotional] = useState("");

  // Write hooks
  const { approve, isPending: isApproving } = useApproveToken();
  const { deposit, isPending: isDepositing, isConfirming: isConfirmingDeposit } = usePoolDeposit();
  const { withdraw, isPending: isWithdrawing, isConfirming: isConfirmingWithdraw } = usePoolWithdraw();
  const { buyProtection, isPending: isBuying, isConfirming: isConfirmingBuy } = usePoolBuyProtection();

  const handleDeposit = async () => {
    if (!depositAmount) return;
    const amount = parseUnits(depositAmount, 18);
    await approve(collateralToken, poolAddress);
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
    if (!protectionNotional) return;
    const notional = parseUnits(protectionNotional, 18);
    const maxPremium = notional / 10n; // rough estimate for slippage
    await approve(collateralToken, poolAddress);
    buyProtection(poolAddress, notional, maxPremium);
    setProtectionNotional("");
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-medium">CDS AMM Pool #{pool.poolId}</h2>
          <p className="text-sm text-zinc-500 font-mono">{shortenAddress(poolAddress, 8)}</p>
        </div>
        <span className={`text-xs px-3 py-1 rounded font-medium ${
          isActive ? "bg-green-500/20 text-green-400" : "bg-zinc-500/20 text-zinc-400"
        }`}>
          {pool.status}
        </span>
      </div>

      {/* Pool Metrics Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard label="Total Liquidity" value={formatStaticAmount(pool.totalLiquidity)} />
        <MetricCard label="Protection Sold" value={formatStaticAmount(pool.protectionSold)} />
        <MetricCard
          label="Current Spread"
          value={formatWadPercent(BigInt(pool.currentSpread))}
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
            className={`h-full rounded-full transition-all duration-500 ${utilBarColor}`}
            style={{ width: `${Math.min(utilPct, 100)}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-zinc-600 mt-1">
          <span>0%</span>
          <span>50%</span>
          <span>95% max</span>
        </div>
      </div>

      {/* Pool Terms */}
      <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] space-y-2">
        <h3 className="text-sm font-medium mb-3 text-zinc-300">Pool Terms</h3>
        <InfoRow label="Reference Asset" value={shortenAddress(pool.referenceAsset)} />
        <InfoRow label="Base Spread" value={formatWadPercent(BigInt(pool.baseSpread))} />
        <InfoRow label="Curve Slope" value={formatWadPercent(BigInt(pool.slope))} />
        <InfoRow label="Maturity" value={formatDate(BigInt(pool.maturity))} />
      </div>

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
            className="w-full px-3 py-2 rounded bg-zinc-800 border border-zinc-700 text-sm font-mono mb-3 focus:border-[var(--accent)] focus:outline-none"
          />
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
          <button
            onClick={handleBuyProtection}
            disabled={!protectionNotional || isBuying || isConfirmingBuy || isApproving}
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
