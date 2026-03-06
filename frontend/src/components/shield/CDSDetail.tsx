"use client";

import { useState } from "react";
import { type Address, parseUnits, zeroAddress } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import {
  useCDSStatus, useCDSTerms, useCDSBuyer, useCDSSeller,
  useAccruedPremium, useTimeToMaturity, useIsFullyMatched,
  useCollateralPosted, useBuyerPremiumDeposit,
} from "@/hooks/useCDSContract";
import { useApproveToken, useTokenAllowance } from "@/hooks/useApproveToken";
import { CDSContractAbi } from "@/lib/contracts/abis/CDSContract";
import { formatAmount, formatBps, CDSStatus, shortenAddress, formatDate } from "@/lib/utils";

export function CDSDetail({ cdsAddress }: { cdsAddress: Address }) {
  const { address: userAddress } = useAccount();
  const { data: status } = useCDSStatus(cdsAddress);
  const { data: terms } = useCDSTerms(cdsAddress);
  const { data: buyer } = useCDSBuyer(cdsAddress);
  const { data: seller } = useCDSSeller(cdsAddress);
  const { data: accrued } = useAccruedPremium(cdsAddress);
  const { data: ttm } = useTimeToMaturity(cdsAddress);
  const { data: matched } = useIsFullyMatched(cdsAddress);
  const { data: collateral } = useCollateralPosted(cdsAddress);
  const { data: premiumDeposit } = useBuyerPremiumDeposit(cdsAddress);

  const collateralToken = terms?.[4] as Address | undefined;
  const { data: allowance } = useTokenAllowance(collateralToken, userAddress, cdsAddress);
  const { approve, isPending: isApproving } = useApproveToken();

  const [amount, setAmount] = useState("");
  const [maxPremium, setMaxPremium] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const hasBuyer = buyer && buyer !== zeroAddress;
  const hasSeller = seller && seller !== zeroAddress;
  const isActive = status === 0;
  const isTriggered = status === 1;
  const daysLeft = ttm !== undefined ? Math.floor(Number(ttm) / 86400) : null;

  return (
    <div className="space-y-6">
      {/* Info Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <InfoBox label="Status" value={status !== undefined ? CDSStatus[status as keyof typeof CDSStatus] ?? "Unknown" : "..."} />
        <InfoBox label="Reference Asset" value={terms ? shortenAddress(terms[0]) : "..."} />
        <InfoBox label="Protection Amount" value={terms ? formatAmount(terms[1]) : "..."} />
        <InfoBox label="Premium Rate" value={terms ? formatBps(terms[2]) : "..."} />
        <InfoBox label="Maturity" value={terms ? formatDate(terms[3]) : "..."} />
        <InfoBox label="Time Left" value={daysLeft !== null ? `${daysLeft} days` : "..."} />
        <InfoBox label="Collateral Token" value={terms ? shortenAddress(terms[4]) : "..."} />
        <InfoBox label="Fully Matched" value={matched !== undefined ? (matched ? "Yes" : "No") : "..."} />
      </div>

      {/* Participants */}
      <div className="grid grid-cols-2 gap-4">
        <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <div className="text-xs text-zinc-500 mb-1">Protection Buyer</div>
          <div className="text-sm font-mono">{hasBuyer ? shortenAddress(buyer!) : "None"}</div>
          <div className="text-xs text-zinc-500 mt-1">
            Premium Deposit: {premiumDeposit !== undefined ? formatAmount(premiumDeposit) : "..."}
          </div>
        </div>
        <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <div className="text-xs text-zinc-500 mb-1">Protection Seller</div>
          <div className="text-sm font-mono">{hasSeller ? shortenAddress(seller!) : "None"}</div>
          <div className="text-xs text-zinc-500 mt-1">
            Collateral: {collateral !== undefined ? formatAmount(collateral) : "..."}
          </div>
        </div>
      </div>

      {/* Accrued Premium */}
      <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
        <div className="text-xs text-zinc-500 mb-1">Accrued Premium (owed to seller)</div>
        <div className="text-sm font-mono">{accrued !== undefined ? formatAmount(accrued) : "..."}</div>
      </div>

      {/* Actions */}
      <div className="space-y-3 pt-4 border-t border-[var(--card-border)]">
        <h3 className="text-sm font-medium text-zinc-400">Actions</h3>

        {isActive && !hasBuyer && (
          <ActionRow label="Buy Protection">
            <input
              type="text" value={amount} onChange={(e) => setAmount(e.target.value)}
              placeholder="Amount" className="input-field"
            />
            <input
              type="text" value={maxPremium} onChange={(e) => setMaxPremium(e.target.value)}
              placeholder="Max Premium" className="input-field"
            />
            <ActionButton
              onClick={() => {
                if (allowance !== undefined && collateralToken && parseUnits(amount || "0", 18) > allowance) {
                  approve(collateralToken, cdsAddress);
                } else {
                  writeContract({
                    address: cdsAddress, abi: CDSContractAbi, functionName: "buyProtection",
                    args: [parseUnits(amount || "0", 18), parseUnits(maxPremium || "0", 18)],
                  });
                }
              }}
              isPending={isPending || isApproving} isSuccess={isSuccess}
              label={isApproving ? "Approving..." : "Buy Protection"}
            />
          </ActionRow>
        )}

        {isActive && !hasSeller && (
          <ActionRow label="Sell Protection">
            <input
              type="text" value={amount} onChange={(e) => setAmount(e.target.value)}
              placeholder="Collateral Amount" className="input-field"
            />
            <ActionButton
              onClick={() => {
                if (allowance !== undefined && collateralToken && parseUnits(amount || "0", 18) > allowance) {
                  approve(collateralToken, cdsAddress);
                } else {
                  writeContract({
                    address: cdsAddress, abi: CDSContractAbi, functionName: "sellProtection",
                    args: [parseUnits(amount || "0", 18)],
                  });
                }
              }}
              isPending={isPending || isApproving} isSuccess={isSuccess}
              label={isApproving ? "Approving..." : "Sell Protection"}
            />
          </ActionRow>
        )}

        {isActive && matched && (
          <ActionRow label="Pay Premium">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "payPremium" })}
              isPending={isPending} isSuccess={isSuccess} label="Pay Premium"
            />
          </ActionRow>
        )}

        {isActive && matched && (
          <ActionRow label="Trigger Credit Event">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "triggerCreditEvent" })}
              isPending={isPending} isSuccess={isSuccess} label="Trigger Event"
            />
          </ActionRow>
        )}

        {isTriggered && (
          <ActionRow label="Settle">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "settle" })}
              isPending={isPending} isSuccess={isSuccess} label="Settle"
            />
          </ActionRow>
        )}

        {isActive && daysLeft === 0 && (
          <ActionRow label="Expire">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "expire" })}
              isPending={isPending} isSuccess={isSuccess} label="Expire Contract"
            />
          </ActionRow>
        )}
      </div>
    </div>
  );
}

function InfoBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="text-xs text-zinc-500 mb-1">{label}</div>
      <div className="text-sm font-mono font-medium">{value}</div>
    </div>
  );
}

function ActionRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-sm text-zinc-400 w-36">{label}</span>
      {children}
    </div>
  );
}

function ActionButton({
  onClick, isPending, isSuccess, label,
}: {
  onClick: () => void; isPending: boolean; isSuccess: boolean; label: string;
}) {
  return (
    <button
      onClick={onClick} disabled={isPending}
      className="px-3 py-1.5 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:bg-zinc-700 disabled:text-zinc-500 rounded transition-colors"
    >
      {isPending ? "Pending..." : isSuccess ? "Done" : label}
    </button>
  );
}
