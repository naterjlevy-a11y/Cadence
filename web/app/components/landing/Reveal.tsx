"use client";

import { animate, stagger, utils } from "animejs";
import { onScroll } from "animejs";
import { reducedMotion, useAnimeScope } from "./motion";

/**
 * Generic scroll-reveal wrapper: children marked with [data-reveal] fade+rise
 * in with a stagger when the section enters the viewport.
 */
export function Reveal({
  children,
  className = "",
  id,
}: {
  children: React.ReactNode;
  className?: string;
  id?: string;
}) {
  const { rootRef } = useAnimeScope((scope) => {
    const els = Array.from(scope.root.querySelectorAll<HTMLElement>("[data-reveal]"));
    if (els.length === 0) return;
    if (reducedMotion(scope)) return;

    utils.set(els, { opacity: 0, translateY: 24 });
    animate(els, {
      opacity: [0, 1],
      translateY: [24, 0],
      duration: 750,
      ease: "out(3)",
      delay: stagger(70),
      autoplay: onScroll({
        target: scope.root as HTMLElement,
        enter: "bottom-=120 top",
      }),
    });
  });

  return (
    <section id={id} ref={rootRef as React.Ref<HTMLElement>} className={className}>
      {children}
    </section>
  );
}
