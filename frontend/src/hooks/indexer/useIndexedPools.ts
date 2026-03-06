"use client";

import { useQuery } from "@tanstack/react-query";

export interface IndexedPool {
  id: string;
  poolId: string;
  referenceAsset: string;
  totalLiquidity: string;
  protectionSold: string;
  utilizationRate: string;
  currentSpread: string;
  baseSpread: string;
  slope: string;
  maturity: string;
  status: string;
  collateralToken: string;
}

// Hardcoded pool data for demo — showcases CDS AMM pool layer
const DEPLOYED_POOLS: IndexedPool[] = [
  {
    id: "0xAA1122334455667788990011223344556677AABB",
    poolId: "0",
    referenceAsset: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327",
    totalLiquidity: "2000000000000000000000000",
    protectionSold: "800000000000000000000000",
    utilizationRate: "400000000000000000",
    currentSpread: "25000000000000000",
    baseSpread: "20000000000000000",
    slope: "50000000000000000",
    maturity: "1771000000",
    status: "Active",
    collateralToken: "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f",
  },
  {
    id: "0xBB2233445566778899001122334455667788BBCC",
    poolId: "1",
    referenceAsset: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334",
    totalLiquidity: "5000000000000000000000000",
    protectionSold: "3500000000000000000000000",
    utilizationRate: "700000000000000000",
    currentSpread: "45000000000000000",
    baseSpread: "20000000000000000",
    slope: "60000000000000000",
    maturity: "1774000000",
    status: "Active",
    collateralToken: "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f",
  },
  {
    id: "0xCC3344556677889900112233445566778899CCDD",
    poolId: "2",
    referenceAsset: "0xE5F607182930A4B5C6D7E8F900112233445566BB",
    totalLiquidity: "1500000000000000000000000",
    protectionSold: "1350000000000000000000000",
    utilizationRate: "900000000000000000",
    currentSpread: "80000000000000000",
    baseSpread: "25000000000000000",
    slope: "70000000000000000",
    maturity: "1765000000",
    status: "Settled",
    collateralToken: "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f",
  },
];

export function useIndexedPools() {
  return useQuery({
    queryKey: ["static", "pools"],
    queryFn: () => DEPLOYED_POOLS,
    staleTime: Infinity,
  });
}

export function useIndexedPoolDetail(poolId: string | undefined) {
  return useQuery({
    queryKey: ["static", "pool", poolId],
    queryFn: () => DEPLOYED_POOLS.find((p) => p.poolId === poolId) ?? null,
    enabled: !!poolId,
    staleTime: Infinity,
  });
}
