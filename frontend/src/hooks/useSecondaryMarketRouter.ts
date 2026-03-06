"use client";

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address } from "viem";
import { SecondaryMarketRouterAbi } from "@/lib/contracts/abis/SecondaryMarketRouter";

const ROUTER_ADDRESS = process.env.NEXT_PUBLIC_SECONDARY_MARKET_ROUTER as Address | undefined;

export function useQuoteSwap(
  tokenIn: Address | undefined,
  tokenOut: Address | undefined,
  amountIn: bigint | undefined
) {
  return useReadContract({
    address: ROUTER_ADDRESS,
    abi: SecondaryMarketRouterAbi,
    functionName: "quoteSwap",
    args: tokenIn && tokenOut && amountIn ? [tokenIn, tokenOut, amountIn] : undefined,
    query: {
      enabled: !!ROUTER_ADDRESS && !!tokenIn && !!tokenOut && !!amountIn && amountIn > 0n,
    },
  });
}

export function useSwap() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  function swap(params: {
    tokenIn: Address;
    tokenOut: Address;
    amountIn: bigint;
    minAmountOut: bigint;
  }) {
    if (!ROUTER_ADDRESS) return;
    writeContract({
      address: ROUTER_ADDRESS,
      abi: SecondaryMarketRouterAbi,
      functionName: "swap",
      args: [{
        tokenIn: params.tokenIn,
        tokenOut: params.tokenOut,
        amountIn: params.amountIn,
        minAmountOut: params.minAmountOut,
      }],
    });
  }

  return { swap, isPending, isConfirmed, hash };
}

export function useSwapAndReinvest() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  function swapAndReinvest(params: {
    tokenIn: Address;
    amountIn: bigint;
    minUnderlying: bigint;
    vault: Address;
    trancheId: number;
  }) {
    if (!ROUTER_ADDRESS) return;
    writeContract({
      address: ROUTER_ADDRESS,
      abi: SecondaryMarketRouterAbi,
      functionName: "swapAndReinvest",
      args: [{
        tokenIn: params.tokenIn,
        amountIn: params.amountIn,
        minUnderlying: params.minUnderlying,
        vault: params.vault,
        trancheId: params.trancheId,
      }],
    });
  }

  return { swapAndReinvest, isPending, isConfirmed, hash };
}

export function useSwapAndHedge() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  function swapAndHedge(params: {
    tokenIn: Address;
    amountIn: bigint;
    minUnderlying: bigint;
    vault: Address;
    trancheId: number;
    cds: Address;
    maxPremium: bigint;
  }) {
    if (!ROUTER_ADDRESS) return;
    writeContract({
      address: ROUTER_ADDRESS,
      abi: SecondaryMarketRouterAbi,
      functionName: "swapAndHedge",
      args: [{
        tokenIn: params.tokenIn,
        amountIn: params.amountIn,
        minUnderlying: params.minUnderlying,
        vault: params.vault,
        trancheId: params.trancheId,
        cds: params.cds,
        maxPremium: params.maxPremium,
      }],
    });
  }

  return { swapAndHedge, isPending, isConfirmed, hash };
}
