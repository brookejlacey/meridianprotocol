import { useReadContract } from "wagmi";
import { ForgeFactoryAbi } from "@/lib/contracts/abis/ForgeFactory";
import { getAddresses } from "@/lib/contracts/addresses";

const address = getAddresses().forgeFactory;

export function useVaultCount() {
  return useReadContract({
    address,
    abi: ForgeFactoryAbi,
    functionName: "vaultCount",
  });
}

export function useVaultAddress(vaultId: bigint | undefined) {
  return useReadContract({
    address,
    abi: ForgeFactoryAbi,
    functionName: "getVault",
    args: vaultId !== undefined ? [vaultId] : undefined,
    query: { enabled: vaultId !== undefined },
  });
}
