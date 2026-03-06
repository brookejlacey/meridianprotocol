import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address, parseUnits } from "viem";
import { StrategyRouterAbi } from "@/lib/contracts/abis/StrategyRouter";

export function useStrategy(routerAddress: Address | undefined, strategyId: bigint | undefined) {
  return useReadContract({
    address: routerAddress,
    abi: StrategyRouterAbi,
    functionName: "getStrategy",
    args: strategyId !== undefined ? [strategyId] : undefined,
    query: { enabled: !!routerAddress && strategyId !== undefined },
  });
}

export function useStrategyCount(routerAddress: Address | undefined) {
  return useReadContract({
    address: routerAddress,
    abi: StrategyRouterAbi,
    functionName: "nextStrategyId",
    query: { enabled: !!routerAddress },
  });
}

export function useUserPositions(routerAddress: Address | undefined, user: Address | undefined) {
  return useReadContract({
    address: routerAddress,
    abi: StrategyRouterAbi,
    functionName: "getUserPositions",
    args: user ? [user] : undefined,
    query: { enabled: !!routerAddress && !!user },
  });
}

export function usePositionInfo(routerAddress: Address | undefined, positionId: bigint | undefined) {
  return useReadContract({
    address: routerAddress,
    abi: StrategyRouterAbi,
    functionName: "getPositionInfo",
    args: positionId !== undefined ? [positionId] : undefined,
    query: { enabled: !!routerAddress && positionId !== undefined },
  });
}

export function usePositionValue(routerAddress: Address | undefined, positionId: bigint | undefined) {
  return useReadContract({
    address: routerAddress,
    abi: StrategyRouterAbi,
    functionName: "getPositionValue",
    args: positionId !== undefined ? [positionId] : undefined,
    query: { enabled: !!routerAddress && positionId !== undefined },
  });
}

export function useOpenPosition() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const openPosition = (routerAddress: Address, strategyId: bigint, amount: string) => {
    writeContract({
      address: routerAddress,
      abi: StrategyRouterAbi,
      functionName: "openPosition",
      args: [strategyId, parseUnits(amount, 18)],
    });
  };

  return { openPosition, isPending, isConfirming, isSuccess, hash };
}

export function useClosePosition() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const closePosition = (routerAddress: Address, positionId: bigint) => {
    writeContract({
      address: routerAddress,
      abi: StrategyRouterAbi,
      functionName: "closePosition",
      args: [positionId],
    });
  };

  return { closePosition, isPending, isConfirming, isSuccess, hash };
}

export function useRebalance() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const rebalance = (routerAddress: Address, positionId: bigint, newStrategyId: bigint) => {
    writeContract({
      address: routerAddress,
      abi: StrategyRouterAbi,
      functionName: "rebalance",
      args: [positionId, newStrategyId],
    });
  };

  return { rebalance, isPending, isConfirming, isSuccess, hash };
}
