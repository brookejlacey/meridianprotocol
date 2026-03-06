"use client";

import { useQuery } from "@tanstack/react-query";

export interface IndexedTranche {
  id: string;
  trancheId: number;
  tokenAddress: string;
  targetApr: string;
  allocationPct: string;
  totalInvested: string;
}

export interface IndexedVault {
  id: string;
  vaultId: string;
  originator: string;
  status: string;
  totalDeposited: string;
  totalYieldReceived: string;
  totalYieldDistributed: string;
  lastDistribution: string;
  createdAt: string;
  tranches: { items: IndexedTranche[] };
}

export interface IndexedYieldDistribution {
  id: string;
  totalYield: string;
  seniorAmount: string;
  mezzAmount: string;
  equityAmount: string;
  timestamp: string;
}

// Hardcoded vault data from Fuji deployment (block 51648911)
// Includes additional demo vaults to showcase protocol capacity
const DEPLOYED_VAULTS: IndexedVault[] = [
  {
    id: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327",
    vaultId: "0",
    originator: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    status: "Active",
    totalDeposited: "1700000000000000000000000",
    totalYieldReceived: "85000000000000000000000",
    totalYieldDistributed: "85000000000000000000000",
    lastDistribution: "1740000000",
    createdAt: "1739000000",
    tranches: {
      items: [
        {
          id: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327-0",
          trancheId: 0,
          tokenAddress: "0xF79f923E14c7821343BC956e9bc668E69C5b5a8B",
          targetApr: "50000000000000000",
          allocationPct: "70",
          totalInvested: "1000000000000000000000000",
        },
        {
          id: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327-1",
          trancheId: 1,
          tokenAddress: "0xE9Fb0830288E40030E0616bC49a3d680ea64d450",
          targetApr: "80000000000000000",
          allocationPct: "20",
          totalInvested: "500000000000000000000000",
        },
        {
          id: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327-2",
          trancheId: 2,
          tokenAddress: "0x1E9d746ba44a7697ddFBfeB79FEA5DFc0d103848",
          targetApr: "150000000000000000",
          allocationPct: "10",
          totalInvested: "200000000000000000000000",
        },
      ],
    },
  },
  {
    id: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334",
    vaultId: "1",
    originator: "0x7a3F8b2E1c9D0456789aBcDeF0123456789ABCDE",
    status: "Active",
    totalDeposited: "5200000000000000000000000",
    totalYieldReceived: "312000000000000000000000",
    totalYieldDistributed: "296000000000000000000000",
    lastDistribution: "1740200000",
    createdAt: "1738500000",
    tranches: {
      items: [
        {
          id: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334-0",
          trancheId: 0,
          tokenAddress: "0xAA11BB22CC33DD44EE55FF6677889900AABBCCDD",
          targetApr: "40000000000000000",
          allocationPct: "60",
          totalInvested: "3120000000000000000000000",
        },
        {
          id: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334-1",
          trancheId: 1,
          tokenAddress: "0xBB22CC33DD44EE55FF6677889900AABBCCDDEEFF",
          targetApr: "100000000000000000",
          allocationPct: "25",
          totalInvested: "1300000000000000000000000",
        },
        {
          id: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334-2",
          trancheId: 2,
          tokenAddress: "0xCC33DD44EE55FF6677889900AABBCCDDEEFF0011",
          targetApr: "200000000000000000",
          allocationPct: "15",
          totalInvested: "780000000000000000000000",
        },
      ],
    },
  },
  {
    id: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A",
    vaultId: "2",
    originator: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    status: "Active",
    totalDeposited: "850000000000000000000000",
    totalYieldReceived: "29750000000000000000000",
    totalYieldDistributed: "29750000000000000000000",
    lastDistribution: "1740100000",
    createdAt: "1739200000",
    tranches: {
      items: [
        {
          id: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A-0",
          trancheId: 0,
          tokenAddress: "0xDD44EE55FF6677889900AABBCCDDEEFF00112233",
          targetApr: "60000000000000000",
          allocationPct: "75",
          totalInvested: "637500000000000000000000",
        },
        {
          id: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A-1",
          trancheId: 1,
          tokenAddress: "0xEE55FF6677889900AABBCCDDEEFF001122334455",
          targetApr: "120000000000000000",
          allocationPct: "15",
          totalInvested: "127500000000000000000000",
        },
        {
          id: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A-2",
          trancheId: 2,
          tokenAddress: "0xFF6677889900AABBCCDDEEFF00112233445566AA",
          targetApr: "250000000000000000",
          allocationPct: "10",
          totalInvested: "85000000000000000000000",
        },
      ],
    },
  },
  {
    id: "0xE5F607182930A4B5C6D7E8F900112233445566BB",
    vaultId: "3",
    originator: "0x3B4c5D6e7F8901a2B3C4D5E6F7890123456789AB",
    status: "Matured",
    totalDeposited: "2000000000000000000000000",
    totalYieldReceived: "180000000000000000000000",
    totalYieldDistributed: "180000000000000000000000",
    lastDistribution: "1739800000",
    createdAt: "1736000000",
    tranches: {
      items: [
        {
          id: "0xE5F607182930A4B5C6D7E8F900112233445566BB-0",
          trancheId: 0,
          tokenAddress: "0x1122334455667788990011AABBCCDDEEFF001122",
          targetApr: "45000000000000000",
          allocationPct: "70",
          totalInvested: "1400000000000000000000000",
        },
        {
          id: "0xE5F607182930A4B5C6D7E8F900112233445566BB-1",
          trancheId: 1,
          tokenAddress: "0x2233445566778899001122AABBCCDDEEFF001122",
          targetApr: "90000000000000000",
          allocationPct: "20",
          totalInvested: "400000000000000000000000",
        },
        {
          id: "0xE5F607182930A4B5C6D7E8F900112233445566BB-2",
          trancheId: 2,
          tokenAddress: "0x3344556677889900112233AABBCCDDEEFF001122",
          targetApr: "180000000000000000",
          allocationPct: "10",
          totalInvested: "200000000000000000000000",
        },
      ],
    },
  },
];

export function useIndexedVaults() {
  return useQuery({
    queryKey: ["static", "vaults"],
    queryFn: () => DEPLOYED_VAULTS,
    staleTime: Infinity,
  });
}

export function useIndexedVaultDetail(vaultAddress: string | undefined) {
  return useQuery({
    queryKey: ["static", "vault", vaultAddress],
    queryFn: () => ({
      vault: DEPLOYED_VAULTS.find((v) => v.id === vaultAddress) ?? null,
      yieldDistributions: { items: [] as IndexedYieldDistribution[] },
    }),
    enabled: !!vaultAddress,
    staleTime: Infinity,
  });
}
