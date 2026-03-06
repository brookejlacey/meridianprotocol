"use client";

import { useQuery } from "@tanstack/react-query";

export interface IndexedCDS {
  id: string;
  cdsId: string;
  referenceVaultId: string;
  creator: string;
  buyer: string | null;
  seller: string | null;
  protectionAmount: string;
  premiumRate: string;
  maturity: string;
  status: string;
  collateralPosted: string;
  totalPremiumPaid: string;
  createdAt: string;
}

// Hardcoded CDS data from Fuji deployment (block 51648911)
// Includes additional demo CDS contracts to showcase Shield layer
const DEPLOYED_CDS: IndexedCDS[] = [
  {
    id: "0x35d6fE4079400d4f0D3155ea7220D3279D3C7914",
    cdsId: "0",
    referenceVaultId: "0x658b99C350CfEDd8Acf33dB6782Ca99e44e98327",
    creator: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    buyer: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    seller: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    protectionAmount: "500000000000000000000000",
    premiumRate: "300",
    maturity: "1771000000",
    status: "Active",
    collateralPosted: "500000000000000000000000",
    totalPremiumPaid: "15000000000000000000000",
    createdAt: "1739000000",
  },
  {
    id: "0x4A5B6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B",
    cdsId: "1",
    referenceVaultId: "0xA1B2C3D4E5F60718293A4B5C6D7E8F9001122334",
    creator: "0x7a3F8b2E1c9D0456789aBcDeF0123456789ABCDE",
    buyer: "0x7a3F8b2E1c9D0456789aBcDeF0123456789ABCDE",
    seller: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    protectionAmount: "1000000000000000000000000",
    premiumRate: "250",
    maturity: "1774000000",
    status: "Active",
    collateralPosted: "1000000000000000000000000",
    totalPremiumPaid: "25000000000000000000000",
    createdAt: "1738600000",
  },
  {
    id: "0x5B6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B4C",
    cdsId: "2",
    referenceVaultId: "0xD4E5F6071829A3B4C5D6E7F8900112233445566A",
    creator: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    buyer: "0x3B4c5D6e7F8901a2B3C4D5E6F7890123456789AB",
    seller: "0xD243eB302C08511743B0050cE77c02C80FeccCc8",
    protectionAmount: "250000000000000000000000",
    premiumRate: "350",
    maturity: "1768000000",
    status: "Active",
    collateralPosted: "250000000000000000000000",
    totalPremiumPaid: "8750000000000000000000",
    createdAt: "1739300000",
  },
  {
    id: "0x6C7D8E9F0A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D",
    cdsId: "3",
    referenceVaultId: "0xE5F607182930A4B5C6D7E8F900112233445566BB",
    creator: "0x3B4c5D6e7F8901a2B3C4D5E6F7890123456789AB",
    buyer: "0x3B4c5D6e7F8901a2B3C4D5E6F7890123456789AB",
    seller: "0x7a3F8b2E1c9D0456789aBcDeF0123456789ABCDE",
    protectionAmount: "750000000000000000000000",
    premiumRate: "200",
    maturity: "1765000000",
    status: "Settled",
    collateralPosted: "750000000000000000000000",
    totalPremiumPaid: "45000000000000000000000",
    createdAt: "1736100000",
  },
];

export function useIndexedCDS() {
  return useQuery({
    queryKey: ["static", "cds"],
    queryFn: () => DEPLOYED_CDS,
    staleTime: Infinity,
  });
}

export function useIndexedCDSDetail(cdsId: string | undefined) {
  return useQuery({
    queryKey: ["static", "cds", cdsId],
    queryFn: () => DEPLOYED_CDS.find((c) => c.cdsId === cdsId) ?? null,
    enabled: !!cdsId,
    staleTime: Infinity,
  });
}
