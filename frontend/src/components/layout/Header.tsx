"use client";

import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { FaucetButton } from "@/components/FaucetButton";

export function Header() {
  return (
    <header className="sticky top-0 z-50 bg-[#0a0b0f]/80 backdrop-blur-xl">
      <div className="max-w-7xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link href="/" className="group flex items-center gap-2.5 transition-opacity">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--accent)] to-[#0088ff] flex items-center justify-center transition-shadow group-hover:shadow-[0_0_16px_rgba(0,212,170,0.4)]">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
                <path d="M12 2 L22 8 V16 L12 22 L2 16 V8 Z" stroke="white" strokeWidth="2" fill="none" />
                <path d="M12 8 L17 11 V15 L12 18 L7 15 V11 Z" stroke="white" strokeWidth="1.5" fill="none" />
              </svg>
            </div>
            <span className="text-lg font-bold tracking-tight">Meridian</span>
          </Link>
          <span className="text-xs px-2.5 py-0.5 rounded-full bg-[var(--accent)]/10 text-[var(--accent)] font-medium border border-[var(--accent)]/20 flex items-center gap-1.5">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
            </span>
            Fuji
          </span>
        </div>
        <div className="flex items-center gap-3">
          <FaucetButton />
          <ConnectButton />
        </div>
      </div>
      <div className="gradient-border" />
    </header>
  );
}
