"use client";

export default function Footer() {
  return (
    <footer className="border-t border-white/5 py-12 px-6">
      <div className="max-w-6xl mx-auto flex flex-col md:flex-row items-center justify-between gap-6">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-accent to-[#0088ff] flex items-center justify-center">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
              <path d="M12 2 L22 8 V16 L12 22 L2 16 V8 Z" stroke="white" strokeWidth="2" fill="none" />
              <path d="M12 8 L17 11 V15 L12 18 L7 15 V11 Z" stroke="white" strokeWidth="1.5" fill="none" />
            </svg>
          </div>
          <span className="text-sm font-semibold">Meridian Protocol</span>
        </div>

        <p className="text-xs text-muted">
          Built for the Avalanche Build Games 2026 &middot; GlyphStack Labs
        </p>

        <div className="flex items-center gap-4">
          <a
            href="https://app.meridianprotocol.xyz"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-muted hover:text-accent transition-colors"
          >
            App
          </a>
          <a
            href="https://github.com/brookejlacey/meridianprotocol"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-muted hover:text-accent transition-colors"
          >
            GitHub
          </a>
          <a
            href="https://subnets-test.avax.network/c-chain/address/0xD243eB302C08511743B0050cE77c02C80FeccCc8"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-muted hover:text-accent transition-colors"
          >
            Explorer
          </a>
        </div>
      </div>
    </footer>
  );
}
