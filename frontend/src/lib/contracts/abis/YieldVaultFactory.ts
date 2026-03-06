export const YieldVaultFactoryAbi = [
  { type: "function", name: "vaultCount", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "vaults", inputs: [{ name: "", type: "uint256" }], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "getYieldVault", inputs: [{ name: "forgeVault", type: "address" }, { name: "trancheId", type: "uint8" }], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "getVault", inputs: [{ name: "vaultId", type: "uint256" }], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "createYieldVault", inputs: [{ name: "forgeVault", type: "address" }, { name: "trancheId", type: "uint8" }, { name: "name", type: "string" }, { name: "symbol", type: "string" }, { name: "compoundInterval", type: "uint256" }], outputs: [{ name: "yieldVaultAddress", type: "address" }], stateMutability: "nonpayable" },
  { type: "event", name: "YieldVaultCreated", inputs: [{ name: "vaultId", type: "uint256", indexed: true }, { name: "yieldVault", type: "address", indexed: true }, { name: "forgeVault", type: "address", indexed: true }, { name: "trancheId", type: "uint8", indexed: false }, { name: "name", type: "string", indexed: false }, { name: "symbol", type: "string", indexed: false }], anonymous: false },
] as const;
