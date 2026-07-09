"use client";

import Link from "next/link";
import { createDraggable } from "animejs";
import { Logo } from "./ui";
import { DOWNLOAD_URL } from "./copy";
import { getSprings, useAnimeScope, reducedMotion } from "./motion";

export function Footer() {
  // Easter egg: the logo is draggable — flick it and it springs home.
  const { rootRef } = useAnimeScope((scope) => {
    if (reducedMotion(scope)) return;
    const el = scope.root.querySelector(".logo-drag");
    const bounds = scope.root.querySelector(".logo-bounds");
    if (!el || !bounds) return;
    createDraggable(el, {
      container: bounds as HTMLElement,
      releaseEase: getSprings().snappy,
      onSettle: (d) => d.reset(),
    });
  });

  return (
    <footer ref={rootRef as React.Ref<HTMLElement>} className="border-t border-white/5">
      <div className="logo-bounds mx-auto flex max-w-6xl flex-col items-start justify-between gap-8 px-6 py-14 md:flex-row md:items-end">
        <div>
          <div className="flex items-center gap-3">
            <span className="logo-drag inline-block cursor-grab active:cursor-grabbing" title="go on, flick it">
              <Logo />
            </span>
            <span className="font-display text-2xl tracking-tightest">Cadence</span>
          </div>
          <p className="mt-3 max-w-sm font-display text-lg italic-display text-white/55">
            Push-to-talk dictation for the kind of people who notice their fonts.
          </p>
        </div>
        <div className="flex flex-col gap-3 text-sm text-white/55">
          <a href="mailto:support@mellotron.me" className="hover:text-white">support@mellotron.me</a>
          <Link href="#faq" className="hover:text-white">FAQ</Link>
          <Link href={DOWNLOAD_URL} className="hover:text-white">Download</Link>
        </div>
      </div>
      <div className="mx-auto max-w-6xl border-t border-white/5 px-6 py-6 font-mono text-[11px] uppercase tracking-[0.2em] text-white/40">
        © {new Date().getFullYear()} Cadence · Made in Vancouver, for macOS 14+
      </div>
    </footer>
  );
}
