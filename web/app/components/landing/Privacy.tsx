"use client";

import { createTimeline, onScroll, stagger } from "animejs";
import { reducedMotion, useAnimeScope } from "./motion";
import { SectionEyebrow } from "./ui";

const STATIONS = [
  { label: "key down", sub: "audio captured — only while held" },
  { label: "key up", sub: "transcribed in ~250ms" },
  { label: "raw audio deleted", sub: "it simply stops existing" },
  { label: "text pasted", sub: "clipboard restored ~600ms later" },
];

/**
 * "The life of your audio" — a blob travels the timeline as you scroll
 * through the section. At station three it bursts into particles (the
 * audio being deleted); a smaller text-dot carries on to the paste.
 */
export function Privacy() {
  const { rootRef } = useAnimeScope((scope) => {
    if (reducedMotion(scope)) return;
    const root = scope.root as HTMLElement;
    const track = root.querySelector<HTMLElement>(".pv-track");
    const blob = root.querySelector<HTMLElement>(".pv-blob");
    const dot = root.querySelector<HTMLElement>(".pv-dot");
    const particles = Array.from(root.querySelectorAll<HTMLElement>(".pv-particle"));
    const stations = Array.from(root.querySelectorAll<HTMLElement>(".pv-station"));
    if (!track || !blob || !dot) return;

    const w = () => track.getBoundingClientRect().width;

    const tl = createTimeline({
      defaults: { ease: "inOut(2)" },
      autoplay: onScroll({
        target: root,
        enter: "center bottom",
        leave: "center top",
        sync: true,
      }),
    });

    tl
      .add(blob, { translateX: [0, () => w() * 0.33], duration: 800 }, 0)
      .add(stations[0], { opacity: [0.3, 1], duration: 200 }, 0)
      .add(stations[1], { opacity: [0.3, 1], duration: 200 }, 700)
      .add(blob, { translateX: () => w() * 0.66, duration: 800 }, 900)
      .add(stations[2], { opacity: [0.3, 1], duration: 200 }, 1600)
      // the burst: audio ceases to exist
      .add(blob, { scale: [1, 1.5], opacity: [1, 0], duration: 220, ease: "out(2)" }, 1750)
      .add(
        particles,
        {
          translateX: () => (Math.random() - 0.5) * 90,
          translateY: () => (Math.random() - 0.5) * 70,
          opacity: [1, 0],
          scale: [1, 0.3],
          duration: 480,
          delay: stagger(14),
          ease: "out(3)",
        },
        1760
      )
      .add(dot, { opacity: [0, 1], duration: 180 }, 1950)
      .add(dot, { translateX: [() => w() * 0.66, () => w()], duration: 700 }, 2000)
      .add(stations[3], { opacity: [0.3, 1], duration: 200 }, 2550);
  });

  return (
    <section ref={rootRef as React.Ref<HTMLElement>} className="mx-auto max-w-6xl px-6 py-32">
      <SectionEyebrow>Privacy</SectionEyebrow>
      <h2 className="mt-4 max-w-3xl font-display text-[2.5rem] leading-[1.08] tracking-tightest md:text-[3.2rem]">
        Your audio has a lifespan of{" "}
        <span className="italic-display text-mello">one held key.</span>
      </h2>

      <div className="mt-20">
        <div className="pv-track relative h-px w-full bg-white/10">
          {/* the audio blob */}
          <span className="pv-blob absolute -top-2 left-0 block size-4 rounded-full bg-mello" />
          {/* burst particles, positioned where the blob dies */}
          <span className="absolute -top-2 left-[66%] block">
            {Array.from({ length: 10 }).map((_, i) => (
              <span
                key={i}
                className="pv-particle absolute left-0 top-0 block size-1.5 rounded-full bg-mello opacity-0"
              />
            ))}
          </span>
          {/* the text dot that survives */}
          <span className="pv-dot absolute -top-1 left-0 block size-2 rounded-full bg-white/80 opacity-0" />
        </div>

        <div className="mt-8 grid grid-cols-2 gap-6 md:grid-cols-4">
          {STATIONS.map((s, i) => (
            <div key={i} className="pv-station opacity-30">
              <p className="text-[12px] font-semibold tracking-wide text-mello">
                {String(i + 1).padStart(2, "0")}
              </p>
              <h3 className="mt-1 font-display text-xl tracking-tightest">{s.label}</h3>
              <p className="mt-1 text-sm text-white/60">{s.sub}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-16 grid gap-4 text-sm text-white/60 md:grid-cols-3">
        <p data-reveal>Dictation history is <span className="text-white/85">off by default</span> — when on, it stores cleaned text only, never audio.</p>
        <p data-reveal>Prefer on-device? Offline mode never touches the network at all.</p>
        <p data-reveal>No account wall — guest mode works the moment you install.</p>
      </div>
    </section>
  );
}
