export const SecondaryMarketRouterAbi = [
  {
    type: "function",
    name: "dex",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "quoteSwap",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swap",
    inputs: [
      {
        name: "p",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minAmountOut", type: "uint256" },
        ],
      },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "swapAndReinvest",
    inputs: [
      {
        name: "p",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minUnderlying", type: "uint256" },
          { name: "vault", type: "address" },
          { name: "trancheId", type: "uint8" },
        ],
      },
    ],
    outputs: [{ name: "invested", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "swapAndHedge",
    inputs: [
      {
        name: "p",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minUnderlying", type: "uint256" },
          { name: "vault", type: "address" },
          { name: "trancheId", type: "uint8" },
          { name: "cds", type: "address" },
          { name: "maxPremium", type: "uint256" },
        ],
      },
    ],
    outputs: [{ name: "invested", type: "uint256" }],
    stateMutability: "nonpayable",
  },
] as const;
