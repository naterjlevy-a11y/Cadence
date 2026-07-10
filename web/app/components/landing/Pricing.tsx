import { DOWNLOAD_URL } from "./copy";
import { DownloadIcon } from "./ui";

export function Pricing() {
  return (
    <section className="border-y border-white/[0.06] bg-white/[0.015]">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-8 px-6 py-20 md:flex-row md:items-center">
        <p className="max-w-2xl font-display text-3xl leading-snug tracking-tight md:text-4xl">
          Free — about <span className="italic-display text-mello">3 hours of talking</span> a
          month. No credit card. Pro (unlimited) coming.
        </p>
        <a
          href={DOWNLOAD_URL}
          className="group inline-flex shrink-0 items-center gap-2 rounded-xl bg-mello-coral px-6 py-3 text-[15px] font-semibold text-mello-ink transition hover:brightness-110"
        >
          <DownloadIcon /> Download
          <span className="ml-1 opacity-60 transition group-hover:translate-x-0.5">↗</span>
        </a>
      </div>
    </section>
  );
}
