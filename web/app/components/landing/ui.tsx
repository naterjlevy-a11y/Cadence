/**
 * Server-safe shared UI atoms — no client APIs, no anime.js.
 */

export function Logo() {
  // The Cadence mark: a waveform pulse inside a pill — the recording
  // indicator, the porthole, the brand. One shape everywhere.
  return (
    <span className="logo-mark relative grid h-8 w-12 place-items-center rounded-full bg-mello">
      <svg width="24" height="14" viewBox="0 0 24 14" fill="none">
        <path
          d="M2 7h2m2-4v8m3-10v12m3-8v4m3-6v8m3-4v0"
          stroke="white"
          strokeWidth="1.8"
          strokeLinecap="round"
        />
      </svg>
    </span>
  );
}

export function SectionEyebrow({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.2em] text-white/55">
      <span className="h-px w-8 bg-white/30" />
      {children}
    </div>
  );
}

export function LightSectionEyebrow({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.2em] text-mello-ink/55">
      <span className="h-px w-8 bg-mello-ink/30" />
      {children}
    </div>
  );
}

export function DownloadIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path
        d="M8 1v9m0 0 3-3m-3 3L5 7M2 12v2h12v-2"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
