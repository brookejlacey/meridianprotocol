import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address } from "viem";
import { CDSPoolAbi } from "@/lib/contracts/abis/CDSPool";

// --- Read Hooks ---

export function usePoolStatus(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "getPoolStatus",
    query: { enabled: !!poolAddress },
  });
}

export function usePoolTerms(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "getPoolTerms",
    query: { enabled: !!poolAddress },
  });
}

export function useTotalAssets(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "totalAssets",
    query: { enabled: !!poolAddress },
  });
}

export function useTotalShares(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "totalShares",
    query: { enabled: !!poolAddress },
  });
}

export function useUtilizationRate(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "utilizationRate",
    query: { enabled: !!poolAddress },
  });
}

export function useCurrentSpread(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "currentSpread",
    query: { enabled: !!poolAddress },
  });
}

export function useQuoteProtection(poolAddress: Address | undefined, notional: bigint | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "quoteProtection",
    args: notional !== undefined ? [notional] : undefined,
    query: { enabled: !!poolAddress && notional !== undefined && notional > 0n },
  });
}

export function useTotalProtectionSold(poolAddress: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "totalProtectionSold",
    query: { enabled: !!poolAddress },
  });
}

export function useSharesOf(poolAddress: Address | undefined, lp: Address | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "sharesOf",
    args: lp ? [lp] : undefined,
    query: { enabled: !!poolAddress && !!lp },
  });
}

export function useConvertToAssets(poolAddress: Address | undefined, shares: bigint | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "convertToAssets",
    args: shares !== undefined ? [shares] : undefined,
    query: { enabled: !!poolAddress && shares !== undefined },
  });
}

export function usePoolPosition(poolAddress: Address | undefined, positionId: bigint | undefined) {
  return useReadContract({
    address: poolAddress,
    abi: CDSPoolAbi,
    functionName: "getPosition",
    args: positionId !== undefined ? [positionId] : undefined,
    query: { enabled: !!poolAddress && positionId !== undefined },
  });
}

// --- Write Hooks ---

export function usePoolDeposit() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  return {
    deposit: (poolAddress: Address, amount: bigint) =>
      writeContract({
        address: poolAddress,
        abi: CDSPoolAbi,
        functionName: "deposit",
        args: [amount],
      }),
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  };
}

export function usePoolWithdraw() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  return {
    withdraw: (poolAddress: Address, shares: bigint) =>
      writeContract({
        address: poolAddress,
        abi: CDSPoolAbi,
        functionName: "withdraw",
        args: [shares],
      }),
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  };
}

export function usePoolBuyProtection() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  return {
    buyProtection: (poolAddress: Address, notional: bigint, maxPremium: bigint) =>
      writeContract({
        address: poolAddress,
        abi: CDSPoolAbi,
        functionName: "buyProtection",
        args: [notional, maxPremium],
      }),
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  };
}

export function usePoolCloseProtection() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  return {
    closeProtection: (poolAddress: Address, positionId: bigint) =>
      writeContract({
        address: poolAddress,
        abi: CDSPoolAbi,
        functionName: "closeProtection",
        args: [positionId],
      }),
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  };
}
