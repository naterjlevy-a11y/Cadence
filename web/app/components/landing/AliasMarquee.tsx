"use client";

import { animate, createTimeline, stagger } from "animejs";
import { useEffect, useRef, useState } from "react";
import { ALIAS_PAIRS } from "./copy";
import { getSprings, prefersReducedMotion } from "./motion";

/**
 * The fuzzy-alias joke. A CSS marquee belt of misheard→resolved pairs,
 * with one featured pair cycling above it: the alias types in char by char,
 * gets struck through, and the resolved name spring-pops in.
 */
export function AliasMarquee() {
  const [idx, setIdx] = useState(0);
  const featureRef = useRef<HTMLDivElement>(null);
  const visibleRef = useRef(false);

  useEffect(() => {
    if (prefersReducedMotion()) return;
    const el = featureRef.current;
    if (!el) return;

    const io = new IntersectionObserver(([e]) => (visibleRef.current = e.isIntersecting));
    io.observe(el);

    let cancelled = false;
    let timer: number;

    const cycle = () => {
      if (cancelled) return;
      if (!visibleRef.current || document.hidden) {
        timer = window.setTimeout(cycle, 1000);
        return;
      }
      const heardChars = el.querySelectorAll<HTMLElement>(".alias-heard span");
      const strike = el.querySelector<HTMLElement>(".alias-strike");
      const resolved = el.querySelector<HTMLElement>(".alias-resolved");
      if (!strike || !resolved) return;

      const tl = createTimeline({
        onComplete: () => {
          timer = window.setTimeout(() => {
            if (cancelled) return;
            setIdx((i) => (i + 1) % ALIAS_PAIRS.length);
            timer = window.setTimeout(cycle, 60);
          }, 1400);
        },
      });
      tl.add(heardChars, {
        opacity: [0, 1],
        translateY: [4, 0],
        duration: 120,
        delay: stagger(38),
        ease: "out(2)",
      })
        .add(strike, { scaleX: [0, 1], duration: 260, ease: "inOut(2)" }, "+=450")
        .add(
          resolved,
          {
            opacity: [0, 1],
            scale: [0.85, 1],
            translateY: [6, 0],
            duration: 500,
            ease: getSprings().snappy,
          },
          "-=80"
        );
    };
    timer = window.setTimeout(cycle, 300);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      io.disconnect();
    };
  }, [idx]);

  const pair = ALIAS_PAIRS[idx];

  return (
    <section className="relative border-y border-white/[0.06] bg-white/[0.015] py-10">
      <p className="mx-auto mb-6 max-w-6xl px-6 text-[12px] font-semibold tracking-wide text-white/50">
        Fuzzy routing · longest-match alias wins
      </p>

      {/* Featured resolving pair */}
      <div
        ref={featureRef}
        className="mx-auto mb-8 flex h-10 max-w-6xl items-center gap-4 px-6 font-mono text-lg md:text-xl"
        aria-live="off"
      >
        <span className="alias-heard relative text-white/60">
          {pair.heard.split("").map((ch, i) => (
            <span key={`${idx}-${i}`} className="inline-block whitespace-pre opacity-0">
              {ch}
            </span>
          ))}
          <span className="alias-strike absolute left-0 top-1/2 h-px w-full origin-left scale-x-0 bg-mello" />
        </span>
        <span className="text-white/30">→</span>
        <span className="alias-resolved font-display text-2xl tracking-tightest text-mello opacity-0 md:text-3xl">
          {pair.resolved}
        </span>
      </div>

      {/* The belt */}
      <div className="no-scrollbar overflow-hidden">
        <div className="marquee-belt flex w-max gap-10 whitespace-nowrap px-6 font-mono text-sm text-white/35">
          {[...ALIAS_PAIRS, ...ALIAS_PAIRS].map((p, i) => (
            <span key={i} className="flex items-center gap-10">
              <span>
                &ldquo;{p.heard}&rdquo; <span className="text-white/20">→</span>{" "}
                <span className="font-display text-base tracking-tightest text-white/55">{p.resolved}</span>
              </span>
              <span className="size-1 rounded-full bg-white/15" />
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
