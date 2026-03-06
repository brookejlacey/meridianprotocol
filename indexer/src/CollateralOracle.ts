import { ponder } from "ponder:registry";
import { asset } from "ponder:schema";

ponder.on("CollateralOracle:AssetRegistered", async ({ event, context }) => {
  const assetAddr = event.args.asset.toLowerCase();

  await context.db.insert(asset).values({
    id: assetAddr,
    price: event.args.price,
    riskWeight: event.args.riskWeight,
    lastUpdated: event.block.timestamp,
  });
});

ponder.on("CollateralOracle:PriceUpdated", async ({ event, context }) => {
  const assetAddr = event.args.asset.toLowerCase();

  await context.db.update(asset, { id: assetAddr }).set({
    price: event.args.price,
    lastUpdated: event.block.timestamp,
  });
});
