"use client";

import { useEffect, useRef } from "react";
import { prefersReducedMotion } from "./motion";

/**
 * Giant outlined-text marquee band whose speed reacts to scroll velocity —
 * scroll fast and the words rip past. The F1-site staple.
 */
export function MarqueeBand({
  text,
  reverse = false,
}: {
  text: string;
  reverse?: boolean;
}) {
  const beltRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (prefersReducedMotion()) return;
    const belt = beltRef.current;
    if (!belt) return;

    let x = 0;
    let vel = 0;
    let lastY = window.scrollY;
    let raf = 0;
    let visible = true;

    const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting));
    io.observe(belt);

    const loop = () => {
      const y = window.scrollY;
      vel += (Math.min(60, Math.abs(y - lastY)) - vel) * 0.1;
      lastY = y;
      if (visible && !document.hidden) {
        const speed = (0.6 + vel * 0.12) * (reverse ? 1 : -1);
        x += speed;
        const half = belt.scrollWidth / 2;
        if (x <= -half) x += half;
        if (x > 0) x -= half;
        belt.style.transform = `translateX(${x}px)`;
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
    };
  }, [reverse]);

  const chunk = ` ${text} · `;
  return (
    <div className="overflow-hidden border-y border-white/[0.05] py-3" aria-hidden>
      <div ref={beltRef} className="flex w-max whitespace-nowrap will-change-transform">
        {Array.from({ length: 6 }).map((_, i) => (
          <span
            key={i}
            className="text-outline px-2 font-display text-[clamp(2.6rem,6vw,5rem)] uppercase leading-none tracking-tightest"
          >
            {chunk}
          </span>
        ))}
      </div>
    </div>
  );
}
