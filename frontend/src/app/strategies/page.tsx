"use client";

import { useAccount } from "wagmi";
import { type Address, formatUnits } from "viem";
import { useState } from "react";
import {
  useStrategyCount,
  useStrategy,
  useUserPositions,
  usePositionInfo,
  usePositionValue,
} from "@/hooks/useStrategyRouter";

const ROUTER_ADDRESS = (process.env.NEXT_PUBLIC_STRATEGY_ROUTER || "0x0000000000000000000000000000000000000000") as Address;

const TRANCHE_LABELS: Record<number, string> = { 0: "Senior", 1: "Mezzanine", 2: "Equity" };

function fmt(val: bigint | undefined) {
  if (!val) return "0.00";
  return Number(formatUnits(val, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function StrategyCard({ strategyId }: { strategyId: number }) {
  const { data } = useStrategy(ROUTER_ADDRESS, BigInt(strategyId));
  if (!data) return null;

  const [name, vaults, allocations, active] = data;

  return (
    <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="font-medium">{name || `Strategy #${strategyId}`}</h3>
        <span className={`text-xs px-2 py-0.5 rounded ${active ? "bg-green-900/50 text-green-400" : "bg-red-900/50 text-red-400"}`}>
          {active ? "Active" : "Paused"}
        </span>
      </div>
      <div className="space-y-2">
        {vaults.map((vault: string, i: number) => (
          <div key={vault} className="flex items-center justify-between text-sm">
            <span className="text-zinc-400 font-mono text-xs">{vault.slice(0, 10)}...</span>
            <span className="text-zinc-300">{Number(allocations[i]) / 100}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function PositionRow({ positionId }: { positionId: bigint }) {
  const { data: info } = usePositionInfo(ROUTER_ADDRESS, positionId);
  const { data: value } = usePositionValue(ROUTER_ADDRESS, positionId);
  const { data: strategy } = useStrategy(ROUTER_ADDRESS, info ? info[1] : undefined);

  if (!info) return null;

  const deposited = info[2];
  const currentValue = value || 0n;
  const pnl = Number(formatUnits(currentValue - deposited, 18));

  return (
    <tr className="border-t border-zinc-800">
      <td className="py-2 text-sm">{Number(positionId)}</td>
      <td className="py-2 text-sm">{strategy ? strategy[0] : `#${Number(info[1])}`}</td>
      <td className="py-2 text-sm text-right">{fmt(deposited)}</td>
      <td className="py-2 text-sm text-right">{fmt(currentValue)}</td>
      <td className={`py-2 text-sm text-right ${pnl >= 0 ? "text-green-400" : "text-red-400"}`}>
        {pnl >= 0 ? "+" : ""}{pnl.toFixed(2)}
      </td>
    </tr>
  );
}

export default function StrategiesPage() {
  const { address } = useAccount();
  const { data: stratCount, isLoading } = useStrategyCount(ROUTER_ADDRESS);
  const { data: positions } = useUserPositions(ROUTER_ADDRESS, address);

  const count = stratCount ? Number(stratCount) : 0;
  const positionIds = positions || [];

  if (isLoading) {
    return <div className="text-zinc-500">Loading strategies...</div>;
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h2 className="text-lg font-medium">Yield Strategies</h2>
        <p className="text-sm text-zinc-500">
          Auto-compounding vaults with multi-tranche allocation strategies
        </p>
      </div>

      {/* Strategies Grid */}
      <div>
        <h3 className="text-sm font-medium text-zinc-400 mb-3">Available Strategies ({count})</h3>
        {count === 0 ? (
          <p className="text-sm text-zinc-600">No strategies created yet. Deploy a StrategyRouter and create strategies.</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {Array.from({ length: count }, (_, i) => (
              <StrategyCard key={i} strategyId={i} />
            ))}
          </div>
        )}
      </div>

      {/* User Positions */}
      <div>
        <h3 className="text-sm font-medium text-zinc-400 mb-3">
          Your Positions ({positionIds.length})
        </h3>
        {!address ? (
          <p className="text-sm text-zinc-600">Connect wallet to view positions.</p>
        ) : positionIds.length === 0 ? (
          <p className="text-sm text-zinc-600">No open positions. Select a strategy above to get started.</p>
        ) : (
          <div className="bg-[var(--card-bg)] border border-[var(--card-border)] rounded-lg overflow-hidden">
            <table className="w-full">
              <thead>
                <tr className="text-xs text-zinc-500 text-left">
                  <th className="px-4 py-2">ID</th>
                  <th className="px-4 py-2">Strategy</th>
                  <th className="px-4 py-2 text-right">Deposited</th>
                  <th className="px-4 py-2 text-right">Current Value</th>
                  <th className="px-4 py-2 text-right">P&L</th>
                </tr>
              </thead>
              <tbody className="px-4">
                {positionIds.map((pid: bigint) => (
                  <PositionRow key={Number(pid)} positionId={pid} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Info Box */}
      <div className="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 text-sm text-zinc-400">
        <p className="font-medium text-zinc-300 mb-2">How Yield Strategies Work</p>
        <ul className="space-y-1 list-disc list-inside">
          <li>Each YieldVault wraps a ForgeVault tranche with ERC-4626 auto-compounding</li>
          <li>Strategies split capital across multiple YieldVaults by BPS allocation</li>
          <li>Keepers call <code className="text-zinc-300">compound()</code> to harvest and reinvest yield</li>
          <li>Rebalance between strategies anytime without closing your position</li>
        </ul>
      </div>
    </div>
  );
}
