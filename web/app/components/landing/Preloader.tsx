"use client";

import { animate, createTimeline, stagger } from "animejs";
import { useEffect, useRef, useState } from "react";
import { prefersReducedMotion } from "./motion";

/** Black curtain, mono counter 000→100, waveform pulse, curtain lifts. */
export function Preloader() {
  const [gone, setGone] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    if (prefersReducedMotion()) {
      setGone(true);
      return;
    }
    document.documentElement.classList.add("preloading");
    const counter = root.querySelector<HTMLElement>(".pre-count");
    const bars = Array.from(root.querySelectorAll<HTMLElement>(".pre-bar"));
    const obj = { v: 0 };

    const tl = createTimeline({
      onComplete: () => {
        document.documentElement.classList.remove("preloading");
        setGone(true);
      },
    });
    tl.add(bars, {
      scaleY: [0.15, 1],
      duration: 500,
      ease: "inOut(2)",
      delay: stagger(40, { from: "center" }),
      loop: 2,
      alternate: true,
    }, 0)
      .add(obj, {
        v: 100,
        duration: 1500,
        ease: "inOut(3)",
        onUpdate: () => {
          if (counter) counter.textContent = String(Math.round(obj.v)).padStart(3, "0");
        },
      }, 0)
      .add(root.querySelector(".pre-inner") as HTMLElement, { opacity: [1, 0], duration: 260, ease: "out(2)" }, 1550)
      .add(root, { translateY: ["0%", "-100%"], duration: 700, ease: "inOut(4)" }, 1650);

    return () => {
      tl.pause();
      document.documentElement.classList.remove("preloading");
    };
  }, []);

  if (gone) return null;
  return (
    <div
      ref={rootRef}
      className="fixed inset-0 z-[100] flex items-center justify-center bg-mello-ink"
      aria-hidden
    >
      <div className="pre-inner flex flex-col items-center gap-8">
        {/* the mark — same as nav/footer/app */}
        <span className="grid size-12 place-items-center rounded-2xl bg-mello">
          <svg width="24" height="24" viewBox="0 0 18 18" fill="none">
            <path
              d="M3 14V4l3 4 3-5 3 5 3-4v10"
              stroke="white"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </span>
        <div className="flex h-14 items-end gap-1.5">
          {[18, 34, 24, 46, 30, 22, 40, 28, 44, 20, 36, 26].map((h, i) => (
            <span
              key={i}
              className="pre-bar w-1.5 origin-bottom rounded-full bg-mello"
              style={{ height: `${h}px` }}
            />
          ))}
        </div>
        <div className="font-mono text-[11px] uppercase tracking-[0.2em] text-white/55">
          <span className="pre-count text-mello">000</span> · CADENCE
        </div>
      </div>
    </div>
  );
}
