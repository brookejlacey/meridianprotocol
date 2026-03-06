"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const tabs = [
  { name: "Forge", href: "/forge", description: "Structured Credit" },
  { name: "Shield", href: "/shield", description: "Credit Default Swaps" },
  { name: "Pools", href: "/pools", description: "CDS AMM" },
  { name: "Nexus", href: "/nexus", description: "Cross-Chain Margin" },
  { name: "Trade", href: "/trade", description: "Secondary Market" },
  { name: "Strategies", href: "/strategies", description: "Yield Optimizer" },
  { name: "Analytics", href: "/analytics", description: "Risk Dashboard" },
];

export function Navigation() {
  const pathname = usePathname();

  return (
    <nav className="border-b border-[var(--card-border)] bg-[var(--card-bg)]">
      <div className="max-w-7xl mx-auto px-4">
        <div className="flex gap-1 overflow-x-auto">
          {tabs.map((tab) => {
            const isActive = pathname.startsWith(tab.href);
            return (
              <Link
                key={tab.href}
                href={tab.href}
                className={`px-4 py-3 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                  isActive
                    ? "border-[var(--accent)] text-white"
                    : "border-transparent text-zinc-400 hover:text-zinc-200 hover:border-zinc-600"
                }`}
              >
                {tab.name}
                <span className="ml-2 text-xs text-zinc-500 hidden lg:inline">{tab.description}</span>
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
