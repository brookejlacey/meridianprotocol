"use client";

import { use, useState } from "react";
import { type Address, parseUnits, zeroAddress } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useIndexedCDSDetail } from "@/hooks/indexer/useIndexedCDS";
import { useApproveToken, useTokenAllowance } from "@/hooks/useApproveToken";
import { CDSContractAbi } from "@/lib/contracts/abis/CDSContract";
import { formatAmount, formatBps, shortenAddress, formatDate } from "@/lib/utils";
import Link from "next/link";

function formatStaticAmount(value: string): string {
  return formatAmount(BigInt(value));
}

export default function CDSDetailPage({ params }: { params: Promise<{ cdsId: string }> }) {
  const { cdsId } = use(params);
  const { data: cds, isLoading } = useIndexedCDSDetail(cdsId);

  if (isLoading) {
    return <div className="text-zinc-500">Loading CDS contract...</div>;
  }

  if (!cds) {
    return <div className="text-zinc-500">CDS contract not found</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link href="/shield" className="text-zinc-500 hover:text-white text-sm">&larr; Back</Link>
        <h2 className="text-lg font-medium">CDS #{cdsId}</h2>
        <span className={`text-xs px-2 py-0.5 rounded font-medium ${
          cds.status === "Active" ? "bg-green-500/20 text-green-400" :
          cds.status === "Settled" ? "bg-[var(--accent)]/15 text-[var(--accent)]" :
          "bg-zinc-500/20 text-zinc-400"
        }`}>
          {cds.status}
        </span>
      </div>
      <div className="text-xs text-zinc-500 font-mono -mt-4">{cds.id}</div>

      <CDSActions cds={cds} />
    </div>
  );
}

function CDSActions({ cds }: { cds: NonNullable<ReturnType<typeof useIndexedCDSDetail>["data"]> }) {
  const { address: userAddress } = useAccount();
  const cdsAddress = cds.id as Address;
  const { approve, isPending: isApproving } = useApproveToken();
  // Use MockUSDC as collateral token for approvals
  const collateralToken = "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f" as Address;
  const { data: allowance } = useTokenAllowance(collateralToken, userAddress, cdsAddress);

  const [amount, setAmount] = useState("");
  const [maxPremium, setMaxPremium] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash });

  const hasBuyer = cds.buyer && cds.buyer !== zeroAddress;
  const hasSeller = cds.seller && cds.seller !== zeroAddress;
  const isActive = cds.status === "Active";
  const isSettled = cds.status === "Settled";
  const maturitySec = Number(BigInt(cds.maturity));
  const nowSec = Math.floor(Date.now() / 1000);
  const daysLeft = maturitySec > nowSec ? Math.floor((maturitySec - nowSec) / 86400) : 0;

  return (
    <>
      {/* Info Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <InfoBox label="Status" value={cds.status} />
        <InfoBox label="Reference Vault" value={shortenAddress(cds.referenceVaultId)} />
        <InfoBox label="Protection Amount" value={formatStaticAmount(cds.protectionAmount)} />
        <InfoBox label="Premium Rate" value={formatBps(Number(cds.premiumRate))} />
        <InfoBox label="Maturity" value={formatDate(BigInt(cds.maturity))} />
        <InfoBox label="Time Left" value={daysLeft > 0 ? `${daysLeft} days` : "Expired"} />
        <InfoBox label="Collateral Posted" value={formatStaticAmount(cds.collateralPosted)} />
        <InfoBox label="Total Premium Paid" value={formatStaticAmount(cds.totalPremiumPaid)} />
      </div>

      {/* Participants */}
      <div className="grid grid-cols-2 gap-4">
        <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <div className="text-xs text-zinc-500 mb-1">Protection Buyer</div>
          <div className="text-sm font-mono">{hasBuyer ? shortenAddress(cds.buyer!) : "None"}</div>
        </div>
        <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
          <div className="text-xs text-zinc-500 mb-1">Protection Seller</div>
          <div className="text-sm font-mono">{hasSeller ? shortenAddress(cds.seller!) : "None"}</div>
        </div>
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
                if (allowance !== undefined && parseUnits(amount || "0", 18) > allowance) {
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
                if (allowance !== undefined && parseUnits(amount || "0", 18) > allowance) {
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

        {isActive && hasBuyer && hasSeller && (
          <ActionRow label="Pay Premium">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "payPremium" })}
              isPending={isPending} isSuccess={isSuccess} label="Pay Premium"
            />
          </ActionRow>
        )}

        {isActive && hasBuyer && hasSeller && (
          <ActionRow label="Trigger Credit Event">
            <ActionButton
              onClick={() => writeContract({ address: cdsAddress, abi: CDSContractAbi, functionName: "triggerCreditEvent" })}
              isPending={isPending} isSuccess={isSuccess} label="Trigger Event"
            />
          </ActionRow>
        )}

        {isSettled && (
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
    </>
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
