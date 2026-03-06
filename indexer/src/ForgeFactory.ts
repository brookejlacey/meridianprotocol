import { ponder } from "ponder:registry";
import { vault, tranche } from "ponder:schema";
import { ForgeVaultAbi } from "../abis/ForgeVault";

ponder.on("ForgeFactory:VaultCreated", async ({ event, context }) => {
  const vaultAddress = event.args.vault.toLowerCase();

  // Create vault entity
  await context.db.insert(vault).values({
    id: vaultAddress,
    vaultId: event.args.vaultId,
    originator: event.args.originator,
    underlyingAsset: event.args.underlyingAsset,
    status: "Active",
    totalDeposited: 0n,
    totalYieldReceived: 0n,
    totalYieldDistributed: 0n,
    lastDistribution: event.block.timestamp,
    createdAt: event.block.timestamp,
    blockNumber: event.block.number,
  });

  // Read tranche params from on-chain and create tranche entities
  for (let i = 0; i < 3; i++) {
    const params = await context.client.readContract({
      abi: ForgeVaultAbi,
      address: event.args.vault,
      functionName: "trancheParamsArray",
      args: [BigInt(i)],
    });

    const tokenAddress = await context.client.readContract({
      abi: ForgeVaultAbi,
      address: event.args.vault,
      functionName: "trancheTokens",
      args: [BigInt(i)],
    });

    await context.db.insert(tranche).values({
      id: `${vaultAddress}-${i}`,
      vaultId: vaultAddress,
      trancheId: i,
      tokenAddress: tokenAddress,
      targetApr: params[0], // targetApr
      allocationPct: params[1], // allocationPct
      totalInvested: 0n,
    });
  }
});
