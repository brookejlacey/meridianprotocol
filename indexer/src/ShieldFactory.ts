import { ponder } from "ponder:registry";
import { cdsContract } from "ponder:schema";

const MOCK_USDC = "0x09eC69338406B293b3f6Aa775A65C1FA7C0bC42f".toLowerCase();

ponder.on("ShieldFactory:CDSCreated", async ({ event, context }) => {
  const cdsAddress = event.args.cds.toLowerCase();
  const referenceVaultId = event.args.referenceAsset.toLowerCase();

  await context.db.insert(cdsContract).values({
    id: cdsAddress,
    cdsId: event.args.cdsId,
    referenceVaultId,
    creator: event.args.creator,
    buyer: null,
    seller: null,
    protectionAmount: event.args.protectionAmount,
    premiumRate: event.args.premiumRate,
    maturity: event.args.maturity,
    collateralToken: MOCK_USDC,
    status: "Open",
    collateralPosted: 0n,
    totalPremiumPaid: 0n,
    createdAt: event.block.timestamp,
    blockNumber: event.block.number,
  });
});
