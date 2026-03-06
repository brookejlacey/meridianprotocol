import { useReadContract } from "wagmi";
import { CDSPoolFactoryAbi } from "@/lib/contracts/abis/CDSPoolFactory";
import { getAddresses } from "@/lib/contracts/addresses";

const address = getAddresses().cdsPoolFactory;

export function usePoolCount() {
  return useReadContract({
    address,
    abi: CDSPoolFactoryAbi,
    functionName: "poolCount",
  });
}

export function usePoolAddress(poolId: bigint | undefined) {
  return useReadContract({
    address,
    abi: CDSPoolFactoryAbi,
    functionName: "getPool",
    args: poolId !== undefined ? [poolId] : undefined,
    query: { enabled: poolId !== undefined },
  });
}

export function usePoolsForVault(vaultAddress: `0x${string}` | undefined) {
  return useReadContract({
    address,
    abi: CDSPoolFactoryAbi,
    functionName: "getPoolsForVault",
    args: vaultAddress ? [vaultAddress] : undefined,
    query: { enabled: !!vaultAddress },
  });
}
