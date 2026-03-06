import { ponder } from "ponder:registry";
import { cdsPool } from "ponder:schema";

const MOCK_USDC = "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f".toLowerCase();
const CREDIT_ORACLE = "0x8E28b5C0fc6053F70dB768Fa9F35a3a8a3f35175".toLowerCase();

ponder.on("CDSPoolFactory:PoolCreated", async ({ event, context }) => {
  const poolAddress = event.args.pool.toLowerCase();

  await context.db.insert(cdsPool).values({
    id: poolAddress,
    poolId: event.args.poolId,
    referenceAsset: event.args.referenceAsset,
    collateralToken: MOCK_USDC,
    oracle: CREDIT_ORACLE,
    maturity: event.args.maturity,
    baseSpreadWad: event.args.baseSpreadWad,
    slopeWad: event.args.slopeWad,
    creator: event.args.creator,
    status: "Active",
    totalDeposits: 0n,
    totalPremiumsEarned: 0n,
    totalProtectionSold: 0n,
    createdAt: event.block.timestamp,
    blockNumber: event.block.number,
  });
});
