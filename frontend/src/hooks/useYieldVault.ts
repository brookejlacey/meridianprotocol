import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address, parseUnits } from "viem";
import { YieldVaultAbi } from "@/lib/contracts/abis/YieldVault";

export function useYieldVaultMetrics(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: YieldVaultAbi,
    functionName: "getMetrics",
    query: { enabled: !!vaultAddress },
  });
}

export function useYieldVaultBalance(vaultAddress: Address | undefined, account: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: YieldVaultAbi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled: !!vaultAddress && !!account },
  });
}

export function useYieldVaultForgeVault(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: YieldVaultAbi,
    functionName: "forgeVault",
    query: { enabled: !!vaultAddress },
  });
}

export function useYieldVaultTrancheId(vaultAddress: Address | undefined) {
  return useReadContract({
    address: vaultAddress,
    abi: YieldVaultAbi,
    functionName: "trancheId",
    query: { enabled: !!vaultAddress },
  });
}

export function useYieldVaultDeposit() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const deposit = (vaultAddress: Address, amount: string, receiver: Address) => {
    writeContract({
      address: vaultAddress,
      abi: YieldVaultAbi,
      functionName: "deposit",
      args: [parseUnits(amount, 18), receiver],
    });
  };

  return { deposit, isPending, isConfirming, isSuccess, hash };
}

export function useYieldVaultRedeem() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const redeem = (vaultAddress: Address, shares: bigint, receiver: Address, owner: Address) => {
    writeContract({
      address: vaultAddress,
      abi: YieldVaultAbi,
      functionName: "redeem",
      args: [shares, receiver, owner],
    });
  };

  return { redeem, isPending, isConfirming, isSuccess, hash };
}

export function useYieldVaultCompound() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const compound = (vaultAddress: Address) => {
    writeContract({
      address: vaultAddress,
      abi: YieldVaultAbi,
      functionName: "compound",
    });
  };

  return { compound, isPending, isConfirming, isSuccess, hash };
}
