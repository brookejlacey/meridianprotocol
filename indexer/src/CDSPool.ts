import { ponder } from "ponder:registry";
import { cdsPool, poolDeposit, protectionPosition } from "ponder:schema";

const MOCK_USDC = "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f".toLowerCase();
const CREDIT_ORACLE = "0x8E28b5C0fc6053F70dB768Fa9F35a3a8a3f35175".toLowerCase();

// Helper: default pool values used as fallback in upserts.
// Pool should already exist from CDSPoolFactory:PoolCreated, so these
// are only used if an event arrives before the creation event is indexed.
function defaultPoolValues(poolAddress: string, timestamp: bigint, blockNumber: bigint) {
  return {
    id: poolAddress,
    poolId: 0n,
    referenceAsset: poolAddress,
    collateralToken: MOCK_USDC,
    oracle: CREDIT_ORACLE,
    maturity: 0n,
    baseSpreadWad: 0n,
    slopeWad: 0n,
    creator: poolAddress,
    status: "Active" as const,
    totalDeposits: 0n,
    totalPremiumsEarned: 0n,
    totalProtectionSold: 0n,
    createdAt: timestamp,
    blockNumber,
  };
}

ponder.on("CDSPool:LiquidityDeposited", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  // Record deposit event
  await context.db.insert(poolDeposit).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    poolId: poolAddress,
    lp: event.args.lp,
    amount: event.args.amount,
    shares: event.args.shares,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });

  // Update pool totals
  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      totalDeposits: event.args.amount,
    })
    .onConflictDoUpdate((row) => ({
      totalDeposits: row.totalDeposits + event.args.amount,
    }));
});

ponder.on("CDSPool:LiquidityWithdrawn", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db
    .insert(cdsPool)
    .values(defaultPoolValues(poolAddress, event.block.timestamp, event.block.number))
    .onConflictDoUpdate((row) => ({
      totalDeposits:
        row.totalDeposits > event.args.amount
          ? row.totalDeposits - event.args.amount
          : 0n,
    }));
});

ponder.on("CDSPool:ProtectionBought", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db.insert(protectionPosition).values({
    id: `${poolAddress}-${event.args.positionId}`,
    poolId: poolAddress,
    positionId: event.args.positionId,
    buyer: event.args.buyer,
    notional: event.args.notional,
    premiumPaid: event.args.premium,
    spreadWad: event.args.spreadWad,
    active: true,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });

  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      totalProtectionSold: event.args.notional,
    })
    .onConflictDoUpdate((row) => ({
      totalProtectionSold: row.totalProtectionSold + event.args.notional,
    }));
});

ponder.on("CDSPool:ProtectionClosed", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();
  const posKey = `${poolAddress}-${event.args.positionId}`;

  await context.db
    .insert(protectionPosition)
    .values({
      id: posKey,
      poolId: poolAddress,
      positionId: event.args.positionId,
      buyer: event.args.buyer,
      notional: 0n,
      premiumPaid: 0n,
      spreadWad: 0n,
      active: false,
      timestamp: event.block.timestamp,
      blockNumber: event.block.number,
      txHash: event.transaction.hash,
    })
    .onConflictDoUpdate(() => ({
      active: false,
    }));
});

ponder.on("CDSPool:PremiumsAccrued", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      totalPremiumsEarned: event.args.totalAccrued,
    })
    .onConflictDoUpdate((row) => ({
      totalPremiumsEarned: row.totalPremiumsEarned + event.args.totalAccrued,
    }));
});

ponder.on("CDSPool:CreditEventTriggered", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      status: "Triggered",
    })
    .onConflictDoUpdate(() => ({
      status: "Triggered" as const,
    }));
});

ponder.on("CDSPool:PoolSettled", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      status: "Settled",
    })
    .onConflictDoUpdate(() => ({
      status: "Settled" as const,
      totalProtectionSold: 0n,
    }));
});

ponder.on("CDSPool:PoolExpired", async ({ event, context }) => {
  const poolAddress = event.log.address.toLowerCase();

  await context.db
    .insert(cdsPool)
    .values({
      ...defaultPoolValues(poolAddress, event.block.timestamp, event.block.number),
      status: "Expired",
    })
    .onConflictDoUpdate(() => ({
      status: "Expired" as const,
      totalProtectionSold: 0n,
    }));
});
