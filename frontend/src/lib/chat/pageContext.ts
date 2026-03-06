const PAGE_CONTEXTS: Record<string, string> = {
  "/": "The home/dashboard page. Users see an overview of the Meridian protocol, key stats, and can navigate to any section.",

  "/invest": "The Invest page (Forge Vaults). Users can deposit USDC into structured credit vaults and choose between Senior, Mezzanine, or Equity tranches. Each tranche has different risk/return profiles. Help them understand which tranche suits their goals.",

  "/pools": "The CDS Pools page. Users can provide liquidity to credit default swap AMM pools to earn spread fees, or buy protection against credit events. Key metrics: utilization rate, current spread, total liquidity. Higher utilization = higher spreads.",

  "/hedge": "The Hedge page (Shield CDS). Users can buy or sell credit default swap protection on specific reference assets. Protection buyers pay a premium; sellers collect it. If a credit event triggers, buyers receive a payout.",

  "/yield": "The Yield page (ERC-4626 Vaults). Users can deposit into auto-compounding yield vaults for Senior, Mezzanine, or Equity tranches. The LPIncentiveGauge distributes MERID reward tokens to LPs based on their gauge share.",

  "/trade": "The Trade page (Secondary Market). Users can swap tranche tokens on DEX or use Swap & Reinvest to atomically sell one tranche position and invest in another. Note: SecondaryMarketRouter may not be deployed yet.",

  "/faucet": "The Faucet page. Users can mint free MockUSDC test tokens for use on Fuji testnet. They also need test AVAX from the Avalanche faucet (faucet.avax.network) for gas fees.",

  "/ai": "The AI page. Users can view AI-generated risk scores (AIRiskOracle), strategy recommendations (AIStrategyOptimizer), automated keeper actions (AIKeeper), and credit deterioration signals (AICreditDetector).",
};

export function getPageContext(pathname: string): string {
  // Exact match first
  if (PAGE_CONTEXTS[pathname]) return PAGE_CONTEXTS[pathname];

  // Try matching the first path segment (e.g., /pools/0x123 → /pools)
  const base = "/" + pathname.split("/").filter(Boolean)[0];
  return PAGE_CONTEXTS[base] || "";
}

export function getSuggestedPrompts(pathname: string): string[] {
  const base = "/" + pathname.split("/").filter(Boolean)[0];

  switch (base) {
    case "/invest":
      return [
        "What's the difference between Senior and Equity tranches?",
        "How do I deposit into a Forge vault?",
        "What happens if there's a default?",
      ];
    case "/pools":
      return [
        "How do I provide liquidity to a CDS pool?",
        "What does the utilization rate mean?",
        "How is the spread calculated?",
      ];
    case "/hedge":
      return [
        "How does credit default swap protection work?",
        "What triggers a credit event payout?",
        "How much does protection cost?",
      ];
    case "/yield":
      return [
        "How do the yield vaults auto-compound?",
        "What are MERID reward tokens?",
        "Which tranche vault has the highest APY?",
      ];
    case "/faucet":
      return [
        "How do I get test tokens?",
        "Where do I get test AVAX for gas?",
      ];
    case "/ai":
      return [
        "How does the AI risk oracle work?",
        "What does the strategy optimizer recommend?",
        "How are credit events detected?",
      ];
    default:
      return [
        "What is Meridian Protocol?",
        "How do I get started?",
        "What are the six protocol layers?",
      ];
  }
}
