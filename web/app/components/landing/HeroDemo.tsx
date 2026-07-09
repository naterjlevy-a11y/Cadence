"use client";

import Link from "next/link";
import { animate } from "animejs";
import { useEffect, useRef, useState } from "react";
import { DESTINATIONS, DOWNLOAD_URL, type DestinationId } from "./copy";
import { DestinationRail } from "./DestinationRail";
import { DownloadIcon } from "./ui";
import { Keycap } from "./Keycap";
import { KineticTitle } from "./KineticTitle";
import { Magnetic } from "./Magnetic";
import { ParticleField } from "./ParticleField";
import { getSprings } from "./motion";
import { TranscriptLine, flyWords } from "./TranscriptLine";
import { Waveform } from "./Waveform";
import { useHoldToTalk } from "./useHoldToTalk";

const STATUS: Record<string, string> = {
  requesting: "allow the mic — it never leaves this tab",
  listening: "listening…",
  "sim-listening": "listening… (scripted, but you get the idea)",
  routing: "+120ms tail — so your last syllable makes it",
  "sim-routing": "+120ms tail — so your last syllable makes it",
  settle: "routed. clipboard restored 600ms later.",
};

export function HeroDemo() {
  const demo = useHoldToTalk();
  const sectionRef = useRef<HTMLElement>(null);
  const [received, setReceived] = useState<{ id: DestinationId; text: string } | null>(null);
  const routedSeq = useRef(0);

  // Hero visibility gates the spacebar + attract loop.
  useEffect(() => {
    const el = sectionRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => demo.setVisible(e.isIntersecting && e.intersectionRatio >= 0.5),
      { threshold: [0, 0.5, 1] }
    );
    io.observe(el);
    return () => io.disconnect();
  }, [demo]);

  // The routing choreography: fly words → tile gulps → text lands.
  useEffect(() => {
    const req = demo.routeRequest;
    if (!req || req.seq === routedSeq.current) return;
    routedSeq.current = req.seq;

    const section = sectionRef.current;
    if (!section) return;
    const tile = section.querySelector<HTMLElement>(`[data-dest-id="${req.targetId}"]`);
    const wordEls = Array.from(section.querySelectorAll<HTMLElement>("[data-word]"));
    if (!tile) {
      demo.completeRouting();
      return;
    }
    tile.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" });

    flyWords(wordEls, tile, {
      onComplete: () => {
        animate(tile, {
          scale: [1, 1.12, 1],
          duration: 600,
          ease: getSprings().gulp,
        });
        setReceived({ id: req.targetId, text: req.cleaned });
        demo.completeRouting();
      },
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [demo.routeRequest]);

  // Clear the landed text when a new take begins.
  useEffect(() => {
    if (
      demo.state === "listening" ||
      demo.state === "sim-listening" ||
      demo.state === "requesting"
    ) {
      setReceived(null);
    }
  }, [demo.state]);

  const targetName =
    demo.state === "settle" && received
      ? DESTINATIONS.find((d) => d.id === received.id)?.name ?? null
      : null;

  const status = STATUS[demo.state];

  return (
    <section
      id="hero"
      ref={sectionRef}
      className="sky-world relative flex min-h-[96dvh] flex-col items-center gap-9 overflow-hidden px-6 pb-16 pt-20"
    >
      {/* the living waveform ridge — reacts to cursor, and to your voice */}
      <ParticleField active={demo.listening} getLevel={demo.micLevelGetter} />

      <p className="relative inline-flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/55">
        <span className="size-1.5 rounded-full bg-mello pulse-soft" />
        For macOS 14+ · Early access
      </p>

      <div className="relative">
        <KineticTitle overrideWord={targetName ? `${targetName}.` : null} />
      </div>

      <p className="relative max-w-xl text-center text-lg leading-relaxed text-mello-ink/60">
        Push-to-talk dictation for your Mac.
      </p>

      <div className="relative flex flex-col items-center gap-6">
        <Keycap
          pressed={demo.pressed}
          onPressStart={() => void demo.pressStart()}
          onPressEnd={demo.pressEnd}
        />

        <div className="flex h-6 items-center justify-center">
          {demo.toast ? (
            <p className="font-mono text-xs text-mello-deep">{demo.toast}</p>
          ) : status ? (
            <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/55">
              {status}
            </p>
          ) : (
            <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/50">
              hold <kbd className="rounded border border-mello-ink/20 bg-white/60 px-1">space</kbd> · or click the key ·{" "}
              <button type="button" onClick={demo.runSimulation} className="underline decoration-mello-ink/30 underline-offset-2 hover:text-mello-ink">watch it instead →</button>
            </p>
          )}
        </div>

        <Waveform active={demo.listening} getLevel={demo.micLevelGetter} />

        <TranscriptLine
          words={demo.words}
          placeholder={
            demo.capability === "fallback"
              ? "live transcription needs Chrome — but you get the idea"
              : "your words appear here"
          }
        />
      </div>

      <div className="relative w-full max-w-4xl">
        <DestinationRail
          litId={demo.litId}
          receivedId={received?.id ?? null}
          receivedText={received?.text ?? ""}
        />
      </div>

      <div className="relative flex flex-wrap items-center justify-center gap-3">
        <Magnetic>
          <a
            href={DOWNLOAD_URL}
            className="group inline-flex items-center gap-2 rounded-2xl bg-mello px-6 py-3.5 text-base font-semibold text-mello-ink transition hover:bg-mello-glow"
          >
            <DownloadIcon /> Download for macOS
            <span className="ml-1 opacity-60 transition group-hover:translate-x-0.5">↗</span>
          </a>
        </Magnetic>
        <Magnetic>
          <Link
            href="#how"
            className="inline-flex items-center gap-2 rounded-2xl border border-mello-ink/15 bg-white/50 px-5 py-3.5 text-base text-mello-ink/85 backdrop-blur transition hover:bg-white/80"
          >
            See how it works
          </Link>
        </Magnetic>
      </div>
      <p className="relative -mt-4 font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/50">
        Free tier · 3 hours / month · No credit card
      </p>
    </section>
  );
}
