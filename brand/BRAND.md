# Cadence — Brand Spec

One-line: **Cadence — push-to-talk dictation for your Mac. Hold a key. Talk to anything.**
Personality: crisp, precise, cold-air clean. A precision instrument, not a toy. Never cheesy, never "AI-gradient" purple-teal slop.

## Logo

The mark is the **recording pill**: a glacier stadium (fully-rounded rect) containing a white waveform pulse. It's literally the app's menu-bar recording indicator — the product is the logo.

Files in this folder:
- `cadence-mark.svg` — the pill mark alone (use on dark or light)
- `cadence-wordmark.svg` — pill + "Cadence" in Instrument Serif
- `cadence-logo-square.svg` / `cadence-logo-1024.png` — app-icon lockup (dark rounded square + pill)
- `cadence-mark-480.png` — transparent PNG of the mark

Rules: never stretch the pill (always fully-rounded ends), never recolor the waveform (white only), never add gradients to the pill (flat #7c9cff), min clear space = half the pill height.

## Color — "Ink + Glacier Blue"

| Token | Hex | Usage |
|---|---|---|
| Ink | `#0b0d12` | app windows, dark sections, text on light |
| Surface | `#141821` | pills, cards, popovers on ink |
| Midnight | `#12161f` | lifted cards on ink |
| **Glacier** | `#7c9cff` | THE accent — buttons, highlights, waveforms, links |
| Glacier deep | `#5c7ce0` | pressed states, accents on light backgrounds |
| Glacier glow | `#b7c6ff` | hover tints, subtle fills |
| Ice | `#dbe4ff` | light-world gradient start |
| Cream white | `#f7f9ff` | light-world base, text on ink |
| Amber | `#ffb454` | RARE spark — one CTA max per screen. Never decorative. |

Light world gradient (landing): `#dbe4ff → #eef2ff → #f7f9ff` top-to-bottom.
Rule: one accent per surface. Glacier does 95% of the work; amber is the single exception moment.

## Typography

| Role | Font | Where |
|---|---|---|
| Display / headlines | **Instrument Serif** (Regular + Italic) | landing headlines, app display text, wordmark. Italic = the emphasis voice ("anything.") |
| Body | Inter (web) / SF Pro system (app) | paragraphs, UI labels |
| Mono / codes / stats | IBM Plex Mono (web) / SF Mono (app) | "Enter your code", kbd hints, stats, eyebrows |

Display rules: tight tracking (-0.04em), huge sizes, mix roman + italic in one line for emphasis. Mono is uppercase + wide tracking (0.2em) for eyebrows/labels — this is the "instrument panel" voice. Codes/OTP inputs: mono, large, generous letter-spacing, glacier caret.

## Motion (for any implementation)

Springs, not ease-in-out: snappy (stiffness 320, damping 22) for UI feedback; a "gulp" scale pulse (1 → 1.12 → 1) when something receives content. Waveform bars are the recurring motif — they should react to real input (voice, scroll) wherever possible. Transform/opacity only.

## Voice / copy

Short. Benefit-led. Never mention infrastructure (no "Groq", "API", "worker"). Real numbers as charm: ~250ms, 120ms tail, 3 hours free. Jokes come from honesty ("we answer to claudia"). No exclamation marks.
