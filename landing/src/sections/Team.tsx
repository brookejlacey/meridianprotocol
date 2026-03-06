"use client";

import Image from "next/image";
import FadeIn from "@/components/FadeIn";

const team = [
  {
    name: "Brooke Lacey",
    title: "Founder & Engineer",
    headshot: "/Brooke_headshot.jpg",
    bio: "25 years of building software. Systems architect, tech manager, and engineer who's shipped production systems across enterprise and startup. Meridian is what happens when an experienced engineer gets AI-native dev tools.",
    credentials: [
      "25 years in software engineering",
      "Systems architect & technical manager",
      "GlyphStack Labs (AI-native dev)",
      "300K+ followers, 47M+ views",
    ],
    links: {
      github: "https://github.com/brookejlacey",
      x: "https://x.com/brookejlacey",
    },
  },
  {
    name: "Nicki Sanders",
    title: "Co-Founder & Advisor",
    headshot: "/Nicki_headshot.jpg",
    bio: "Blockchain engineer with 10+ years in digital assets. Ex-Anchorage engineering leader who advises startups and institutions on custody architecture, tokenization systems, and secure onchain product design.",
    credentials: [
      "10+ years in digital assets",
      "Ex-Anchorage engineering leader",
      "Custody & tokenization architecture",
      "Startup & institutional advisor",
    ],
    links: {
      github: "https://github.com/nickisanders",
      x: "https://x.com/nickisanders",
    },
  },
];

export default function Team() {
  return (
    <section id="team" className="section relative overflow-hidden">
      <div className="absolute inset-0 dot-grid-bg opacity-50" />
      <div className="relative z-10 max-w-5xl mx-auto">
        <FadeIn>
          <p className="text-accent text-sm font-semibold uppercase tracking-widest mb-4 text-center">
            The Team
          </p>
          <h2 className="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight text-center mb-4 leading-tight">
            Built by engineers,<br className="hidden md:block" />
            <span className="text-muted">not just dreamers</span>
          </h2>
          <p className="text-foreground/50 text-center text-lg max-w-2xl mx-auto mb-16">
            Partners at <span className="text-accent font-medium">GirlCode</span>,
            combining decades of engineering experience with deep blockchain expertise.
          </p>
        </FadeIn>

        <div className="grid md:grid-cols-2 gap-6">
          {team.map((member, idx) => (
            <FadeIn key={member.name} delay={0.15 + idx * 0.1}>
              <div className="p-6 rounded-2xl border border-white/5 bg-surface/60 hover:border-accent/10 transition-all h-full">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-16 h-16 rounded-full overflow-hidden border-2 border-white/10 relative flex-shrink-0">
                    <Image
                      src={member.headshot}
                      alt={member.name}
                      fill
                      className="object-cover"
                    />
                  </div>
                  <div>
                    <h3 className="text-lg font-bold">{member.name}</h3>
                    <p className="text-accent text-sm font-medium">{member.title}</p>
                  </div>
                </div>

                <p className="text-foreground/60 text-sm leading-relaxed mb-4">
                  {member.bio}
                </p>

                <div className="flex flex-wrap gap-1.5 mb-4">
                  {member.credentials.map((c, i) => (
                    <span
                      key={i}
                      className="px-2.5 py-1 text-[11px] rounded-full bg-white/5 text-foreground/50 border border-white/5"
                    >
                      {c}
                    </span>
                  ))}
                </div>

                <div className="flex gap-2">
                  {member.links.github && (
                    <a
                      href={member.links.github}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="w-8 h-8 rounded-lg border border-white/10 flex items-center justify-center text-muted hover:text-accent hover:border-accent/30 transition-all"
                    >
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
                      </svg>
                    </a>
                  )}
                  {member.links.x && (
                    <a
                      href={member.links.x}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="w-8 h-8 rounded-lg border border-white/10 flex items-center justify-center text-muted hover:text-accent hover:border-accent/30 transition-all"
                    >
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                      </svg>
                    </a>
                  )}
                </div>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}
