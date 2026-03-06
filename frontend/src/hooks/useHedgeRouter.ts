"use client";

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address, parseUnits } from "viem";
import { HedgeRouterAbi } from "@/lib/contracts/abis/HedgeRouter";

const HEDGE_ROUTER = process.env.NEXT_PUBLIC_HEDGE_ROUTER as Address | undefined;

export function useQuoteHedge(
  vault: Address | undefined,
  investAmount: bigint | undefined,
  tenorDays: bigint | undefined
) {
  return useReadContract({
    address: HEDGE_ROUTER,
    abi: HedgeRouterAbi,
    functionName: "quoteHedge",
    args: vault && investAmount && tenorDays ? [vault, investAmount, tenorDays] : undefined,
    query: {
      enabled: !!HEDGE_ROUTER && !!vault && !!investAmount && investAmount > 0n && !!tenorDays,
    },
  });
}

export function useInvestAndHedge() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  function investAndHedge(params: {
    vault: Address;
    trancheId: number;
    investAmount: bigint;
    cds: Address;
    maxPremium: bigint;
  }) {
    if (!HEDGE_ROUTER) return;
    writeContract({
      address: HEDGE_ROUTER,
      abi: HedgeRouterAbi,
      functionName: "investAndHedge",
      args: [{
        vault: params.vault,
        trancheId: params.trancheId,
        investAmount: params.investAmount,
        cds: params.cds,
        maxPremium: params.maxPremium,
      }],
    });
  }

  return { investAndHedge, isPending, isConfirmed, hash };
}
