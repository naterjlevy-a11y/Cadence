"use client";

import { useEffect, useRef } from "react";
import { prefersReducedMotion } from "./motion";

/**
 * The hero's living background: a field of particles forming an undulating
 * waveform ridge across the viewport. Particles repel from the cursor; when
 * the mic is live, real amplitude drives the ridge. Canvas 2D, one rAF,
 * pauses off-screen.
 */
export function ParticleField({
  getLevel = null,
  active = false,
}: {
  getLevel?: (() => number) | null;
  active?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const propsRef = useRef({ getLevel, active });
  propsRef.current = { getLevel, active };

  useEffect(() => {
    if (prefersReducedMotion()) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let W = 0;
    let H = 0;
    let raf = 0;
    let running = false;
    let visible = true;
    let t = 0;
    let mx = -9999;
    let my = -9999;
    let amp = 0;

    const isMobile = window.innerWidth < 768;
    const COLS = isMobile ? 70 : 150;
    const ROWS = isMobile ? 9 : 13;
    type P = { ox: number; oy: number; x: number; y: number };
    let pts: P[] = [];

    function layout() {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const r = canvas!.getBoundingClientRect();
      W = r.width;
      H = r.height;
      canvas!.width = Math.round(W * dpr);
      canvas!.height = Math.round(H * dpr);
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      pts = [];
      for (let c = 0; c < COLS; c++) {
        for (let rw = 0; rw < ROWS; rw++) {
          const x = (c / (COLS - 1)) * W;
          const y = H * 0.5 + (rw - (ROWS - 1) / 2) * (H * 0.05);
          pts.push({ ox: x, oy: y, x, y });
        }
      }
    }
    layout();
    const ro = new ResizeObserver(layout);
    ro.observe(canvas);

    const io = new IntersectionObserver(([e]) => {
      visible = e.isIntersecting;
      sync();
    });
    io.observe(canvas);
    const onVis = () => sync();
    document.addEventListener("visibilitychange", onVis);

    const onMove = (e: PointerEvent) => {
      const r = canvas!.getBoundingClientRect();
      mx = e.clientX - r.left;
      my = e.clientY - r.top;
    };
    const onLeave = () => {
      mx = -9999;
      my = -9999;
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeave);

    function draw() {
      const { getLevel: gl, active: act } = propsRef.current;
      t += 0.016;
      const targetAmp = act ? (gl ? Math.min(1, gl() * 2.4) : 0.55) : 0.16;
      amp += (targetAmp - amp) * 0.08;

      ctx!.clearRect(0, 0, W, H);
      const R = 110;
      for (let i = 0; i < pts.length; i++) {
        const p = pts[i];
        const nx = p.ox / W;
        // layered waves — the ridge
        const wave =
          Math.sin(nx * 7 + t * 1.4) * 0.5 +
          Math.sin(nx * 13 - t * 0.9) * 0.3 +
          Math.sin(nx * 23 + t * 2.3) * 0.2;
        const centerBias = Math.sin(nx * Math.PI);
        const ty = p.oy + wave * amp * H * 0.22 * centerBias;

        // cursor repulsion
        let tx = p.ox;
        const dx = p.x - mx;
        const dy = p.y - my;
        const d = Math.hypot(dx, dy);
        let push = 0;
        if (d < R && d > 0.01) {
          push = (1 - d / R) * 34;
          tx = p.ox + (dx / d) * push;
        }
        const tyy = d < R && d > 0.01 ? ty + (dy / d) * push : ty;

        p.x += (tx - p.x) * 0.09;
        p.y += (tyy - p.y) * 0.09;

        const dev = Math.abs(p.y - p.oy) / (H * 0.2);
        const a = 0.10 + Math.min(0.75, dev * 1.1 + amp * 0.25);
        const size = 1 + Math.min(1.6, dev * 2.2);
        ctx!.fillStyle = `rgba(124, 156, 255, ${a})`;
        ctx!.fillRect(p.x, p.y, size, size);
      }
    }

    function loop() {
      draw();
      raf = requestAnimationFrame(loop);
    }
    function sync() {
      const should = visible && !document.hidden;
      if (should && !running) {
        running = true;
        raf = requestAnimationFrame(loop);
      } else if (!should && running) {
        running = false;
        cancelAnimationFrame(raf);
      }
    }
    sync();

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
      window.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", onLeave);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className="pointer-events-none absolute inset-0 h-full w-full"
    />
  );
}
