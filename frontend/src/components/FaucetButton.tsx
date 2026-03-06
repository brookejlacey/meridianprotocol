"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { parseEther, formatEther, type Address } from "viem";
import { MockUSDCAbi } from "@/lib/contracts/abis/MockUSDC";

const MOCK_USDC = (process.env.NEXT_PUBLIC_MOCK_USDC || "0x0000000000000000000000000000000000000000") as Address;
const FAUCET_AMOUNT = parseEther("100000"); // 100k USDC per drip

export function FaucetButton() {
  const { address, isConnected } = useAccount();
  const [showBalance, setShowBalance] = useState(false);

  const { data: balance } = useReadContract({
    address: MOCK_USDC,
    abi: MockUSDCAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { writeContract, data: txHash, isPending } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const handleMint = () => {
    if (!address) return;
    writeContract({
      address: MOCK_USDC,
      abi: MockUSDCAbi,
      functionName: "mint",
      args: [address, FAUCET_AMOUNT],
    });
  };

  if (!isConnected) return null;

  return (
    <div className="flex items-center gap-2">
      {showBalance && balance !== undefined && (
        <span className="text-xs text-zinc-500">
          {Number(formatEther(balance as bigint)).toLocaleString()} USDC
        </span>
      )}
      <button
        onClick={handleMint}
        onMouseEnter={() => setShowBalance(true)}
        onMouseLeave={() => setShowBalance(false)}
        disabled={isPending || isConfirming}
        className="px-3 py-1.5 text-xs font-medium rounded-lg bg-emerald-600 hover:bg-emerald-700 disabled:bg-zinc-700 disabled:text-zinc-500 text-white transition-colors"
      >
        {isPending
          ? "Confirming..."
          : isConfirming
          ? "Minting..."
          : isSuccess
          ? "Minted 100k USDC"
          : "Faucet 100k USDC"}
      </button>
    </div>
  );
}
