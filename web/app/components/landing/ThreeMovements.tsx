"use client";

import { useAnimeScope } from "./motion";
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
  // Static section by design — no pin, no scrub (scrubbing felt bad).
  const { rootRef } = useAnimeScope(() => {});
  return (
    <section
      id="how"
      ref={rootRef as React.Ref<HTMLElement>}
      className="tm-section relative py-8"
    >
      <div className="tm-sticky flex flex-col justify-center overflow-hidden py-20">
        <div className="mx-auto w-full max-w-6xl px-6">
          <SectionEyebrow>How it works</SectionEyebrow>
          <h2 className="mt-4 max-w-3xl font-display text-[2.5rem] leading-[1.08] tracking-tightest md:text-[3.2rem]">
            Three movements.{" "}
            <span className="italic-display text-mello">Under a second.</span>
          </h2>

          <div className="mt-10 grid items-center gap-10 md:mt-14 md:grid-cols-[0.9fr,1.4fr]">
            {/* Numbered narration */}
            <div className="flex flex-row gap-8 md:flex-col">
              <div className="tm-block-1">
                <span className="text-[12px] font-semibold tracking-wide text-mello">01</span>
                <h3 className="mt-1 font-display text-3xl tracking-tightest">Hold.</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-white/60">
                  Press your push-to-talk key.
                </p>
              </div>
              <div className="tm-block-2">
                <span className="text-[12px] font-semibold tracking-wide text-mello">02</span>
                <h3 className="mt-1 font-display text-3xl tracking-tightest">Speak.</h3>
                <p className="mt-1.5 max-w-xs text-sm leading-relaxed text-white/60">
                  &ldquo;Hey Claude, &hellip;&rdquo; — the routing is automatic.
                </p>
              </div>
              <div className="tm-block-3">
                <span className="text-[12px] font-semibold tracking-wide text-mello">03</span>
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
                  <span className="tm-stamp text-[11px] font-medium tracking-wide text-white/45 opacity-0">
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
                    <span className="text-[11px] font-medium tracking-wide text-white/45">
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
                  <p className="tm-typed px-4 py-3 font-mono text-xs leading-relaxed text-white/80">
                    Summarize the standup.
                  </p>
                </div>
                <p className="tm-caption-3 -mt-4 ml-auto text-[11px] font-medium tracking-wide text-white/40">
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
