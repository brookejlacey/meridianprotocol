"use client";

import { useIndexedVaults } from "@/hooks/indexer/useIndexedVaults";
import { VaultCard } from "@/components/forge/VaultCard";

export default function ForgePage() {
  const { data: vaults, isLoading } = useIndexedVaults();

  if (isLoading) {
    return <div className="text-zinc-500">Loading vaults...</div>;
  }

  if (!vaults || vaults.length === 0) {
    return (
      <div className="text-center py-12">
        <h2 className="text-lg font-medium mb-2">No Vaults Yet</h2>
        <p className="text-zinc-500 text-sm">
          No structured credit vaults have been created. Deploy contracts to Fuji and create a vault to get started.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-medium">Structured Credit Vaults</h2>
        <span className="text-sm text-zinc-500">{vaults.length} vault{vaults.length !== 1 ? "s" : ""}</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {vaults.map((vault) => (
          <VaultCard key={vault.id} vault={vault} />
        ))}
      </div>
    </div>
  );
}
