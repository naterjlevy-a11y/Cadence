"use client";

import Lenis from "lenis";
import { useEffect } from "react";
import { prefersReducedMotion } from "./motion";

/** Inertia scrolling. The single biggest "expensive site" feel lever. */
export function SmoothScroll() {
  useEffect(() => {
    if (prefersReducedMotion()) return;
    // Lower lerp = silkier scrub for scroll-linked timelines (portal, etc.).
    document.documentElement.classList.add("lenis");
    const lenis = new Lenis({
      lerp: 0.1,
      smoothWheel: true,
      wheelMultiplier: 0.85,
      touchMultiplier: 1.1,
    });
    (window as unknown as Record<string, unknown>).__lenis = lenis;
    let raf = 0;
    const loop = (t: number) => {
      lenis.raf(t);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      lenis.destroy();
      document.documentElement.classList.remove("lenis");
      delete (window as unknown as Record<string, unknown>).__lenis;
    };
  }, []);
  return null;
}
