"use client";

import { animate } from "animejs";
import { useEffect, useRef } from "react";
import { getSprings, prefersReducedMotion } from "./motion";

/**
 * The big pressable spacebar. Purely presentational — parent owns state.
 * Press: cap face drops 6px fast. Release: springs back with a wobble.
 * Idle: a barely-there CSS breathe so it reads as touchable.
 */
export function Keycap({
  pressed,
  onPressStart,
  onPressEnd,
  disabled = false,
}: {
  pressed: boolean;
  onPressStart: () => void;
  onPressEnd: () => void;
  disabled?: boolean;
}) {
  const faceRef = useRef<HTMLSpanElement>(null);
  const first = useRef(true);

  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    const face = faceRef.current;
    if (!face) return;
    if (prefersReducedMotion()) {
      face.style.transform = pressed ? "translateY(6px)" : "translateY(0px)";
      return;
    }
    if (pressed) {
      animate(face, { translateY: 6, duration: 80, ease: "out(3)" });
    } else {
      animate(face, { translateY: 0, duration: 500, ease: getSprings().snappy });
    }
  }, [pressed]);

  return (
    <div className="flex flex-col items-center gap-4">
      <button
        type="button"
        disabled={disabled}
        aria-pressed={pressed}
        aria-label="Hold to talk — or hold your spacebar"
        className={`keycap select-none touch-none ${pressed ? "keycap-pressed" : "keycap-breathe"}`}
        onPointerDown={(e) => {
          if (disabled) return;
          e.currentTarget.setPointerCapture(e.pointerId);
          e.preventDefault();
          onPressStart();
        }}
        onPointerUp={() => !disabled && onPressEnd()}
        onPointerCancel={() => !disabled && onPressEnd()}
        onContextMenu={(e) => e.preventDefault()}
      >
        <span className="keycap-skirt" aria-hidden />
        <span ref={faceRef} className="keycap-face font-mono">
          space
        </span>
      </button>
      <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/50">
        <kbd className="rounded border border-mello-ink/20 bg-white/60 px-1.5 py-0.5">⌥ right option</kbd>{" "}
        on your Mac
      </p>
    </div>
  );
}
