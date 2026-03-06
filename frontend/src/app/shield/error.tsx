"use client";

import Link from "next/link";

export default function ShieldError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="text-center py-12">
      <h2 className="text-lg font-medium mb-2">Failed to Load CDS Contracts</h2>
      <p className="text-sm text-zinc-500 mb-4">
        Could not read CDS data from the Fuji network. Make sure your wallet is connected to Avalanche Fuji (chain ID 43113).
      </p>
      <div className="flex justify-center gap-3">
        <button
          onClick={reset}
          className="px-4 py-2 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] rounded transition-colors"
        >
          Retry
        </button>
        <Link
          href="/"
          className="px-4 py-2 text-sm bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded border border-zinc-700 transition-colors"
        >
          Back to Home
        </Link>
      </div>
    </div>
  );
}
