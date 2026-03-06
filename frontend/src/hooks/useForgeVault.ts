import { useReadContract } from "wagmi";
import { type Address } from "viem";
import { ForgeVaultAbi } from "@/lib/contracts/abis/ForgeVault";

export function usePoolMetrics(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: ForgeVaultAbi,
    functionName: "getPoolMetrics",
    query: { enabled: !!vaultAddress },
  });
}

export function useTrancheParams(vaultAddress: Address | undefined, trancheId: number) {
  return useReadContract({
    address: vaultAddress,
    abi: ForgeVaultAbi,
    functionName: "getTrancheParams",
    args: [trancheId],
    query: { enabled: !!vaultAddress },
  });
}

export function useClaimableYield(
  vaultAddress: Address | undefined,
  investor: Address | undefined,
  trancheId: number
) {
  return useReadContract({
    address: vaultAddress,
    abi: ForgeVaultAbi,
    functionName: "getClaimableYield",
    args: investor ? [investor, trancheId] : undefined,
    query: { enabled: !!vaultAddress && !!investor },
  });
}

export function useVaultOriginator(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: ForgeVaultAbi,
    functionName: "originator",
    query: { enabled: !!vaultAddress },
  });
}

export function usePoolStatus(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: ForgeVaultAbi,
    functionName: "poolStatus",
    query: { enabled: !!vaultAddress },
  });
}
