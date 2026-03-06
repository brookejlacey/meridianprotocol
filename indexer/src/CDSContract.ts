import { ponder } from "ponder:registry";
import { cdsContract, premiumPayment } from "ponder:schema";

ponder.on("CDSContract:ProtectionBought", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  await context.db.update(cdsContract, { id: cdsAddress }).set({
    buyer: event.args.buyer,
    status: "Active",
  });
});

ponder.on("CDSContract:ProtectionSold", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  await context.db.update(cdsContract, { id: cdsAddress }).set({
    seller: event.args.seller,
    collateralPosted: event.args.collateralPosted,
  });
});

ponder.on("CDSContract:PremiumPaid", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  // Create premium payment event
  await context.db.insert(premiumPayment).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    cdsId: cdsAddress,
    buyer: event.args.buyer,
    amount: event.args.amount,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
    txHash: event.transaction.hash,
  });

  // Update total premium paid
  await context.db.update(cdsContract, { id: cdsAddress }).set((row) => ({
    totalPremiumPaid: row.totalPremiumPaid + event.args.amount,
  }));
});

ponder.on("CDSContract:CreditEventTriggered", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  await context.db.update(cdsContract, { id: cdsAddress }).set({
    status: "Triggered",
  });
});

ponder.on("CDSContract:Settled", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  await context.db.update(cdsContract, { id: cdsAddress }).set({
    status: "Settled",
  });
});

ponder.on("CDSContract:Expired", async ({ event, context }) => {
  const cdsAddress = event.log.address.toLowerCase();

  await context.db.update(cdsContract, { id: cdsAddress }).set({
    status: "Expired",
  });
});
