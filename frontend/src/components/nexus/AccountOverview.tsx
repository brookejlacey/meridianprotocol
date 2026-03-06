"use client";

import { type Address } from "viem";
import {
  useMarginRatio, useIsHealthy, useTotalCollateralValue,
  useLocalCollateralValue, useObligation,
} from "@/hooks/useNexusHub";
import { HealthFactor } from "./HealthFactor";
import { formatAmount } from "@/lib/utils";

export function AccountOverview({ user }: { user: Address }) {
  const { data: ratio } = useMarginRatio(user);
  const { data: healthy } = useIsHealthy(user);
  const { data: totalCollateral } = useTotalCollateralValue(user);
  const { data: localCollateral } = useLocalCollateralValue(user);
  const { data: obligation } = useObligation(user);

  const crossChain = totalCollateral !== undefined && localCollateral !== undefined
    ? totalCollateral - localCollateral
    : undefined;

  return (
    <div className="space-y-4">
      <HealthFactor ratio={ratio} isHealthy={healthy} />

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricBox label="Total Collateral" value={totalCollateral !== undefined ? formatAmount(totalCollateral) : "..."} />
        <MetricBox label="Local Collateral" value={localCollateral !== undefined ? formatAmount(localCollateral) : "..."} />
        <MetricBox label="Cross-Chain Collateral" value={crossChain !== undefined ? formatAmount(crossChain) : "..."} />
        <MetricBox label="Obligations" value={obligation !== undefined ? formatAmount(obligation) : "..."} />
      </div>
    </div>
  );
}

function MetricBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 rounded-lg border border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="text-xs text-zinc-500 mb-1">{label}</div>
      <div className="text-sm font-mono font-medium">{value}</div>
    </div>
  );
}
