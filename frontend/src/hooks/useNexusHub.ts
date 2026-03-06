import { useReadContract } from "wagmi";
import { type Address } from "viem";
import { NexusHubAbi } from "@/lib/contracts/abis/NexusHub";
import { getAddresses } from "@/lib/contracts/addresses";

const address = getAddresses().nexusHub;

export function useHasAccount(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "hasAccount",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useMarginRatio(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "getMarginRatio",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useIsHealthy(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "isHealthy",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useTotalCollateralValue(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "getTotalCollateralValue",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useLocalCollateralValue(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "getLocalCollateralValue",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useUserAssets(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "getUserAssets",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}

export function useLocalDeposit(user: Address | undefined, asset: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "localDeposits",
    args: user && asset ? [user, asset] : undefined,
    query: { enabled: !!user && !!asset },
  });
}

export function useObligation(user: Address | undefined) {
  return useReadContract({
    address,
    abi: NexusHubAbi,
    functionName: "obligations",
    args: user ? [user] : undefined,
    query: { enabled: !!user },
  });
}
