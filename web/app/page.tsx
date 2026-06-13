import Link from "next/link";

// Replace with your GitHub release URL once the first DMG is up.
const DOWNLOAD_URL = "#download";

export default function Home() {
  return (
    <main className="relative isolate min-h-dvh overflow-hidden bg-mello-ink text-white">
      {/* Subtle grain only — no gradients or halos. Pure purple-on-black. */}
      <div className="pointer-events-none absolute inset-0 -z-10 grain opacity-50" />

      <Nav />

      <Hero />

      <Marquee />

      <HowItWorks />

      <Quote />

      <FeaturesEditorial />

      <FAQ />

      <Footer />
    </main>
  );
}

// ───────────────────────────────────────────────────────────── NAV ────────

function Nav() {
  return (
    <header className="relative z-10">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
        <Link href="/" className="flex items-center gap-3 text-white">
          <Logo />
          <span className="font-display text-xl tracking-tightest">Mellotron</span>
        </Link>
        <nav className="hidden items-center gap-7 text-sm text-white/70 md:flex">
          <Link href="#how" className="hover:text-white">How it works</Link>
          <Link href="#features" className="hover:text-white">Features</Link>
          <Link href="#faq" className="hover:text-white">FAQ</Link>
          <a
            href={DOWNLOAD_URL}
            className="rounded-full border border-white/15 bg-white/[0.06] px-4 py-1.5 text-white hover:bg-white/[0.12]"
          >
            Download
          </a>
        </nav>
      </div>
      <div className="hairline mx-auto h-px max-w-6xl" />
    </header>
  );
}

// ───────────────────────────────────────────────────────── HERO ───────────

function Hero() {
  return (
    <section className="relative mx-auto max-w-6xl px-6 pt-20 pb-24 lg:pt-32">
      <p className="mb-6 inline-flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.18em] text-white/60">
        <span className="size-1.5 rounded-full bg-mello pulse-soft" />
        For macOS 14+ · v0.1 beta
      </p>

      <h1 className="font-display text-[clamp(3rem,9vw,7.5rem)] leading-[0.95] tracking-tightest">
        Hold a key. <br />
        Talk to <span className="italic-display text-mello">anything.</span>
      </h1>

      <div className="mt-12 grid gap-12 lg:grid-cols-[1.1fr,1fr]">
        <div>
          <p className="max-w-xl text-lg leading-relaxed text-white/70 md:text-xl">
            Mellotron is push-to-talk dictation for your Mac. Press a key, speak
            naturally, release — and watch your words land in Claude, ChatGPT,
            Docs, Cursor, Messages, or anywhere else you're typing.
          </p>

          <div className="mt-8 flex flex-wrap gap-3">
            <a
              href={DOWNLOAD_URL}
              className="group inline-flex items-center gap-2 rounded-2xl bg-mello px-6 py-3.5 text-base font-semibold text-mello-ink transition hover:bg-mello-glow"
            >
              <DownloadIcon /> Download for macOS
              <span className="ml-1 opacity-60 transition group-hover:translate-x-0.5">↗</span>
            </a>
            <Link
              href="#how"
              className="inline-flex items-center gap-2 rounded-2xl border border-white/15 bg-white/[0.04] px-5 py-3.5 text-base text-white/85 backdrop-blur transition hover:bg-white/[0.09]"
            >
              See how it works
            </Link>
          </div>

          <p className="mt-5 font-mono text-xs uppercase tracking-[0.16em] text-white/45">
            Free tier · 3 hours / month · No credit card
          </p>
        </div>

        {/* Pill mockup column */}
        <div className="relative hidden lg:block">
          <PillMockup />
        </div>
      </div>
    </section>
  );
}

// ───────────────────────────────────────────────────── MARQUEE ────────────

function Marquee() {
  const apps = [
    "Claude", "ChatGPT", "Cursor", "Google Docs", "Notion", "Gemini",
    "Slack", "Linear", "VS Code", "Mail", "Messages", "Discord",
  ];
  return (
    <section className="relative border-y border-white/[0.06] bg-white/[0.015] py-8">
      <p className="mx-auto mb-5 max-w-6xl px-6 font-mono text-[10px] uppercase tracking-[0.22em] text-white/45">
        Works in every app · Tested across
      </p>
      <div className="no-scrollbar overflow-hidden">
        <div className="flex animate-[scroll_30s_linear_infinite] gap-12 whitespace-nowrap px-6 font-display text-3xl text-white/40">
          {[...apps, ...apps].map((app, i) => (
            <span key={i} className="flex items-center gap-12">
              {app}
              <span className="size-1 rounded-full bg-white/20" />
            </span>
          ))}
        </div>
      </div>
      <style>{`
        @keyframes scroll {
          from { transform: translateX(0); }
          to   { transform: translateX(-50%); }
        }
      `}</style>
    </section>
  );
}

// ─────────────────────────────────────────────────── HOW IT WORKS ─────────

function HowItWorks() {
  return (
    <section id="how" className="mx-auto max-w-6xl px-6 py-28">
      <SectionEyebrow>How it works</SectionEyebrow>
      <h2 className="mt-4 max-w-3xl font-display text-5xl leading-tight tracking-tightest md:text-6xl">
        Three movements.{" "}
        <span className="italic-display text-mello">Under a second.</span>
      </h2>

      <div className="mt-16 grid gap-px overflow-hidden rounded-3xl border border-white/8 bg-white/[0.04] md:grid-cols-3">
        <Step
          n="01"
          title="Hold"
          body="Press your push-to-talk key. The default is Right Option — change it to anything you like."
          kbd="⌥"
        />
        <Step
          n="02"
          title="Speak"
          body={`"Hey Claude, summarize the meeting" — or just dictate. Mellotron picks up the routing prefix automatically.`}
          waveform
        />
        <Step
          n="03"
          title="Release"
          body="Your text appears in the right app, polished by AI: lists formatted, brands capitalized, filler removed."
          kbd="✓"
        />
      </div>
    </section>
  );
}

function Step({
  n,
  title,
  body,
  kbd,
  waveform,
}: {
  n: string;
  title: string;
  body: string;
  kbd?: string;
  waveform?: boolean;
}) {
  return (
    <div className="relative bg-mello-ink p-10">
      <div className="flex items-center justify-between">
        <span className="font-mono text-xs uppercase tracking-[0.18em] text-mello">{n}</span>
        {kbd && (
          <kbd className="rounded-lg border border-white/15 bg-white/5 px-3 py-1 font-mono text-sm">{kbd}</kbd>
        )}
        {waveform && (
          <div className="flex items-end gap-1">
            {[6, 14, 9, 18, 11, 7].map((h, i) => (
              <span
                key={i}
                className="w-1 rounded-full bg-mello"
                style={{ height: `${h}px`, opacity: 0.35 + (i % 3) * 0.2 }}
              />
            ))}
          </div>
        )}
      </div>
      <h3 className="mt-8 font-display text-4xl tracking-tightest">{title}.</h3>
      <p className="mt-3 leading-relaxed text-white/65">{body}</p>
    </div>
  );
}

// ──────────────────────────────────────────────────────── QUOTE ───────────

function Quote() {
  return (
    <section className="relative mx-auto max-w-5xl px-6 py-32 text-center">
      <p className="font-display text-3xl leading-snug tracking-tight md:text-5xl">
        Speak like you think. <br />
        <span className="italic-display text-mello">We&apos;ll handle the typing.</span>
      </p>
      <div className="hairline mx-auto mt-12 h-px w-32" />
    </section>
  );
}

// ───────────────────────────────────────────────────── FEATURES ───────────

function FeaturesEditorial() {
  return (
    <section id="features" className="mx-auto max-w-6xl px-6 py-28">
      <SectionEyebrow>What's inside</SectionEyebrow>
      <h2 className="mt-4 max-w-3xl font-display text-5xl leading-tight tracking-tightest md:text-6xl">
        Built for the way <span className="italic-display text-mello">you actually work.</span>
      </h2>

      <div className="mt-16 grid gap-px overflow-hidden rounded-3xl border border-white/8 bg-white/[0.04] md:grid-cols-2">
        <Feature
          title="Groq Whisper"
          body="Whisper-large-v3 on Groq's LPU. Typical 5-second clip back in ~250ms. Plus a fallback to Apple Speech when the network drops."
          stat="~250ms"
          statLabel="round-trip"
        />
        <Feature
          title="Smart routing"
          body={`Say "Hey Claude…", "Open Docs…", "Reply in Messages…" — Mellotron focuses the right window, opens new tabs as needed, and submits.`}
          stat="40+"
          statLabel="destinations"
        />
        <Feature
          title="AI polish"
          body="Optional GPT-4o-mini pass that cleans filler words, fixes lists, and capitalizes brand names. Or turn it off — fully rules-based works too."
          stat="Optional"
          statLabel="LLM cleanup"
        />
        <Feature
          title="Brand dictionary"
          body="McGill, Anthropic, OpenAI, Formula Electric, GitHub — proper nouns recognized correctly, every time. Add your own in Settings."
          stat="500+"
          statLabel="brands shipped"
        />
        <Feature
          title="Native macOS"
          body="LSUIElement menu bar app. Signed, notarized, Sparkle auto-updates. ~12 MB download. Plays nice with macOS Accessibility."
          stat="~12MB"
          statLabel="download"
        />
        <Feature
          title="Bring your own key"
          body="Drop your own Groq or OpenRouter key in Settings — zero quota, zero cloud. Keys live in macOS Keychain."
          stat="BYOK"
          statLabel="supported"
        />
      </div>
    </section>
  );
}

function Feature({
  title,
  body,
  stat,
  statLabel,
}: {
  title: string;
  body: string;
  stat: string;
  statLabel: string;
}) {
  return (
    <div className="group bg-mello-ink p-10">
      <div className="flex items-baseline justify-between gap-6">
        <h3 className="font-display text-3xl tracking-tightest">{title}.</h3>
        <div className="text-right">
          <div className="font-display text-2xl text-mello">{stat}</div>
          <div className="font-mono text-[10px] uppercase tracking-[0.18em] text-white/45">{statLabel}</div>
        </div>
      </div>
      <p className="mt-4 max-w-md leading-relaxed text-white/65">{body}</p>
    </div>
  );
}

// ─────────────────────────────────────────────────────── FAQ ──────────────

function FAQ() {
  const items = [
    {
      q: "Where does my audio go?",
      a: "By default, to Mellotron Cloud (a Cloudflare Worker that proxies Groq Whisper). You can switch to BYOK with your own Groq key, or go fully on-device with Apple Speech.",
    },
    {
      q: "Is it free?",
      a: "Yes — about 3 hours of cloud transcription per month, no credit card. Beyond that you can bring your own Groq key (free tier with Groq is generous) or upgrade later.",
    },
    {
      q: "Why a custom font?",
      a: "Because most AI apps look the same. Instrument Serif is the typographic equivalent of saying \"this was designed by humans, on purpose, for you.\"",
    },
    {
      q: "Open source?",
      a: "Partially. The cloud worker, landing page, and Supabase schema are open. The app itself isn't — yet.",
    },
  ];
  return (
    <section id="faq" className="mx-auto max-w-4xl px-6 py-28">
      <SectionEyebrow>Frequently asked</SectionEyebrow>
      <h2 className="mt-4 font-display text-5xl tracking-tightest">
        Questions, <span className="italic-display text-mello">answered.</span>
      </h2>
      <div className="mt-12 divide-y divide-white/[0.08] border-y border-white/[0.08]">
        {items.map((item, i) => (
          <details key={i} className="group py-6">
            <summary className="flex cursor-pointer items-center justify-between gap-6 list-none">
              <span className="font-display text-2xl tracking-tightest">{item.q}</span>
              <span className="font-mono text-2xl text-white/40 transition group-open:rotate-45">+</span>
            </summary>
            <p className="mt-4 max-w-2xl leading-relaxed text-white/65">{item.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

// ─────────────────────────────────────────────────────── FOOTER ───────────

function Footer() {
  return (
    <footer className="border-t border-white/5">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-8 px-6 py-14 md:flex-row md:items-end">
        <div>
          <div className="flex items-center gap-3">
            <Logo />
            <span className="font-display text-2xl tracking-tightest">Mellotron</span>
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
      <div className="mx-auto max-w-6xl border-t border-white/5 px-6 py-6 font-mono text-[10px] uppercase tracking-[0.2em] text-white/35">
        © {new Date().getFullYear()} Mellotron · Made for macOS · v0.1 beta
      </div>
    </footer>
  );
}

// ──────────────────────────────────────────────────── COMPONENTS ──────────

function SectionEyebrow({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.22em] text-white/55">
      <span className="h-px w-8 bg-white/30" />
      {children}
    </div>
  );
}

function PillMockup() {
  return (
    <div className="relative h-full min-h-[280px]">
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
        <div className="relative">
          {/* The pill — no glow, no halo, just the brand surface on black. */}
          <div className="relative flex items-center gap-2 rounded-full border border-mello/30 bg-mello-surface px-3 py-2">
            <span className="grid size-5 place-items-center rounded-full bg-white/15">
              <svg width="9" height="9" viewBox="0 0 9 9" fill="none">
                <path d="M2 2l5 5M7 2L2 7" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
            </span>
            <div className="flex items-end gap-1 px-2">
              {[12, 22, 16, 28, 18, 14, 24, 10].map((h, i) => (
                <span
                  key={i}
                  className="w-1 rounded-full bg-mello"
                  style={{ height: `${h}px`, opacity: 0.6 + (i % 3) * 0.15 }}
                />
              ))}
            </div>
            <span className="grid size-5 place-items-center rounded-full bg-mello">
              <svg width="9" height="9" viewBox="0 0 9 9" fill="none">
                <path d="M1 5h2m1-3v6m1-4v2m1-3v4m1-5v6m1-4v2m1-3v4" stroke="white" strokeWidth="1.2" strokeLinecap="round" />
              </svg>
            </span>
          </div>

          {/* Caption */}
          <p className="mt-6 text-center font-mono text-[10px] uppercase tracking-[0.2em] text-white/45">
            The recording indicator
          </p>
        </div>
      </div>
    </div>
  );
}

function Logo() {
  // Solid flat purple square with the wordless Mellotron mark inside.
  // No gradients, no glow — matches the in-app mark exactly.
  return (
    <span className="relative grid size-9 place-items-center rounded-xl bg-mello">
      <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
        <path
          d="M3 14V4l3 4 3-5 3 5 3-4v10"
          stroke="white"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

function DownloadIcon() {
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
