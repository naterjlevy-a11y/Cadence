"use client";

import { createTimeline } from "animejs";

/**
 * The interim transcript — words render as inline spans in the display
 * serif so they feel like typography, not a form field.
 */
export function TranscriptLine({
  words,
  placeholder,
}: {
  words: string[];
  placeholder: string;
}) {
  return (
    <p
      aria-live="polite"
      className="transcript-line min-h-[2.6rem] max-w-xl text-center font-display text-2xl leading-snug tracking-tight md:text-3xl"
    >
      {words.length === 0 ? (
        <span className="text-mello-ink/30">{placeholder}</span>
      ) : (
        words.map((w, i) => (
          <span key={i} data-word className="mr-[0.45ch] inline-block italic-display text-mello-ink/90">
            {w}
          </span>
        ))
      )}
    </p>
  );
}

/**
 * The money shot: clone every word span into a fixed fly-layer and arc them
 * into the target tile, staggered. Transform/opacity only; clones removed
 * on completion.
 */
export function flyWords(
  wordEls: HTMLElement[],
  target: HTMLElement,
  { onComplete }: { onComplete?: () => void } = {}
) {
  if (wordEls.length === 0 || !target) {
    onComplete?.();
    return null;
  }
  const layer = document.createElement("div");
  layer.className = "fly-layer";
  document.body.appendChild(layer);

  const tr = target.getBoundingClientRect();
  const tx = tr.left + tr.width / 2;
  const ty = tr.top + tr.height / 2;

  const clones = wordEls.map((el) => {
    const r = el.getBoundingClientRect();
    const c = el.cloneNode(true) as HTMLElement;
    c.style.position = "fixed";
    c.style.left = `${r.left}px`;
    c.style.top = `${r.top}px`;
    c.style.margin = "0";
    c.style.willChange = "transform, opacity";
    layer.appendChild(c);
    return { c, r };
  });

  // Fade originals in place while clones take flight.
  wordEls.forEach((el) => {
    el.style.transition = "opacity 180ms ease-out";
    el.style.opacity = "0";
  });

  const tl = createTimeline({
    onComplete: () => {
      layer.remove();
      onComplete?.();
    },
  });

  clones.forEach(({ c, r }, i) => {
    const dx = tx - (r.left + r.width / 2);
    const dy = ty - (r.top + r.height / 2);
    tl.add(
      c,
      {
        translateX: { to: dx, duration: 620, ease: "inOut(3)" },
        translateY: [
          { to: dy - 56, duration: 270, ease: "out(2)" },
          { to: dy, duration: 350, ease: "in(2)" },
        ],
        scale: { to: 0.35, duration: 620, ease: "inOut(3)" },
        opacity: [
          { to: 0.9, duration: 420 },
          { to: 0, duration: 200 },
        ],
      },
      i * 22
    );
  });

  return tl;
}
