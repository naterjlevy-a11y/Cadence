/**
 * Real app logos — the things Cadence routes to. Static, no motion.
 * Logos served from simpleicons (brand-accurate marks); names as fallback.
 */
const APPS: { name: string; slug?: string; color?: string; src?: string }[] = [
  { name: "Claude", slug: "claude", color: "D97757" },
  { name: "ChatGPT", src: "https://upload.wikimedia.org/wikipedia/commons/0/04/ChatGPT_logo.svg" },
  { name: "Gemini", slug: "googlegemini", color: "8E75B2" },
  { name: "Google Docs", slug: "googledocs", color: "4285F4" },
  { name: "Gmail", slug: "gmail", color: "EA4335" },
  { name: "Slack", src: "https://upload.wikimedia.org/wikipedia/commons/d/d5/Slack_icon_2019.svg" },
  { name: "Perplexity", slug: "perplexity", color: "1FB8CD" },
  { name: "Notion", slug: "notion", color: "1a1a1a" },
  { name: "Apple Notes", slug: "apple", color: "1a1a1a" },
];

export function WorksWith() {
  return (
    <section className="sky-world border-t border-mello-ink/[0.06] px-6 py-20">
      <div className="mx-auto max-w-5xl">
        <p className="text-center text-[12px] font-semibold tracking-wide text-mello-ink/50">
          Works with everything you already use
        </p>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-x-12 gap-y-8">
          {APPS.map((app) => (
            <div key={app.name} className="flex items-center gap-2.5 opacity-80 transition hover:opacity-100">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={app.src ?? `https://cdn.simpleicons.org/${app.slug}/${app.color}`}
                alt={app.name}
                width={22}
                height={22}
                loading="lazy"
              />
              <span className="text-[14px] font-medium text-mello-ink/75">{app.name}</span>
            </div>
          ))}
        </div>
        <p className="mt-10 text-center text-[13px] text-mello-ink/45">
          …and any app or website you name. Say &ldquo;Hey&rdquo; + its name, and your words go there.
        </p>
      </div>
    </section>
  );
}
