"use client";

import { animate } from "animejs";
import { useEffect, useRef } from "react";
import { getSprings, prefersReducedMotion } from "./motion";

/** Magnetic hover: the child leans toward the cursor, springs back on leave. */
export function Magnetic({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (prefersReducedMotion()) return;
    if (!window.matchMedia("(pointer: fine)").matches) return;
    const el = ref.current;
    if (!el) return;
    const child = el.firstElementChild as HTMLElement | null;
    if (!child) return;

    const onMove = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      const dx = e.clientX - (r.left + r.width / 2);
      const dy = e.clientY - (r.top + r.height / 2);
      child.style.transform = `translate(${dx * 0.22}px, ${dy * 0.22}px)`;
    };
    const onLeave = () => {
      animate(child, { translateX: 0, translateY: 0, duration: 600, ease: getSprings().snappy });
    };
    el.addEventListener("pointermove", onMove);
    el.addEventListener("pointerleave", onLeave);
    return () => {
      el.removeEventListener("pointermove", onMove);
      el.removeEventListener("pointerleave", onLeave);
    };
  }, []);

  return (
    <div ref={ref} className="inline-block p-2">
      {children}
    </div>
  );
}
