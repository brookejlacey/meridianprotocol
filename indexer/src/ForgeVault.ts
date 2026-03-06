import { ponder } from "ponder:registry";
import {
  vault,
  tranche,
  investment,
  investEvent,
  withdrawEvent,
  yieldClaimEvent,
  yieldDistribution,
} from "ponder:schema";

ponder.on("ForgeVault:Invested", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();
  const trancheIdx = Number(event.args.trancheId);
  const trancheEntityId = `${vaultAddress}-${trancheIdx}`;
  const investmentId = `${vaultAddress}-${trancheIdx}-${event.args.investor.toLowerCase()}`;

  // Upsert investment
  await context.db
    .insert(investment)
    .values({
      id: investmentId,
      vaultId: vaultAddress,
      trancheId: trancheEntityId,
      investor: event.args.investor,
      totalInvested: event.args.amount,
      totalWithdrawn: 0n,
      totalYieldClaimed: 0n,
    })
    .onConflictDoUpdate((row) => ({
      totalInvested: row.totalInvested + event.args.amount,
    }));

  // Update tranche totalInvested
  await context.db.update(tranche, { id: trancheEntityId }).set((row) => ({
    totalInvested: row.totalInvested + event.args.amount,
  }));

  // Update vault totalDeposited
  await context.db.update(vault, { id: vaultAddress }).set((row) => ({
    totalDeposited: row.totalDeposited + event.args.amount,
  }));

  // Create event log
  await context.db.insert(investEvent).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    vaultId: vaultAddress,
    investor: event.args.investor,
    trancheId: trancheIdx,
    amount: event.args.amount,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });
});

ponder.on("ForgeVault:Withdrawn", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();
  const trancheIdx = Number(event.args.trancheId);
  const investmentId = `${vaultAddress}-${trancheIdx}-${event.args.investor.toLowerCase()}`;

  // Update investment
  await context.db.update(investment, { id: investmentId }).set((row) => ({
    totalWithdrawn: row.totalWithdrawn + event.args.amount,
  }));

  // Update tranche
  await context.db
    .update(tranche, { id: `${vaultAddress}-${trancheIdx}` })
    .set((row) => ({
      totalInvested: row.totalInvested - event.args.amount,
    }));

  // Update vault
  await context.db.update(vault, { id: vaultAddress }).set((row) => ({
    totalDeposited: row.totalDeposited - event.args.amount,
  }));

  // Create event log
  await context.db.insert(withdrawEvent).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    vaultId: vaultAddress,
    investor: event.args.investor,
    trancheId: trancheIdx,
    amount: event.args.amount,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });
});

ponder.on("ForgeVault:YieldClaimed", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();
  const trancheIdx = Number(event.args.trancheId);
  const investmentId = `${vaultAddress}-${trancheIdx}-${event.args.investor.toLowerCase()}`;

  // Update investment
  await context.db.update(investment, { id: investmentId }).set((row) => ({
    totalYieldClaimed: row.totalYieldClaimed + event.args.amount,
  }));

  // Create event log
  await context.db.insert(yieldClaimEvent).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    vaultId: vaultAddress,
    investor: event.args.investor,
    trancheId: trancheIdx,
    amount: event.args.amount,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });
});

ponder.on("ForgeVault:YieldReceived", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();

  await context.db.update(vault, { id: vaultAddress }).set((row) => ({
    totalYieldReceived: row.totalYieldReceived + event.args.amount,
  }));
});

ponder.on("ForgeVault:WaterfallDistributed", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();

  // Update vault
  await context.db.update(vault, { id: vaultAddress }).set((row) => ({
    totalYieldDistributed: row.totalYieldDistributed + event.args.totalYield,
    lastDistribution: event.block.timestamp,
  }));

  // Create distribution event
  await context.db.insert(yieldDistribution).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    vaultId: vaultAddress,
    totalYield: event.args.totalYield,
    seniorAmount: event.args.trancheAmounts[0],
    mezzAmount: event.args.trancheAmounts[1],
    equityAmount: event.args.trancheAmounts[2],
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });
});

ponder.on("ForgeVault:PoolStatusChanged", async ({ event, context }) => {
  const vaultAddress = event.log.address.toLowerCase();
  const statusMap = ["Active", "Impaired", "Defaulted", "Matured"] as const;
  const newStatus = statusMap[Number(event.args.newStatus)] ?? "Active";

  await context.db.update(vault, { id: vaultAddress }).set({
    status: newStatus,
  });
});
