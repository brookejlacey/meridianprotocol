import { index, onchainEnum, onchainTable, relations } from "ponder";

// --- Enums ---

export const poolStatus = onchainEnum("pool_status", [
  "Active",
  "Impaired",
  "Defaulted",
  "Matured",
]);

export const cdsStatus = onchainEnum("cds_status", [
  "Open",
  "Active",
  "Triggered",
  "Settled",
  "Expired",
]);

export const creditEventType = onchainEnum("credit_event_type", [
  "None",
  "Impairment",
  "Default",
]);

// --- Forge Module ---

export const vault = onchainTable(
  "vault",
  (t) => ({
    id: t.text().primaryKey(), // vault address
    vaultId: t.bigint().notNull(),
    originator: t.hex().notNull(),
    underlyingAsset: t.hex().notNull(),
    status: poolStatus().notNull(),
    totalDeposited: t.bigint().notNull(),
    totalYieldReceived: t.bigint().notNull(),
    totalYieldDistributed: t.bigint().notNull(),
    lastDistribution: t.bigint().notNull(),
    createdAt: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
  }),
  (table) => ({
    originatorIdx: index().on(table.originator),
    statusIdx: index().on(table.status),
  })
);

export const vaultRelations = relations(vault, ({ many }) => ({
  tranches: many(tranche),
  investments: many(investment),
  yieldDistributions: many(yieldDistribution),
  cdsContracts: many(cdsContract),
  creditEvents: many(creditEvent),
}));

export const tranche = onchainTable("tranche", (t) => ({
  id: t.text().primaryKey(), // vaultAddress-trancheId
  vaultId: t.text().notNull(),
  trancheId: t.integer().notNull(),
  tokenAddress: t.hex().notNull(),
  targetApr: t.bigint().notNull(),
  allocationPct: t.bigint().notNull(),
  totalInvested: t.bigint().notNull(),
}));

export const trancheRelations = relations(tranche, ({ one, many }) => ({
  vault: one(vault, { fields: [tranche.vaultId], references: [vault.id] }),
  investments: many(investment),
}));

export const investment = onchainTable(
  "investment",
  (t) => ({
    id: t.text().primaryKey(), // vaultAddress-trancheId-investor
    vaultId: t.text().notNull(),
    trancheId: t.text().notNull(),
    investor: t.hex().notNull(),
    totalInvested: t.bigint().notNull(),
    totalWithdrawn: t.bigint().notNull(),
    totalYieldClaimed: t.bigint().notNull(),
  }),
  (table) => ({
    investorIdx: index().on(table.investor),
    vaultIdx: index().on(table.vaultId),
  })
);

export const investmentRelations = relations(investment, ({ one }) => ({
  vault: one(vault, { fields: [investment.vaultId], references: [vault.id] }),
  tranche: one(tranche, {
    fields: [investment.trancheId],
    references: [tranche.id],
  }),
}));

export const investEvent = onchainTable(
  "invest_event",
  (t) => ({
    id: t.text().primaryKey(), // txHash-logIndex
    vaultId: t.text().notNull(),
    investor: t.hex().notNull(),
    trancheId: t.integer().notNull(),
    amount: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (table) => ({
    vaultIdx: index().on(table.vaultId),
    investorIdx: index().on(table.investor),
  })
);

export const withdrawEvent = onchainTable("withdraw_event", (t) => ({
  id: t.text().primaryKey(),
  vaultId: t.text().notNull(),
  investor: t.hex().notNull(),
  trancheId: t.integer().notNull(),
  amount: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const yieldClaimEvent = onchainTable("yield_claim_event", (t) => ({
  id: t.text().primaryKey(),
  vaultId: t.text().notNull(),
  investor: t.hex().notNull(),
  trancheId: t.integer().notNull(),
  amount: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const yieldDistribution = onchainTable(
  "yield_distribution",
  (t) => ({
    id: t.text().primaryKey(), // txHash-logIndex
    vaultId: t.text().notNull(),
    totalYield: t.bigint().notNull(),
    seniorAmount: t.bigint().notNull(),
    mezzAmount: t.bigint().notNull(),
    equityAmount: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (table) => ({
    vaultIdx: index().on(table.vaultId),
  })
);

export const yieldDistributionRelations = relations(
  yieldDistribution,
  ({ one }) => ({
    vault: one(vault, {
      fields: [yieldDistribution.vaultId],
      references: [vault.id],
    }),
  })
);

// --- Shield Module ---

export const cdsContract = onchainTable(
  "cds_contract",
  (t) => ({
    id: t.text().primaryKey(), // cds address
    cdsId: t.bigint().notNull(),
    referenceVaultId: t.text().notNull(),
    creator: t.hex().notNull(),
    buyer: t.hex(),
    seller: t.hex(),
    protectionAmount: t.bigint().notNull(),
    premiumRate: t.bigint().notNull(),
    maturity: t.bigint().notNull(),
    collateralToken: t.hex().notNull(),
    status: cdsStatus().notNull(),
    collateralPosted: t.bigint().notNull(),
    totalPremiumPaid: t.bigint().notNull(),
    createdAt: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
  }),
  (table) => ({
    referenceVaultIdx: index().on(table.referenceVaultId),
    statusIdx: index().on(table.status),
    buyerIdx: index().on(table.buyer),
    sellerIdx: index().on(table.seller),
  })
);

export const cdsContractRelations = relations(cdsContract, ({ one, many }) => ({
  referenceVault: one(vault, {
    fields: [cdsContract.referenceVaultId],
    references: [vault.id],
  }),
  premiumPayments: many(premiumPayment),
}));

export const premiumPayment = onchainTable("premium_payment", (t) => ({
  id: t.text().primaryKey(),
  cdsId: t.text().notNull(),
  buyer: t.hex().notNull(),
  amount: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const premiumPaymentRelations = relations(premiumPayment, ({ one }) => ({
  cds: one(cdsContract, {
    fields: [premiumPayment.cdsId],
    references: [cdsContract.id],
  }),
}));

export const creditEvent = onchainTable(
  "credit_event",
  (t) => ({
    id: t.text().primaryKey(),
    vaultId: t.text().notNull(),
    eventType: creditEventType().notNull(),
    lossAmount: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (table) => ({
    vaultIdx: index().on(table.vaultId),
  })
);

export const creditEventRelations = relations(creditEvent, ({ one }) => ({
  vault: one(vault, {
    fields: [creditEvent.vaultId],
    references: [vault.id],
  }),
}));

// --- CDS Pool AMM Module ---

export const cdsPoolStatus = onchainEnum("cds_pool_status", [
  "Active",
  "Triggered",
  "Settled",
  "Expired",
]);

export const cdsPool = onchainTable(
  "cds_pool",
  (t) => ({
    id: t.text().primaryKey(), // pool address
    poolId: t.bigint().notNull(),
    referenceAsset: t.hex().notNull(),
    collateralToken: t.hex().notNull(),
    oracle: t.hex().notNull(),
    maturity: t.bigint().notNull(),
    baseSpreadWad: t.bigint().notNull(),
    slopeWad: t.bigint().notNull(),
    creator: t.hex().notNull(),
    status: cdsPoolStatus().notNull(),
    totalDeposits: t.bigint().notNull(),
    totalPremiumsEarned: t.bigint().notNull(),
    totalProtectionSold: t.bigint().notNull(),
    createdAt: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
  }),
  (table) => ({
    referenceAssetIdx: index().on(table.referenceAsset),
    statusIdx: index().on(table.status),
    creatorIdx: index().on(table.creator),
  })
);

export const cdsPoolRelations = relations(cdsPool, ({ many }) => ({
  lpDeposits: many(poolDeposit),
  protectionPositions: many(protectionPosition),
}));

export const poolDeposit = onchainTable(
  "pool_deposit",
  (t) => ({
    id: t.text().primaryKey(), // txHash-logIndex
    poolId: t.text().notNull(),
    lp: t.hex().notNull(),
    amount: t.bigint().notNull(),
    shares: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (table) => ({
    poolIdx: index().on(table.poolId),
    lpIdx: index().on(table.lp),
  })
);

export const poolDepositRelations = relations(poolDeposit, ({ one }) => ({
  pool: one(cdsPool, { fields: [poolDeposit.poolId], references: [cdsPool.id] }),
}));

export const protectionPosition = onchainTable(
  "protection_position",
  (t) => ({
    id: t.text().primaryKey(), // poolAddress-positionId
    poolId: t.text().notNull(),
    positionId: t.bigint().notNull(),
    buyer: t.hex().notNull(),
    notional: t.bigint().notNull(),
    premiumPaid: t.bigint().notNull(),
    spreadWad: t.bigint().notNull(),
    active: t.boolean().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    txHash: t.hex().notNull(),
  }),
  (table) => ({
    poolIdx: index().on(table.poolId),
    buyerIdx: index().on(table.buyer),
  })
);

export const protectionPositionRelations = relations(
  protectionPosition,
  ({ one }) => ({
    pool: one(cdsPool, {
      fields: [protectionPosition.poolId],
      references: [cdsPool.id],
    }),
  })
);

// --- Nexus Module ---

export const marginAccount = onchainTable("margin_account", (t) => ({
  id: t.text().primaryKey(), // user address
  user: t.hex().notNull(),
  openedAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
}));

export const marginAccountRelations = relations(
  marginAccount,
  ({ many }) => ({
    collateralPositions: many(collateralPosition),
    liquidations: many(liquidation),
  })
);

export const collateralPosition = onchainTable(
  "collateral_position",
  (t) => ({
    id: t.text().primaryKey(), // user-asset
    accountId: t.text().notNull(),
    asset: t.hex().notNull(),
    currentBalance: t.bigint().notNull(),
  }),
  (table) => ({
    accountIdx: index().on(table.accountId),
  })
);

export const collateralPositionRelations = relations(
  collateralPosition,
  ({ one }) => ({
    account: one(marginAccount, {
      fields: [collateralPosition.accountId],
      references: [marginAccount.id],
    }),
  })
);

export const liquidation = onchainTable("liquidation", (t) => ({
  id: t.text().primaryKey(),
  accountId: t.text().notNull(),
  liquidator: t.hex().notNull(),
  collateralSeized: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const liquidationRelations = relations(liquidation, ({ one }) => ({
  account: one(marginAccount, {
    fields: [liquidation.accountId],
    references: [marginAccount.id],
  }),
}));

// --- Oracle ---

export const asset = onchainTable("asset", (t) => ({
  id: t.text().primaryKey(), // asset address
  price: t.bigint().notNull(),
  riskWeight: t.bigint().notNull(),
  lastUpdated: t.bigint().notNull(),
}));
