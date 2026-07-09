"use client";

import { DESTINATIONS, type DestinationId } from "./copy";

/**
 * The 10 real destination tiles in a horizontal rail. Tiles light up live
 * while the visitor is still talking (litId), and the routing target shows
 * the cleaned text typed into a mini window (receivedText).
 * Tile DOM nodes carry data-dest-id so HeroDemo can target them for the
 * fly animation and gulp pulse.
 */
export function DestinationRail({
  litId,
  receivedId,
  receivedText,
}: {
  litId: DestinationId | null;
  receivedId: DestinationId | null;
  receivedText: string;
}) {
  return (
    <div className="no-scrollbar -mx-6 overflow-x-auto px-6">
      <div className="flex w-max gap-2.5 pb-2">
        {DESTINATIONS.map((d) => {
          const lit = litId === d.id;
          const received = receivedId === d.id && receivedText.length > 0;
          const isHere = d.id === "here";
          return (
            <div
              key={d.id}
              data-dest-id={d.id}
              className={`dest-tile relative flex w-[9.5rem] shrink-0 flex-col gap-1 rounded-2xl border p-3.5 transition-colors duration-200 ${
                lit
                  ? "tile-lit border-mello-deep/70 bg-mello/[0.14]"
                  : "border-mello-ink/10 bg-white/60"
              }`}
            >
              <span className={`font-display text-lg tracking-tightest ${lit ? "text-mello-deep" : "text-mello-ink/85"}`}>
                {d.name}
              </span>
              {received ? (
                <span
                  className={`mt-0.5 line-clamp-2 rounded-md px-1.5 py-1 font-mono text-[10px] leading-relaxed text-mello-ink/85 ${
                    isHere ? "here-field" : "bg-white/80"
                  }`}
                >
                  {receivedText}
                </span>
              ) : isHere ? (
                <span className="here-field mt-0.5 rounded-md px-1.5 py-1 font-mono text-[10px] text-mello-ink/40">
                  <span className="here-caret" />
                  {d.hint}
                </span>
              ) : (
                <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/45">
                  {d.hint}
                </span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
