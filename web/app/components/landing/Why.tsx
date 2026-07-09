import { LightSectionEyebrow } from "./ui";

/**
 * The manifesto — the one section that sounds like a person, not a product.
 * Editorial: no cards, no grid, just type.
 */
export function Why() {
  return (
    <section className="sky-world border-y border-mello-ink/[0.06]">
      <div className="mx-auto max-w-4xl px-6 py-32">
        <LightSectionEyebrow>Why this exists</LightSectionEyebrow>
        <p className="mt-8 font-display text-3xl leading-snug tracking-tight md:text-[2.6rem] md:leading-[1.25]">
          You think at <span className="italic-display text-mello-deep">150 words a minute</span> and
          type at 40. Every idea you have pays that tax — in every app, all day,
          forever. Cadence exists to delete it: hold a key, say the thing,
          and it&apos;s already where it needs to be.
        </p>
      </div>
    </section>
  );
}
