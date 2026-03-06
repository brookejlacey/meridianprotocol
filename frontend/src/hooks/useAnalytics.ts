"use client";

import { useQuery } from "@tanstack/react-query";
import { usePoolCount, usePoolAddress } from "@/hooks/useCDSPoolFactory";
import {
  usePoolStatus,
  useTotalAssets,
  useUtilizationRate,
  useCurrentSpread,
  useTotalProtectionSold,
} from "@/hooks/useCDSPool";
import { type Address } from "viem";

// ---------- Types ----------

export interface VaultSummary {
  id: string;
  vaultId: string;
  status: string;
  totalDeposited: string;
  totalYieldReceived: string;
  totalYieldDistributed: string;
  tranches: {
    items: {
      trancheId: number;
      targetApr: string;
      allocationPct: string;
      totalInvested: string;
    }[];
  };
}

export interface CDSSummary {
  id: string;
  cdsId: string;
  status: string;
  protectionAmount: string;
  collateralPosted: string;
  totalPremiumPaid: string;
}

export interface ProtocolMetrics {
  totalVaultTVL: bigint;
  totalYieldGenerated: bigint;
  totalYieldDistributed: bigint;
  vaultCount: number;
  activeVaults: number;
  cdsCount: number;
  activeCDS: number;
  totalProtectionBilateral: bigint;
  totalCollateralPosted: bigint;
  totalPremiumsPaid: bigint;
  seniorTVL: bigint;
  mezzTVL: bigint;
  equityTVL: bigint;
  weightedAvgApr: number;
}

// ---------- Hooks ----------

// Hardcoded data matching deployed Fuji contracts + demo data
const STATIC_VAULTS: VaultSummary[] = [
  {
    id: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327",
    vaultId: "0",
    status: "Active",
    totalDeposited: "1700000000000000000000000",
    totalYieldReceived: "85000000000000000000000",
    totalYieldDistributed: "85000000000000000000000",
    tranches: {
      items: [
        { trancheId: 0, targetApr: "50000000000000000", allocationPct: "70", totalInvested: "1000000000000000000000000" },
        { trancheId: 1, targetApr: "80000000000000000", allocationPct: "20", totalInvested: "500000000000000000000000" },
        { trancheId: 2, targetApr: "150000000000000000", allocationPct: "10", totalInvested: "200000000000000000000000" },
      ],
    },
  },
  {
    id: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334",
    vaultId: "1",
    status: "Active",
    totalDeposited: "5200000000000000000000000",
    totalYieldReceived: "312000000000000000000000",
    totalYieldDistributed: "296000000000000000000000",
    tranches: {
      items: [
        { trancheId: 0, targetApr: "40000000000000000", allocationPct: "60", totalInvested: "3120000000000000000000000" },
        { trancheId: 1, targetApr: "100000000000000000", allocationPct: "25", totalInvested: "1300000000000000000000000" },
        { trancheId: 2, targetApr: "200000000000000000", allocationPct: "15", totalInvested: "780000000000000000000000" },
      ],
    },
  },
  {
    id: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A",
    vaultId: "2",
    status: "Active",
    totalDeposited: "850000000000000000000000",
    totalYieldReceived: "29750000000000000000000",
    totalYieldDistributed: "29750000000000000000000",
    tranches: {
      items: [
        { trancheId: 0, targetApr: "60000000000000000", allocationPct: "75", totalInvested: "637500000000000000000000" },
        { trancheId: 1, targetApr: "120000000000000000", allocationPct: "15", totalInvested: "127500000000000000000000" },
        { trancheId: 2, targetApr: "250000000000000000", allocationPct: "10", totalInvested: "85000000000000000000000" },
      ],
    },
  },
  {
    id: "0xE5F607182930A4B5C6D7E8F900112233445566BB",
    vaultId: "3",
    status: "Matured",
    totalDeposited: "2000000000000000000000000",
    totalYieldReceived: "180000000000000000000000",
    totalYieldDistributed: "180000000000000000000000",
    tranches: {
      items: [
        { trancheId: 0, targetApr: "45000000000000000", allocationPct: "70", totalInvested: "1400000000000000000000000" },
        { trancheId: 1, targetApr: "90000000000000000", allocationPct: "20", totalInvested: "400000000000000000000000" },
        { trancheId: 2, targetApr: "180000000000000000", allocationPct: "10", totalInvested: "200000000000000000000000" },
      ],
    },
  },
];

const STATIC_CDS: CDSSummary[] = [
  {
    id: "0x35d6fE4079400d4f0D3155ea7220D3279D3C7914",
    cdsId: "0",
    status: "Active",
    protectionAmount: "500000000000000000000000",
    collateralPosted: "500000000000000000000000",
    totalPremiumPaid: "15000000000000000000000",
  },
  {
    id: "0x4A5B6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B",
    cdsId: "1",
    status: "Active",
    protectionAmount: "1000000000000000000000000",
    collateralPosted: "1000000000000000000000000",
    totalPremiumPaid: "25000000000000000000000",
  },
  {
    id: "0x5B6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B4C",
    cdsId: "2",
    status: "Active",
    protectionAmount: "250000000000000000000000",
    collateralPosted: "250000000000000000000000",
    totalPremiumPaid: "8750000000000000000000",
  },
  {
    id: "0x6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D",
    cdsId: "3",
    status: "Settled",
    protectionAmount: "750000000000000000000000",
    collateralPosted: "750000000000000000000000",
    totalPremiumPaid: "45000000000000000000000",
  },
];

/** Fetch protocol-wide aggregate metrics */
export function useProtocolMetrics() {
  return useQuery({
    queryKey: ["protocol-metrics"],
    queryFn: async (): Promise<ProtocolMetrics> => {
      const vaults = STATIC_VAULTS;
      const cds = STATIC_CDS;

      let totalVaultTVL = 0n;
      let totalYieldGenerated = 0n;
      let totalYieldDistributed = 0n;
      let activeVaults = 0;
      let seniorTVL = 0n;
      let mezzTVL = 0n;
      let equityTVL = 0n;
      let totalWeightedApr = 0n;
      let totalInvested = 0n;

      for (const v of vaults) {
        const deposited = BigInt(v.totalDeposited || "0");
        totalVaultTVL += deposited;
        totalYieldGenerated += BigInt(v.totalYieldReceived || "0");
        totalYieldDistributed += BigInt(v.totalYieldDistributed || "0");
        if (v.status !== "Closed" && v.status !== "Matured") activeVaults++;

        for (const t of v.tranches.items) {
          const invested = BigInt(t.totalInvested || "0");
          const apr = BigInt(t.targetApr || "0");
          if (t.trancheId === 0) seniorTVL += invested;
          else if (t.trancheId === 1) mezzTVL += invested;
          else equityTVL += invested;
          totalWeightedApr += invested * apr;
          totalInvested += invested;
        }
      }

      let totalProtectionBilateral = 0n;
      let totalCollateralPosted = 0n;
      let totalPremiumsPaid = 0n;
      let activeCDS = 0;

      for (const c of cds) {
        totalProtectionBilateral += BigInt(c.protectionAmount || "0");
        totalCollateralPosted += BigInt(c.collateralPosted || "0");
        totalPremiumsPaid += BigInt(c.totalPremiumPaid || "0");
        if (c.status === "Active") activeCDS++;
      }

      const weightedAvgApr =
        totalInvested > 0n
          ? Number(totalWeightedApr / totalInvested) / 100
          : 0;

      return {
        totalVaultTVL,
        totalYieldGenerated,
        totalYieldDistributed,
        vaultCount: vaults.length,
        activeVaults,
        cdsCount: cds.length,
        activeCDS,
        totalProtectionBilateral,
        totalCollateralPosted,
        totalPremiumsPaid,
        seniorTVL,
        mezzTVL,
        equityTVL,
        weightedAvgApr,
      };
    },
    staleTime: Infinity,
  });
}

/** Aggregate CDS pool metrics from on-chain reads */
export function usePoolMetricsAggregate() {
  const { data: poolCount } = usePoolCount();
  const count = poolCount ? Number(poolCount) : 0;

  // We return the count so the page can render individual pool readers
  return { poolCount: count };
}

/** Read single pool metrics for the analytics view */
export function usePoolAnalytics(poolAddress: Address | undefined) {
  const enabled = !!poolAddress && poolAddress !== "0x0000000000000000000000000000000000000000";
  const { data: status } = usePoolStatus(poolAddress as Address);
  const { data: totalAssets } = useTotalAssets(poolAddress as Address);
  const { data: utilization } = useUtilizationRate(poolAddress as Address);
  const { data: spread } = useCurrentSpread(poolAddress as Address);
  const { data: totalProtection } = useTotalProtectionSold(poolAddress as Address);

  return {
    enabled,
    status: status !== undefined ? Number(status) : undefined,
    totalAssets: totalAssets ?? 0n,
    utilization: utilization ?? 0n,
    spread: spread ?? 0n,
    totalProtection: totalProtection ?? 0n,
  };
}
