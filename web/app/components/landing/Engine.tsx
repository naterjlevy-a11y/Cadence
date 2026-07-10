"use client";

import { animate, onScroll, stagger, utils } from "animejs";
import { reducedMotion, useAnimeScope } from "./motion";
import { SectionEyebrow } from "./ui";

/**
 * Benefit-led, editorial — hairline columns, no cards. The ~250ms stat
 * counts up on scroll; a thin cascade line lights through the columns.
 */
export function Engine() {
  const { rootRef } = useAnimeScope((scope) => {
    const root = scope.root as HTMLElement;
    const counter = root.querySelector<HTMLElement>(".engine-count");
    const cascades = Array.from(root.querySelectorAll<HTMLElement>(".engine-cascade"));

    if (reducedMotion(scope)) {
      if (counter) counter.textContent = "250";
      return;
    }

    if (counter) {
      const obj = { v: 0 };
      animate(obj, {
        v: 250,
        duration: 1400,
        ease: "out(4)",
        onUpdate: () => {
          counter.textContent = String(Math.round(obj.v));
        },
        autoplay: onScroll({ target: root, enter: "bottom-=140 top" }),
      });
    }

    if (cascades.length) {
      utils.set(cascades, { scaleX: 0 });
      animate(cascades, {
        scaleX: [0, 1],
        duration: 600,
        ease: "inOut(2)",
        delay: stagger(350),
        autoplay: onScroll({ target: root, enter: "bottom-=140 top" }),
      });
    }
  });

  return (
    <section ref={rootRef as React.Ref<HTMLElement>} className="mx-auto max-w-6xl px-6 py-28">
      <SectionEyebrow>Under the hood</SectionEyebrow>
      <h2 className="mt-4 max-w-3xl font-display text-[2.5rem] leading-[1.08] tracking-tightest md:text-[3.2rem]">
        Fast by default. <span className="italic-display text-mello">Never stranded.</span>
      </h2>

      <div className="mt-16 grid gap-12 md:grid-cols-3 md:gap-8">
        <div className="relative pt-6">
          <span className="engine-cascade absolute inset-x-0 top-0 h-px origin-left bg-mello" />
          <div className="font-display text-5xl text-mello">
            ~<span className="engine-count">0</span>ms
          </div>
          <h3 className="mt-5 font-display text-2xl tracking-tightest">Fast.</h3>
          <p className="mt-2 leading-relaxed text-white/60">
            Speak, release, done. Your words come back in about a quarter of a
            second — before your hands find the keyboard.
          </p>
        </div>
        <div className="relative pt-6 md:mt-10">
          <span className="engine-cascade absolute inset-x-0 top-0 h-px origin-left bg-mello/60" />
          <div className="font-display text-5xl text-white/85">Offline</div>
          <h3 className="mt-5 font-display text-2xl tracking-tightest">No signal, no problem.</h3>
          <p className="mt-2 leading-relaxed text-white/60">
            On-device transcription takes over automatically when the network
            drops. Prefer it always on? One toggle.
          </p>
        </div>
        <div className="relative pt-6 md:mt-20">
          <span className="engine-cascade absolute inset-x-0 top-0 h-px origin-left bg-mello/30" />
          <div className="font-display text-5xl text-white/85">Private</div>
          <h3 className="mt-5 font-display text-2xl tracking-tightest">Deleted on arrival.</h3>
          <p className="mt-2 leading-relaxed text-white/60">
            Raw audio is erased the instant it becomes text. Dictation history
            is off unless you turn it on.
          </p>
        </div>
      </div>

      <p className="mt-10 text-[12px] font-semibold tracking-wide text-white/50">
        auto mode: fast when connected · on-device when not
      </p>
    </section>
  );
}
