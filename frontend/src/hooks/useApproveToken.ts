import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address, maxUint256 } from "viem";
import { ERC20Abi } from "@/lib/contracts/abis/ERC20";

export function useTokenAllowance(
  token: Address | undefined,
  owner: Address | undefined,
  spender: Address | undefined
) {
  return useReadContract({
    address: token,
    abi: ERC20Abi,
    functionName: "allowance",
    args: owner && spender ? [owner, spender] : undefined,
    query: { enabled: !!token && !!owner && !!spender },
  });
}

export function useTokenBalance(token: Address | undefined, account: Address | undefined) {
  return useReadContract({
    address: token,
    abi: ERC20Abi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled: !!token && !!account },
  });
}

export function useApproveToken() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  function approve(token: Address, spender: Address) {
    writeContract({
      address: token,
      abi: ERC20Abi,
      functionName: "approve",
      args: [spender, maxUint256],
    });
  }

  return { approve, isPending, isConfirmed, hash };
}
