"use client";

import { useQuery } from "@tanstack/react-query";
import { graphqlQuery } from "@/lib/graphql/client";
import { USER_INVESTMENTS_QUERY } from "@/lib/graphql/queries";

export interface IndexedInvestment {
  id: string;
  vaultId: string;
  trancheId: string;
  investor: string;
  totalInvested: string;
  totalWithdrawn: string;
  totalYieldClaimed: string;
}

interface InvestmentsResponse {
  investments: { items: IndexedInvestment[] };
}

export function useUserInvestments(userAddress: string | undefined) {
  return useQuery({
    queryKey: ["indexer", "investments", userAddress],
    queryFn: () =>
      graphqlQuery<InvestmentsResponse>(USER_INVESTMENTS_QUERY, {
        investor: userAddress?.toLowerCase(),
      }),
    enabled: !!userAddress,
    select: (data) => data.investments.items,
    refetchInterval: 10_000,
  });
}
