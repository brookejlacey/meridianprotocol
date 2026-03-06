"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { type Address, parseUnits, formatUnits } from "viem";
import { useQuoteSwap, useSwap, useSwapAndReinvest } from "@/hooks/useSecondaryMarketRouter";
import { useApproveToken } from "@/hooks/useApproveToken";

const ROUTER_DEPLOYED = !!process.env.NEXT_PUBLIC_SECONDARY_MARKET_ROUTER;

export default function TradePage() {
  const { address: userAddress } = useAccount();

  const [tokenIn, setTokenIn] = useState("");
  const [tokenOut, setTokenOut] = useState("");
  const [amountIn, setAmountIn] = useState("");
  const [slippage, setSlippage] = useState("1"); // 1%

  // Reinvest params
  const [reinvestVault, setReinvestVault] = useState("");
  const [reinvestTranche, setReinvestTranche] = useState("0");
  const [mode, setMode] = useState<"swap" | "reinvest">("swap");

  if (!ROUTER_DEPLOYED) {
    return (
      <div className="max-w-lg mx-auto text-center py-12">
        <h2 className="text-lg font-medium mb-2">Secondary Market</h2>
        <p className="text-sm text-zinc-500 mb-4">
          The SecondaryMarketRouter contract has not been deployed to Fuji yet.
          Tranche tokens are still tradeable as standard ERC-20s on any DEX.
        </p>
        <p className="text-xs text-zinc-600">
          Deploy via: <code className="text-zinc-400">forge script script/DeploySecondaryMarket.s.sol --rpc-url fuji --broadcast</code>
        </p>
      </div>
    );
  }

  const parsedAmount = amountIn ? parseUnits(amountIn, 18) : undefined;
  const tokenInAddr = tokenIn as Address | undefined;
  const tokenOutAddr = tokenOut as Address | undefined;

  const { data: quote } = useQuoteSwap(
    tokenInAddr || undefined,
    tokenOutAddr || undefined,
    parsedAmount
  );

  const { swap, isPending: isSwapping, isConfirmed: swapConfirmed } = useSwap();
  const { swapAndReinvest, isPending: isReinvesting, isConfirmed: reinvestConfirmed } = useSwapAndReinvest();

  const minOut = quote && slippage
    ? quote - (quote * BigInt(Math.floor(parseFloat(slippage) * 100))) / 10000n
    : 0n;

  function handleSwap() {
    if (!tokenInAddr || !tokenOutAddr || !parsedAmount) return;
    swap({
      tokenIn: tokenInAddr,
      tokenOut: tokenOutAddr,
      amountIn: parsedAmount,
      minAmountOut: minOut,
    });
  }

  function handleSwapAndReinvest() {
    if (!tokenInAddr || !parsedAmount || !reinvestVault) return;
    swapAndReinvest({
      tokenIn: tokenInAddr,
      amountIn: parsedAmount,
      minUnderlying: minOut,
      vault: reinvestVault as Address,
      trancheId: parseInt(reinvestTranche),
    });
  }

  return (
    <div className="max-w-lg mx-auto">
      <div className="mb-6">
        <h2 className="text-lg font-medium">Secondary Market</h2>
        <p className="text-sm text-zinc-500">
          Swap tranche tokens on DEX, or swap and reinvest into a different tranche
        </p>
      </div>

      {/* Mode selector */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setMode("swap")}
          className={`px-4 py-2 rounded text-sm font-medium ${
            mode === "swap"
              ? "bg-[var(--accent)] text-white"
              : "bg-zinc-800 text-zinc-400 hover:text-zinc-200"
          }`}
        >
          Swap
        </button>
        <button
          onClick={() => setMode("reinvest")}
          className={`px-4 py-2 rounded text-sm font-medium ${
            mode === "reinvest"
              ? "bg-[var(--accent)] text-white"
              : "bg-zinc-800 text-zinc-400 hover:text-zinc-200"
          }`}
        >
          Swap & Reinvest
        </button>
      </div>

      <div className="p-4 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)] space-y-4">
        {/* Token In */}
        <div>
          <label className="block text-xs text-zinc-500 mb-1">Token In (address)</label>
          <input
            type="text"
            value={tokenIn}
            onChange={(e) => setTokenIn(e.target.value)}
            placeholder="0x... tranche token or underlying"
            className="w-full px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white placeholder:text-zinc-600"
          />
        </div>

        {/* Token Out (swap only) */}
        {mode === "swap" && (
          <div>
            <label className="block text-xs text-zinc-500 mb-1">Token Out (address)</label>
            <input
              type="text"
              value={tokenOut}
              onChange={(e) => setTokenOut(e.target.value)}
              placeholder="0x... target token"
              className="w-full px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white placeholder:text-zinc-600"
            />
          </div>
        )}

        {/* Amount */}
        <div>
          <label className="block text-xs text-zinc-500 mb-1">Amount</label>
          <input
            type="text"
            value={amountIn}
            onChange={(e) => setAmountIn(e.target.value)}
            placeholder="0.0"
            className="w-full px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white placeholder:text-zinc-600"
          />
        </div>

        {/* Slippage */}
        <div>
          <label className="block text-xs text-zinc-500 mb-1">Slippage Tolerance (%)</label>
          <input
            type="text"
            value={slippage}
            onChange={(e) => setSlippage(e.target.value)}
            placeholder="1"
            className="w-24 px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white placeholder:text-zinc-600"
          />
        </div>

        {/* Reinvest fields */}
        {mode === "reinvest" && (
          <>
            <div>
              <label className="block text-xs text-zinc-500 mb-1">Target Vault (address)</label>
              <input
                type="text"
                value={reinvestVault}
                onChange={(e) => setReinvestVault(e.target.value)}
                placeholder="0x... ForgeVault address"
                className="w-full px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white placeholder:text-zinc-600"
              />
            </div>
            <div>
              <label className="block text-xs text-zinc-500 mb-1">Target Tranche</label>
              <select
                value={reinvestTranche}
                onChange={(e) => setReinvestTranche(e.target.value)}
                className="px-3 py-2 rounded bg-zinc-900 border border-zinc-700 text-sm text-white"
              >
                <option value="0">Senior</option>
                <option value="1">Mezzanine</option>
                <option value="2">Equity</option>
              </select>
            </div>
          </>
        )}

        {/* Quote display */}
        {quote !== undefined && (
          <div className="p-3 rounded bg-zinc-900 border border-zinc-800">
            <div className="flex justify-between text-sm">
              <span className="text-zinc-400">Expected Output</span>
              <span className="text-white font-mono">{formatUnits(quote, 18)}</span>
            </div>
            <div className="flex justify-between text-sm mt-1">
              <span className="text-zinc-400">Min Output ({slippage}% slippage)</span>
              <span className="text-zinc-300 font-mono">{formatUnits(minOut, 18)}</span>
            </div>
          </div>
        )}

        {/* Action button */}
        {!userAddress ? (
          <div className="text-center text-zinc-500 text-sm py-2">Connect wallet to trade</div>
        ) : mode === "swap" ? (
          <button
            onClick={handleSwap}
            disabled={isSwapping || !tokenIn || !tokenOut || !amountIn}
            className="w-full py-3 rounded bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium text-sm transition-colors"
          >
            {isSwapping ? "Swapping..." : swapConfirmed ? "Swapped!" : "Swap"}
          </button>
        ) : (
          <button
            onClick={handleSwapAndReinvest}
            disabled={isReinvesting || !tokenIn || !amountIn || !reinvestVault}
            className="w-full py-3 rounded bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium text-sm transition-colors"
          >
            {isReinvesting ? "Processing..." : reinvestConfirmed ? "Done!" : "Swap & Reinvest"}
          </button>
        )}
      </div>

      {/* Info */}
      <div className="mt-6 p-4 rounded-lg border border-zinc-800 bg-zinc-900/50">
        <h3 className="text-sm font-medium text-zinc-300 mb-2">How it works</h3>
        <ul className="text-xs text-zinc-500 space-y-1">
          <li>Tranche tokens are standard ERC-20, tradeable on any DEX</li>
          <li>Transfer hooks keep vault share mirrors in sync automatically</li>
          <li>Swap & Reinvest sells one tranche position and invests in another atomically</li>
          <li>You must approve the router to spend your tokens before trading</li>
        </ul>
      </div>
    </div>
  );
}
