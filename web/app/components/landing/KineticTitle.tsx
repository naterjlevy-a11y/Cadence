"use client";

import { animate, splitText, stagger, utils } from "animejs";
import { useEffect, useRef } from "react";
import { getSprings, reducedMotion, useAnimeScope } from "./motion";

// The h1's inner DOM is managed imperatively (splitText mutates it, the
// override flip rewrites the italic span) — so React must never reconcile
// it. Constant dangerouslySetInnerHTML keeps React's hands off.
const TITLE_HTML =
  'Hold a key.<br/>Talk to <span class="kt-italic inline-block font-bold text-mello">anything.</span>';

/**
 * The hero headline. Chars spring in staggered with a slight scatter of
 * rotation; after entrance, chars within 80px of the cursor get gently
 * repelled (rAF-lerped, transform-only, pointer devices only).
 * The italic word flips to the routed destination name during demos.
 */
export function KineticTitle({ overrideWord }: { overrideWord: string | null }) {
  const firstOverride = useRef(true);

  const { rootRef } = useAnimeScope((scope) => {
    const h1 = scope.root.querySelector("h1");
    if (!h1) return;

    if (reducedMotion(scope)) return;

    let chars: HTMLElement[] = [];
    try {
      const split = splitText(h1, { chars: true, words: false });
      chars = (split.chars as HTMLElement[]) ?? [];
    } catch {
      return;
    }
    if (chars.length === 0) return;

    animate(chars, {
      translateY: ["0.55em", "0em"],
      rotate: () => utils.random(-6, 6),
      opacity: [0, 1],
      ease: getSprings().snappy,
      duration: 700,
      delay: stagger(22),
      onComplete: () => {
        // rotate back to 0 so repulsion transforms don't inherit tilt
        chars.forEach((c) => {
          c.style.transform = "";
          c.style.opacity = "";
        });
      },
    });

    // ── cursor repulsion (pointer-fine devices only) ──
    if (!window.matchMedia("(pointer: fine)").matches) return;

    const R = 80;
    const items = chars.map((el) => ({ el, y: 0, ty: 0, x: 0, tx: 0 }));
    let mx = -9999;
    let my = -9999;
    let raf = 0;
    let running = false;

    const loop = () => {
      let alive = false;
      for (const it of items) {
        if (!it.el.isConnected) continue;
        const r = it.el.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        const dx = cx - mx;
        const dy = cy - my;
        const d = Math.hypot(dx, dy);
        if (d < R && d > 0.01) {
          const f = (1 - d / R) * 14;
          it.tx = (dx / d) * f * 0.6;
          it.ty = (dy / d) * f - f * 0.4;
        } else {
          it.tx = 0;
          it.ty = 0;
        }
        it.x += (it.tx - it.x) * 0.16;
        it.y += (it.ty - it.y) * 0.16;
        if (Math.abs(it.x) > 0.05 || Math.abs(it.y) > 0.05) {
          it.el.style.transform = `translate(${it.x.toFixed(2)}px, ${it.y.toFixed(2)}px)`;
          alive = true;
        } else if (it.el.style.transform) {
          it.el.style.transform = "";
        }
      }
      if (alive || mx > -9000) raf = requestAnimationFrame(loop);
      else running = false;
    };

    const onMove = (e: PointerEvent) => {
      mx = e.clientX;
      my = e.clientY;
      if (!running) {
        running = true;
        raf = requestAnimationFrame(loop);
      }
    };
    const onLeave = () => {
      mx = -9999;
      my = -9999;
    };
    h1.addEventListener("pointermove", onMove as EventListener);
    h1.addEventListener("pointerleave", onLeave);
    return () => {
      cancelAnimationFrame(raf);
      h1.removeEventListener("pointermove", onMove as EventListener);
      h1.removeEventListener("pointerleave", onLeave);
    };
  });

  // Flip "anything." ↔ destination name imperatively — never through React,
  // because splitText owns this DOM subtree.
  useEffect(() => {
    if (firstOverride.current) {
      firstOverride.current = false;
      return;
    }
    const root = rootRef.current;
    const italic = root?.querySelector<HTMLElement>(".kt-italic");
    if (!italic) return;
    italic.textContent = overrideWord ?? "anything.";
    animate(italic, {
      scale: [0.92, 1],
      opacity: [0.4, 1],
      duration: 450,
      ease: getSprings().snappy,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [overrideWord]);

  return (
    <div ref={rootRef as React.Ref<HTMLDivElement>}>
      <h1
        className="text-center text-[clamp(2.5rem,6vw,5.2rem)] font-semibold leading-[1.03] tracking-[-0.035em]"
        // Constant string — React renders once and never reconciles inside.
        dangerouslySetInnerHTML={{ __html: TITLE_HTML }}
      />
    </div>
  );
}
