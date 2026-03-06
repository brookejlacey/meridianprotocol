#!/usr/bin/env node
/**
 * Extract ABIs from Foundry out/ artifacts into TypeScript files.
 * Usage: node scripts/extract-abis.js
 */
const fs = require("fs");
const path = require("path");

const OUT_DIR = path.resolve(__dirname, "../../out");
const ABI_DIR = path.resolve(__dirname, "../src/lib/contracts/abis");

const CONTRACTS = [
  { source: "ForgeFactory.sol/ForgeFactory.json", name: "ForgeFactory" },
  { source: "ForgeVault.sol/ForgeVault.json", name: "ForgeVault" },
  { source: "ShieldFactory.sol/ShieldFactory.json", name: "ShieldFactory" },
  { source: "CDSContract.sol/CDSContract.json", name: "CDSContract" },
  { source: "NexusHub.sol/NexusHub.json", name: "NexusHub" },
  { source: "NexusVault.sol/NexusVault.json", name: "NexusVault" },
  { source: "ERC20.sol/ERC20.json", name: "ERC20" },
];

if (!fs.existsSync(ABI_DIR)) {
  fs.mkdirSync(ABI_DIR, { recursive: true });
}

for (const { source, name } of CONTRACTS) {
  const filePath = path.join(OUT_DIR, source);
  if (!fs.existsSync(filePath)) {
    console.warn(`SKIP: ${filePath} not found`);
    continue;
  }
  const artifact = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  const abi = JSON.stringify(artifact.abi, null, 2);
  const tsContent = `export const ${name}Abi = ${abi} as const;\n`;
  const outPath = path.join(ABI_DIR, `${name}.ts`);
  fs.writeFileSync(outPath, tsContent);
  console.log(`OK: ${name} (${artifact.abi.length} entries) -> ${outPath}`);
}

console.log("\nDone.");
