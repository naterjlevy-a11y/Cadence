import { SectionEyebrow } from "./ui";

const ITEMS = [
  {
    q: "Where does my audio go?",
    a: "It's transcribed in the cloud and the raw audio is deleted the moment your text comes back — it exists for about a quarter of a second. Prefer nothing leaving your Mac at all? Switch to offline mode in Settings.",
  },
  {
    q: "Why does the demo on this page want my mic?",
    a: "The hero demo uses your browser's built-in speech recognition to transcribe you locally, right in this tab — nothing is recorded or uploaded by us. Deny it and you still get the full show, just scripted.",
  },
  {
    q: "Is it free?",
    a: "Yes — about 3 hours of talking per month, free, no credit card, no account wall. When you need more, Pro is unlimited.",
  },
  {
    q: "Why a custom font?",
    a: 'Because most AI apps look the same. Instrument Serif is the typographic equivalent of saying "this was designed by humans, on purpose, for you."',
  },
  {
    q: "Open source?",
    a: "Partially — the server pieces and this site are open on GitHub. The app itself isn't. Yet.",
  },
];

export function FAQ() {
  return (
    <section id="faq" className="mx-auto max-w-4xl px-6 py-28">
      <SectionEyebrow>Frequently asked</SectionEyebrow>
      <h2 className="mt-4 font-display text-[2.5rem] leading-[1.08] tracking-tightest md:text-[3.2rem]">
        Questions, <span className="italic-display text-mello">answered.</span>
      </h2>
      <div className="mt-12 divide-y divide-white/[0.08] border-y border-white/[0.08]">
        {ITEMS.map((item, i) => (
          <details key={i} className="group py-6">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-6">
              <span className="font-display text-2xl tracking-tightest">{item.q}</span>
              <span className="font-mono text-2xl text-white/40 transition group-open:rotate-45">+</span>
            </summary>
            <p className="mt-4 max-w-2xl leading-relaxed text-white/60">{item.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
