"use client";

import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { FaucetButton } from "@/components/FaucetButton";

export function Header() {
  return (
    <header className="border-b border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link href="/" className="flex items-center gap-2.5 hover:opacity-80 transition-opacity">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--accent)] to-[#0088ff] flex items-center justify-center">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
                <path d="M12 2 L22 8 V16 L12 22 L2 16 V8 Z" stroke="white" strokeWidth="2" fill="none" />
                <path d="M12 8 L17 11 V15 L12 18 L7 15 V11 Z" stroke="white" strokeWidth="1.5" fill="none" />
              </svg>
            </div>
            <span className="text-lg font-bold tracking-tight">Meridian</span>
          </Link>
          <span className="text-xs px-2 py-0.5 rounded-md bg-[var(--accent)]/10 text-[var(--accent)] font-medium border border-[var(--accent)]/20">
            Fuji
          </span>
        </div>
        <div className="flex items-center gap-3">
          <FaucetButton />
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}
