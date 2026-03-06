import { useReadContract } from "wagmi";
import { ShieldFactoryAbi } from "@/lib/contracts/abis/ShieldFactory";
import { getAddresses } from "@/lib/contracts/addresses";

const address = getAddresses().shieldFactory;

export function useCDSCount() {
  return useReadContract({
    address,
    abi: ShieldFactoryAbi,
    functionName: "cdsCount",
  });
}

export function useCDSAddress(cdsId: bigint | undefined) {
  return useReadContract({
    address,
    abi: ShieldFactoryAbi,
    functionName: "getCDS",
    args: cdsId !== undefined ? [cdsId] : undefined,
    query: { enabled: cdsId !== undefined },
  });
}
