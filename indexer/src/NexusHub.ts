import { ponder } from "ponder:registry";
import {
  marginAccount,
  collateralPosition,
  liquidation,
} from "ponder:schema";

ponder.on("NexusHub:MarginAccountOpened", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();

  await context.db.insert(marginAccount).values({
    id: userId,
    user: event.args.user,
    openedAt: event.block.timestamp,
    blockNumber: event.block.number,
  });
});

ponder.on("NexusHub:CollateralDeposited", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const assetAddr = event.args.asset.toLowerCase();
  const positionId = `${userId}-${assetAddr}`;

  await context.db
    .insert(collateralPosition)
    .values({
      id: positionId,
      accountId: userId,
      asset: event.args.asset,
      currentBalance: event.args.amount,
    })
    .onConflictDoUpdate((row) => ({
      currentBalance: row.currentBalance + event.args.amount,
    }));
});

ponder.on("NexusHub:CollateralWithdrawn", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const assetAddr = event.args.asset.toLowerCase();
  const positionId = `${userId}-${assetAddr}`;

  await context.db
    .update(collateralPosition, { id: positionId })
    .set((row) => ({
      currentBalance: row.currentBalance - event.args.amount,
    }));
});

ponder.on("NexusHub:LiquidationExecuted", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();

  await context.db.insert(liquidation).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    accountId: userId,
    liquidator: event.args.liquidator,
    collateralSeized: event.args.collateralSeized,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });
});
