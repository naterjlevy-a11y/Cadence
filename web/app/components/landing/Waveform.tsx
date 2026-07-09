"use client";

import { useEffect, useRef } from "react";
import { prefersReducedMotion } from "./motion";

/**
 * Canvas waveform bars. One rAF loop, transform-free (pure canvas), pauses
 * when off-screen or tab hidden.
 *
 * - active=false      → low idle bars with a faint shimmer
 * - active + getLevel → bars driven by real mic amplitude (0..1)
 * - active, no getLevel → simulated speech noise (for scripted takes)
 */
export function Waveform({
  active,
  getLevel = null,
  bars = 48,
  className = "",
}: {
  active: boolean;
  getLevel?: (() => number) | null;
  bars?: number;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stateRef = useRef({ active, getLevel });
  stateRef.current = { active, getLevel };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const reduced = prefersReducedMotion();
    const heights = new Float32Array(bars).fill(0.08);
    let raf = 0;
    let visible = true;
    let running = false;
    let t = 0;

    const io = new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
      sync();
    });
    io.observe(canvas);

    const onVis = () => sync();
    document.addEventListener("visibilitychange", onVis);

    function resize() {
      if (!canvas) return;
      const dpr = window.devicePixelRatio || 1;
      const { width, height } = canvas.getBoundingClientRect();
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx?.scale(dpr, dpr);
    }
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    function draw() {
      if (!canvas || !ctx) return;
      const { width, height } = canvas.getBoundingClientRect();
      ctx.clearRect(0, 0, width, height);
      const gap = 3;
      const barW = Math.max(2, (width - gap * (bars - 1)) / bars);
      const { active: isActive, getLevel: level } = stateRef.current;

      t += 0.055;
      const amp = isActive ? (level ? Math.min(1, level() * 2.2) : null) : 0;

      for (let i = 0; i < bars; i++) {
        // envelope: taller in the middle, like a real meter
        const shape = 0.35 + 0.65 * Math.sin((i / (bars - 1)) * Math.PI);
        let target: number;
        if (!isActive) {
          target = 0.06 + 0.03 * Math.sin(t * 0.6 + i * 0.9);
        } else if (amp !== null) {
          const jitter = 0.6 + 0.4 * Math.abs(Math.sin(t * 2.1 + i * 1.7));
          target = Math.max(0.08, amp * shape * jitter);
        } else {
          // simulated speech: layered sines read as natural cadence
          const speech =
            0.45 +
            0.3 * Math.sin(t * 1.8 + i * 0.7) * Math.sin(t * 0.7) +
            0.25 * Math.abs(Math.sin(t * 3.3 + i * 2.3));
          target = Math.max(0.08, speech * shape);
        }
        heights[i] += (target - heights[i]) * (reduced ? 1 : 0.25);

        const h = Math.max(2, heights[i] * height);
        const x = i * (barW + gap);
        const y = (height - h) / 2;
        ctx.fillStyle = `rgba(124, 156, 255, ${0.45 + heights[i] * 0.55})`;
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, barW / 2);
        ctx.fill();
      }
    }

    function loop() {
      draw();
      raf = requestAnimationFrame(loop);
    }

    function sync() {
      const shouldRun = visible && !document.hidden && !reduced;
      if (shouldRun && !running) {
        running = true;
        raf = requestAnimationFrame(loop);
      } else if (!shouldRun && running) {
        running = false;
        cancelAnimationFrame(raf);
        if (reduced) draw(); // one static frame
      }
    }
    if (reduced) draw();
    else sync();

    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
      ro.disconnect();
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [bars]);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className={`h-12 w-full max-w-md ${className}`}
    />
  );
}
