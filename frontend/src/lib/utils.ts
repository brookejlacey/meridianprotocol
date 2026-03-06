import { formatUnits } from "viem";

/** Format a WAD-scaled bigint (18 decimals) to a readable string */
export function formatAmount(value: bigint, decimals = 18, displayDecimals = 2): string {
  return Number(formatUnits(value, decimals)).toLocaleString("en-US", {
    minimumFractionDigits: displayDecimals,
    maximumFractionDigits: displayDecimals,
  });
}

/** Format basis points to percentage string (e.g., 500 -> "5.00%") */
export function formatBps(bps: bigint | number): string {
  const num = typeof bps === "bigint" ? Number(bps) : bps;
  return (num / 100).toFixed(2) + "%";
}

/** Shorten an Ethereum address (e.g., "0x1234...abcd") */
export function shortenAddress(address: string, chars = 4): string {
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

/** Format a unix timestamp (bigint seconds) to a date string */
export function formatDate(timestamp: bigint): string {
  if (timestamp === 0n) return "N/A";
  return new Date(Number(timestamp) * 1000).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

/** Format a WAD-scaled ratio as a percentage (e.g., 1.5e18 -> "150.00%") */
export function formatRatio(ratio: bigint): string {
  if (ratio === BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")) {
    return "∞";
  }
  const pct = Number(formatUnits(ratio, 18)) * 100;
  return pct.toFixed(2) + "%";
}

/** Format a WAD-scaled value as annual spread percentage (e.g., 0.02e18 -> "2.00%") */
export function formatWadPercent(wadValue: bigint, decimals = 2): string {
  const pct = Number(formatUnits(wadValue, 18)) * 100;
  return pct.toFixed(decimals) + "%";
}

/** Pool Status enum matching Solidity CDSPool.PoolStatus */
export const PoolStatus = {
  0: "Active",
  1: "Triggered",
  2: "Settled",
  3: "Expired",
} as const;

/** CDS Status enum matching Solidity */
export const CDSStatus = {
  0: "Active",
  1: "Triggered",
  2: "Settled",
  3: "Expired",
} as const;

/** Vault Status enum matching Solidity */
export const VaultStatus = {
  0: "Open",
  1: "Active",
  2: "Matured",
  3: "Closed",
} as const;
