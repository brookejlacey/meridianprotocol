import { useReadContract } from "wagmi";
import { type Address } from "viem";
import { CDSContractAbi } from "@/lib/contracts/abis/CDSContract";

export function useCDSStatus(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "getStatus",
    query: { enabled: !!cdsAddress },
  });
}

export function useCDSTerms(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "terms",
    query: { enabled: !!cdsAddress },
  });
}

export function useCDSBuyer(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "buyer",
    query: { enabled: !!cdsAddress },
  });
}

export function useCDSSeller(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "seller",
    query: { enabled: !!cdsAddress },
  });
}

export function useAccruedPremium(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "getAccruedPremium",
    query: { enabled: !!cdsAddress },
  });
}

export function useTimeToMaturity(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "timeToMaturity",
    query: { enabled: !!cdsAddress },
  });
}

export function useIsFullyMatched(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "isFullyMatched",
    query: { enabled: !!cdsAddress },
  });
}

export function useCollateralPosted(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "collateralPosted",
    query: { enabled: !!cdsAddress },
  });
}

export function useBuyerPremiumDeposit(cdsAddress: Address | undefined) {
  return useReadContract({
    address: cdsAddress,
    abi: CDSContractAbi,
    functionName: "buyerPremiumDeposit",
    query: { enabled: !!cdsAddress },
  });
}
