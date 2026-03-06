"use client";

import { useEffect, useState } from "react";

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? "bg-[#0a0b0f]/90 backdrop-blur-xl border-b border-white/5 shadow-lg shadow-black/20"
          : "bg-transparent"
      }`}
    >
      <div className="max-w-7xl mx-auto px-6 flex items-center justify-between h-16">
        {/* Logo */}
        <a href="#" className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-accent to-[#0088ff] flex items-center justify-center">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
              <path d="M12 2 L22 8 V16 L12 22 L2 16 V8 Z" stroke="white" strokeWidth="2" fill="none" />
              <path d="M12 8 L17 11 V15 L12 18 L7 15 V11 Z" stroke="white" strokeWidth="1.5" fill="none" />
            </svg>
          </div>
          <span className="text-lg font-bold tracking-tight">Meridian</span>
        </a>

        {/* Links */}
        <div className="hidden md:flex items-center gap-8">
          <a href="#problem" className="text-sm text-muted hover:text-foreground transition-colors">Problem</a>
          <a href="#solution" className="text-sm text-muted hover:text-foreground transition-colors">Solution</a>
          <a href="#how-it-works" className="text-sm text-muted hover:text-foreground transition-colors">How It Works</a>
          <a href="#team" className="text-sm text-muted hover:text-foreground transition-colors">Team</a>
        </div>

        {/* CTAs */}
        <div className="flex items-center gap-3">
          <a
            href="https://github.com/brookejlacey/meridianprotocol"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:flex items-center gap-2 px-4 py-2 text-sm text-muted hover:text-foreground border border-white/10 rounded-lg hover:border-white/20 transition-all"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
            GitHub
          </a>
          <a
            href="https://app.meridianprotocol.xyz"
            target="_blank"
            rel="noopener noreferrer"
            className="px-4 py-2 text-sm font-medium bg-accent text-black rounded-lg hover:bg-accent/90 transition-colors"
          >
            Launch App
          </a>
        </div>
      </div>
    </nav>
  );
}
