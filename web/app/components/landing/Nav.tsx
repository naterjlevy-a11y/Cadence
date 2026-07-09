"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Logo } from "./ui";
import { NavPulse } from "./NavPulse";
import { DOWNLOAD_URL } from "./copy";

export function Nav() {
  const [light, setLight] = useState(false);

  useEffect(() => {
    const hero = document.getElementById("hero");
    if (!hero) return;
    const io = new IntersectionObserver(
      ([e]) => setLight(e.isIntersecting && e.intersectionRatio > 0.12),
      { threshold: [0, 0.12, 0.35] }
    );
    io.observe(hero);
    return () => io.disconnect();
  }, []);

  return (
    <header
      className={`absolute inset-x-0 top-0 z-30 transition-colors duration-500 ${
        light ? "text-mello-ink" : "text-white"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
        <Link href="/" className="group flex items-center gap-3">
          <Logo />
          <span className="font-display text-xl tracking-tightest">Cadence</span>
          <NavPulse muted={light} />
        </Link>
        <nav
          className={`hidden items-center gap-7 text-sm md:flex ${
            light ? "text-mello-ink/70" : "text-white/70"
          }`}
        >
          <Link href="#how" className={light ? "hover:text-mello-ink" : "hover:text-white"}>
            How it works
          </Link>
          <Link href="#destinations" className={light ? "hover:text-mello-ink" : "hover:text-white"}>
            Destinations
          </Link>
          <Link href="#faq" className={light ? "hover:text-mello-ink" : "hover:text-white"}>
            FAQ
          </Link>
          <a
            href={DOWNLOAD_URL}
            className={`rounded-full border px-4 py-1.5 transition ${
              light
                ? "border-mello-ink/15 bg-mello-ink/[0.04] hover:bg-mello-ink/[0.08]"
                : "border-white/15 bg-white/[0.06] hover:bg-white/[0.12]"
            }`}
          >
            Download
          </a>
        </nav>
      </div>
    </header>
  );
}
