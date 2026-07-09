"use client";

import { createTimeline, onScroll, stagger, svg } from "animejs";
import { reducedMotion, useAnimeScope } from "./motion";
import { SectionEyebrow } from "./ui";

const PHRASE = ["hey", "claude,", "summarize", "the", "standup"];
const PREFIX_LEN = 2; // "hey claude," is the routing phrase

/**
 * The pinned, scroll-scrubbed "three movements" scene. One timeline drives
 * Hold → Speak → Release on a shared mini-desktop stage while the numbered
 * text blocks crossfade in the margin. Without JS (or with reduced motion)
 * the section unpins via CSS and reads as three static blocks + end-state.
 */
export function ThreeMovements() {
  const { rootRef } = useAnimeScope((scope) => {
    if (reducedMotion(scope)) return;
    const root = scope.root as HTMLElement;
    const section = root;

    const q = (sel: string) => root.querySelector<HTMLElement>(sel);
    const qa = (sel: string) => Array.from(root.querySelectorAll<HTMLElement>(sel));

    const keyFace = q(".tm-key-face");
    const stamp = q(".tm-stamp");
    const bars = qa(".tm-bar");
    const words = qa(".tm-word");
    const prefix = qa(".tm-word-prefix");
    const typed = q(".tm-typed");
    const caption3 = q(".tm-caption-3");
    const checkPath = q(".tm-check-path");
    if (!keyFace || !stamp || !typed || !caption3 || !checkPath) return;

    const drawable = svg.createDrawable(checkPath as unknown as SVGPathElement);

    const tl = createTimeline({
      defaults: { ease: "inOut(2)", duration: 400 },
      autoplay: onScroll({
        target: section,
        enter: "top top",
        leave: "bottom bottom",
        sync: true,
      }),
    });

    tl
      // ── 01 Hold ──
      .add(".tm-block-1", { opacity: [0.25, 1] }, 0)
      .add(keyFace, { translateY: [0, 10] }, 50)
      .add(stamp, { opacity: [0, 1], translateY: [8, 0] }, 350)
      // ── 02 Speak ──
      .add(".tm-block-1", { opacity: 0.25 }, 900)
      .add(".tm-block-2", { opacity: [0.25, 1] }, 900)
      .add(bars, { scaleY: [0.12, 1], delay: stagger(40) }, 950)
      .add(words, { opacity: [0, 1], translateY: [8, 0], delay: stagger(70) }, 1000)
      .add(prefix, { color: "#7c9cff" }, 1300)
      // ── 03 Release ──
      .add(".tm-block-2", { opacity: 0.25 }, 1900)
      .add(".tm-block-3", { opacity: [0.25, 1] }, 1900)
      .add(
        words,
        {
          translateX: 150,
          translateY: -70,
          scale: 0.35,
          opacity: 0,
          delay: stagger(26),
        },
        1980
      )
      .add(typed, { opacity: [0, 1] }, 2200)
      .add(drawable, { draw: "0 1", duration: 350, ease: "out(2)" }, 2300)
      .add(caption3, { opacity: [0, 1], translateY: [6, 0] }, 2450);
  });

  return (
    <section
      id="how"
      ref={rootRef as React.Ref<HTMLElement>}
      className="tm-section relative h-[300vh]"
    >
      <div className="tm-sticky sticky top-0 flex h-dvh flex-col justify-center overflow-hidden">
        <div className="mx-auto w-full max-w-6xl px-6">
          <SectionEyebrow>How it works</SectionEyebrow>
          <h2 className="mt-4 max-w-3xl font-display text-5xl leading-tight tracking-tightest md:text-6xl">
            Three movements.{" "}
            <span className="italic-display text-mello">Under a second.</span>
          </h2>

          <div className="mt-10 grid items-center gap-10 md:mt-14 md:grid-cols-[0.9fr,1.4fr]">
            {/* Numbered narration */}
            <div className="flex flex-row gap-8 md:flex-col">
              <div className="tm-block-1">
                <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello">01</span>
                <h3 className="mt-1 font-display text-3xl tracking-tightest">Hold.</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-white/60">
                  Press your push-to-talk key.
                </p>
              </div>
              <div className="tm-block-2 opacity-25">
                <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello">02</span>
                <h3 className="mt-1 font-display text-3xl tracking-tightest">Speak.</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-white/60">
                  &ldquo;Hey Claude, &hellip;&rdquo; — the routing is automatic.
                </p>
              </div>
              <div className="tm-block-3 opacity-25">
                <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello">03</span>
                <h3 className="mt-1 font-display text-3xl tracking-tightest">Release.</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-white/60">
                  Your words land — cleaned, pasted.
                </p>
              </div>
            </div>

            {/* The stage */}
            <div className="relative rounded-3xl border border-white/[0.08] bg-mello-surface/60 p-6 md:p-10">
              <div className="flex flex-col gap-8">
                {/* mini keycap + stamp */}
                <div className="flex items-center gap-5">
                  <div className="tm-key relative h-12 w-24">
                    <span className="absolute inset-x-0 bottom-0 top-2 rounded-xl bg-black/50" />
                    <span className="tm-key-face absolute inset-x-0 bottom-2 top-0 grid place-items-center rounded-xl border border-white/15 bg-mello-surface font-mono text-[10px] uppercase tracking-widest text-white/70">
                      ⌥
                    </span>
                  </div>
                  <span className="tm-stamp font-mono text-[10px] uppercase tracking-[0.2em] text-white/45 opacity-0">
                    min 200ms · shorter holds are dropped
                  </span>
                </div>

                {/* waveform + phrase */}
                <div className="flex flex-col gap-3">
                  <div className="flex h-8 items-end gap-1">
                    {[10, 22, 14, 28, 18, 12, 24, 16, 26, 11, 20, 15].map((h, i) => (
                      <span
                        key={i}
                        className="tm-bar w-1.5 origin-bottom rounded-full bg-mello"
                        style={{ height: `${h}px` }}
                      />
                    ))}
                  </div>
                  <p className="font-display text-xl tracking-tight text-white/85 md:text-2xl">
                    {PHRASE.map((w, i) => (
                      <span
                        key={i}
                        className={`tm-word mr-[0.4ch] inline-block ${i < PREFIX_LEN ? "tm-word-prefix" : ""}`}
                      >
                        {w}
                      </span>
                    ))}
                  </p>
                </div>

                {/* destination mini window */}
                <div className="tm-window relative ml-auto w-4/5 max-w-sm rounded-2xl border border-white/10 bg-black/40">
                  <div className="flex items-center gap-2 border-b border-white/[0.06] px-4 py-2.5">
                    <span className="size-2 rounded-full bg-white/15" />
                    <span className="size-2 rounded-full bg-white/15" />
                    <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-white/45">
                      claude.ai/new
                    </span>
                    <svg className="ml-auto" width="18" height="18" viewBox="0 0 18 18" fill="none">
                      <path
                        className="tm-check-path"
                        d="M4 9.5l3.5 3.5L14 5.5"
                        stroke="#7c9cff"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  </div>
                  <p className="tm-typed px-4 py-3 font-mono text-xs leading-relaxed text-white/80 opacity-0">
                    Summarize the standup.
                  </p>
                </div>
                <p className="tm-caption-3 -mt-4 ml-auto font-mono text-[10px] uppercase tracking-[0.18em] text-white/40 opacity-0">
                  pasted · clipboard restored ~600ms later
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
