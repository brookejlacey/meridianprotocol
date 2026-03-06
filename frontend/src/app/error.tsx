"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="text-center py-16">
      <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-red-500/10 border border-red-500/20 mb-4">
        <span className="text-red-400 text-xl">!</span>
      </div>
      <h2 className="text-lg font-medium mb-2">Something went wrong</h2>
      <p className="text-sm text-zinc-500 max-w-md mx-auto mb-6">
        {error.message || "An unexpected error occurred. This may be due to a network issue or contract interaction failure."}
      </p>
      <button
        onClick={reset}
        className="px-4 py-2 text-sm bg-[var(--accent)] hover:bg-[var(--accent-hover)] rounded transition-colors"
      >
        Try Again
      </button>
    </div>
  );
}
