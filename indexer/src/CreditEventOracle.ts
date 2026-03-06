import { ponder } from "ponder:registry";
import { creditEvent } from "ponder:schema";

ponder.on(
  "CreditEventOracle:CreditEventReported",
  async ({ event, context }) => {
    const eventTypeMap = ["None", "Impairment", "Default"] as const;
    const eventType =
      eventTypeMap[Number(event.args.eventType)] ?? "None";

    await context.db.insert(creditEvent).values({
      id: `${event.transaction.hash}-${event.log.logIndex}`,
      vaultId: event.args.vault.toLowerCase(),
      eventType,
      lossAmount: event.args.lossAmount,
      timestamp: event.block.timestamp,
      blockNumber: event.block.number,
      txHash: event.transaction.hash,
    });
  }
);
