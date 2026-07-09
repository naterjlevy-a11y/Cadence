"use client";

import { animate, onScroll, stagger, utils } from "animejs";
import { useEffect, useRef, useState } from "react";
import { DESTINATIONS } from "./copy";
import { LightSectionEyebrow } from "./ui";
import { getSprings, prefersReducedMotion, reducedMotion, useAnimeScope } from "./motion";

/**
 * The 10 real destinations as a grid. Reveals with a from-center grid
 * stagger; every ~3.5s a tile auto-demos: a typed "hey <alias>" line
 * appears and the tile pulses.
 */
export function Destinations() {
  const [demo, setDemo] = useState<{ alias: string; idx: number } | null>(null);
  const demoIdxRef = useRef(0);
  const visibleRef = useRef(false);

  const { rootRef } = useAnimeScope((scope) => {
    if (reducedMotion(scope)) return;
    const tiles = Array.from(scope.root.querySelectorAll<HTMLElement>(".dest-card"));
    if (tiles.length === 0) return;
    utils.set(tiles, { opacity: 0, translateY: 20 });
    animate(tiles, {
      opacity: [0, 1],
      translateY: [20, 0],
      scale: [0.96, 1],
      duration: 650,
      ease: "out(3)",
      delay: stagger(45, { grid: [5, 2], from: "center" }),
      autoplay: onScroll({ target: scope.root as HTMLElement, enter: "bottom-=120 top" }),
    });
  });

  // periodic auto-demo
  useEffect(() => {
    if (prefersReducedMotion()) return;
    const root = rootRef.current;
    if (!root) return;
    const io = new IntersectionObserver(([e]) => (visibleRef.current = e.isIntersecting));
    io.observe(root);

    const interval = window.setInterval(() => {
      if (!visibleRef.current || document.hidden) return;
      const idx = demoIdxRef.current % DESTINATIONS.length;
      demoIdxRef.current += 1;
      const dest = DESTINATIONS[idx];
      const alias = dest.aliases[Math.floor(Math.random() * dest.aliases.length)];
      setDemo({ alias, idx });
      const tile = root.querySelectorAll<HTMLElement>(".dest-card")[idx];
      if (tile) {
        animate(tile, {
          scale: [1, 1.06, 1],
          duration: 620,
          ease: getSprings().gulp,
        });
      }
    }, 3500);

    return () => {
      window.clearInterval(interval);
      io.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <section
      id="destinations"
      ref={rootRef as React.Ref<HTMLElement>}
      className="sky-world px-6 py-28"
    >
      <div className="mx-auto max-w-6xl">
        <LightSectionEyebrow>Destinations</LightSectionEyebrow>
      <h2 className="mt-4 max-w-3xl font-display text-5xl leading-tight tracking-tightest md:text-6xl">
        Ten destinations.{" "}
        <span className="italic-display text-mello-deep">Zero pronunciation standards.</span>
      </h2>

      <p className="mt-6 h-6 font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/50" aria-live="off">
        {demo ? (
          <>
            <span className="text-mello-ink/70">&ldquo;hey {demo.alias}&rdquo;</span>
            <span className="mx-2 text-mello-ink/30">→</span>
            <span className="text-mello-deep">{DESTINATIONS[demo.idx].name}</span>
          </>
        ) : (
          <span className="text-mello-ink/30">say it however you say it</span>
        )}
      </p>

      <div className="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {DESTINATIONS.map((d, i) => (
          <div
            key={d.id}
            className={`dest-card group rounded-2xl border p-5 transition-colors duration-300 ${
              demo?.idx === i
                ? "border-mello-deep/60 bg-white/70"
                : "border-mello-ink/10 bg-white/50 hover:border-mello-ink/25"
            }`}
          >
            <h3 className="font-display text-2xl tracking-tightest">{d.name}</h3>
            <p className="mt-1 font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/45">
              {d.hint}
            </p>
            <div className="mt-4 flex flex-wrap gap-1.5">
              {d.aliases.slice(1, 4).map((a) => (
                <span
                  key={a}
                  className="rounded-full border border-mello-ink/10 bg-white/60 px-2 py-0.5 font-mono text-[10px] text-mello-ink/50"
                >
                  &ldquo;{a}&rdquo;
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div></section>
  );
}
