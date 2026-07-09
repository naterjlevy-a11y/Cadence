"use client";

import { useEffect, useRef } from "react";
import { prefersReducedMotion } from "./motion";

/** Tiny nav waveform that dances with scroll velocity — the site hears you scroll. */
export function NavPulse({ muted = false }: { muted?: boolean }) {
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (prefersReducedMotion()) return;
    const el = ref.current;
    if (!el) return;
    const bars = Array.from(el.children) as HTMLElement[];
    let vel = 0;
    let lastY = window.scrollY;
    let t = 0;
    let raf = 0;
    const loop = () => {
      const y = window.scrollY;
      vel += (Math.min(50, Math.abs(y - lastY)) - vel) * 0.12;
      lastY = y;
      t += 0.12;
      bars.forEach((b, i) => {
        const s = 0.25 + Math.min(0.75, vel / 40) * Math.abs(Math.sin(t * 1.6 + i * 1.1));
        b.style.transform = `scaleY(${s.toFixed(3)})`;
      });
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <span ref={ref} aria-hidden className="ml-1 flex h-4 items-center gap-[3px]">
      {[10, 16, 12, 16, 10].map((h, i) => (
        <span
          key={i}
          className={`w-[2.5px] origin-center rounded-full ${muted ? "bg-mello-deep/70" : "bg-mello/70"}`}
          style={{ height: h }}
        />
      ))}
    </span>
  );
}
