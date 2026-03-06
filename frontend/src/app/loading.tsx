export default function Loading() {
  return (
    <div className="flex items-center justify-center py-16">
      <div className="flex items-center gap-3">
        <div className="w-2 h-2 rounded-full bg-[var(--accent)] animate-pulse" />
        <div className="w-2 h-2 rounded-full bg-[var(--accent)] animate-pulse [animation-delay:150ms]" />
        <div className="w-2 h-2 rounded-full bg-[var(--accent)] animate-pulse [animation-delay:300ms]" />
      </div>
    </div>
  );
}
