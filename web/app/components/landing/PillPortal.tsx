"use client";

import { createTimeline, onScroll, utils } from "animejs";
import { reducedMotion, useAnimeScope } from "./motion";

const TRACK_BARS = 16;

/**
 * The opening. An exact replica of Cadence's menu-bar recording pill —
 * × button, dashed track, waveform button — floating in the dark. As you
 * scroll, the dashes become dancing bars (the recording "filling up"),
 * then the pill-shaped mask hole blows open and you fly through into the
 * light world. aerodynamics.nl's window, except it's our own UI.
 */
export function PillPortal() {
  const { rootRef } = useAnimeScope((scope) => {
    const root = scope.root as HTMLElement;
    const overlay = root.querySelector<HTMLElement>(".portal-overlay");
    const frame = root.querySelector<HTMLElement>(".portal-frame");
    const line = root.querySelector<HTMLElement>(".portal-line");
    const hint = root.querySelector<HTMLElement>(".portal-hint");
    const dashes = Array.from(root.querySelectorAll<HTMLElement>(".pp-dash"));
    const bars = Array.from(root.querySelectorAll<HTMLElement>(".pp-bar"));
    if (!overlay || !frame || !line) return;

    if (reducedMotion(scope)) {
      utils.set(overlay, { opacity: 0 });
      utils.set(frame, { opacity: 0 });
      bars.forEach((b) => (b.style.transform = "scaleY(1)"));
      return;
    }

    const end = 2 * Math.max(window.innerWidth, window.innerHeight);
    const hole = { w: 360, h: 138 };
    const apply = () => {
      overlay.style.setProperty("--hole-w", `${hole.w}px`);
      overlay.style.setProperty("--hole-h", `${hole.h}px`);
    };
    apply();

    const tl = createTimeline({
      defaults: { ease: "inOut(3)" },
      autoplay: onScroll({
        target: root,
        enter: "top top",
        leave: "bottom bottom",
        // 1:1 scrub — Lenis already smooths input; extra sync lag felt mushy.
        sync: true,
      }),
    });

    const intro = root.querySelector<HTMLElement>(".portal-intro");

    // The bars trickle in WHILE the pill grows and you fly into it —
    // one continuous motion, no dead phases.
    dashes.forEach((d, i) => {
      const at = 80 + (i / TRACK_BARS) * 1200;
      tl.add(d, { opacity: [1, 0], duration: 60 }, at);
      tl.add(bars[i], { scaleY: [0.12, 1], opacity: [0.35, 1], duration: 100 }, at);
    });
    if (intro) tl.add(intro, { opacity: [1, 0], translateY: [0, -24], duration: 600, ease: "out(3)" }, 120);
    tl.add(hint as HTMLElement, { opacity: [1, 0], duration: 280, ease: "out(2)" }, 180);

    // grow + burst — ease ramps gently then accelerates through the hole
    tl.add(hole, { w: end, h: end, duration: 2600, onUpdate: apply, ease: "inOut(4)" }, 420)
      .add(
        frame,
        {
          width: [360, end],
          height: [138, end],
          duration: 2600,
          ease: "inOut(4)",
        },
        420
      )
      // frame surface fades once the hole is large enough to read the light world
      .add(frame, { opacity: [1, 0], duration: 900, ease: "out(3)" }, 1100)
      // the line drifts through as you pass the threshold
      .add(
        line,
        {
          translateX: ["52%", "-68%"],
          translateY: ["4vw", "-3vw"],
          duration: 2600,
          ease: "inOut(3)",
        },
        600
      );
  });

  return (
    <section ref={rootRef as React.Ref<HTMLElement>} className="relative h-[300vh]">
      <div className="sticky top-0 h-dvh overflow-hidden">
        {/* Layer A — the light world behind the hole */}
        <div className="sky-world absolute inset-0">
          <p className="portal-line absolute top-1/2 -mt-[0.5em] whitespace-nowrap font-display text-[clamp(5.5rem,13vw,14rem)] italic-display leading-none tracking-tightest text-mello-ink">
            say it anywhere.
          </p>
        </div>

        {/* intro text — big, fades as you start scrolling */}
        <div className="portal-intro absolute inset-x-0 top-[16dvh] z-20 flex flex-col items-center gap-4 px-6 text-center">
          <h1 className="text-[clamp(2.1rem,4.6vw,3.9rem)] font-semibold leading-[1.05] tracking-[-0.035em] text-white/95">
            Hold a key. Talk to <span className="font-semibold text-mello">anything</span>.
          </h1>
          <p className="mt-1 text-[14px] font-normal text-white/45">Push-to-talk dictation for your Mac — say where your words go.</p>
        </div>

        {/* the replica recording pill you fly through — rounded-full stays a
            perfect stadium at every size (never animate borderRadius) */}
        <div
          className="portal-frame pointer-events-none absolute left-1/2 top-1/2 z-20 flex -translate-x-1/2 -translate-y-1/2 items-center gap-4 rounded-full border-2 border-white/25 bg-mello-surface px-4 shadow-[0_0_0_1px_rgba(124,156,255,0.18),0_24px_70px_rgba(0,0,0,0.6)]"
          style={{ width: 360, height: 138 }}
        >
          {/* status dot */}
          <span className="absolute left-16 top-6 size-2 rounded-full bg-mello/80" />
          {/* × button */}
          <span className="grid size-12 shrink-0 place-items-center rounded-full bg-black/40">
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
              <path d="M2.5 2.5l9 9m0-9l-9 9" stroke="white" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </span>
          {/* dashed track that fills with bars as you scroll */}
          <span className="relative flex h-10 flex-1 items-center justify-between px-1">
            {Array.from({ length: TRACK_BARS }).map((_, i) => (
              <span key={i} className="relative flex h-full w-1.5 items-center justify-center">
                <span className="pp-dash absolute h-[3px] w-full rounded-full bg-white/30" />
                <span
                  className="pp-bar absolute w-full origin-center rounded-full bg-mello opacity-0"
                  style={{ height: `${[38, 62, 46, 78, 55, 42, 70, 50, 66, 40, 74, 52, 60, 44, 68, 48][i]}%` }}
                />
              </span>
            ))}
          </span>
          {/* waveform button */}
          <span className="grid size-12 shrink-0 place-items-center rounded-full bg-mello">
            <svg width="20" height="14" viewBox="0 0 20 14" fill="none">
              <path d="M2 7v0m3-3v6m3-8v10m3-6v2m3-5v8m4-4v0" stroke="white" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
          </span>
        </div>

        {/* scroll hint */}
        <p className="portal-hint absolute bottom-10 left-1/2 z-20 -translate-x-1/2 text-[12px] font-semibold tracking-wide text-white/45">
          scroll
        </p>

        {/* Layer B — ink overlay with the pill hole */}
        <div className="portal-overlay absolute inset-0 z-10 bg-mello-ink" />
      </div>
    </section>
  );
}
