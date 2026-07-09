/**
 * Single source of truth for destinations, fuzzy aliases, and the scripted
 * demo takes. Mirrors Mellotron/Models/Destination.swift — every alias here
 * exists in the real app. Keep it truthful.
 */

export type DestinationId =
  | "claude"
  | "chatgpt"
  | "gemini"
  | "docs"
  | "cursor"
  | "notes"
  | "perplexity"
  | "gmail"
  | "slack"
  | "here";

export interface Destination {
  id: DestinationId;
  name: string;
  /** Lowercase, longest-match wins — same rule as the app. */
  aliases: string[];
  /** Short line shown inside the tile. */
  hint: string;
}

export const DESTINATIONS: Destination[] = [
  {
    id: "claude",
    name: "Claude",
    aliases: ["claude", "claudia", "claudio", "claud", "clyde", "cloud", "clod", "anthropic"],
    hint: "claude.ai/new",
  },
  {
    id: "chatgpt",
    name: "ChatGPT",
    aliases: ["chatgpt", "chat gpt", "chat gbt", "chachi pt", "gpt", "openai", "open ai"],
    hint: "chat.openai.com",
  },
  {
    id: "gemini",
    name: "Gemini",
    aliases: ["gemini", "google gemini", "bard", "jiminy", "jimmy", "germany"],
    hint: "gemini.google.com",
  },
  {
    id: "docs",
    name: "Google Docs",
    aliases: ["google docs", "google doc", "google dock", "google dox", "docs", "document"],
    hint: "docs.google.com",
  },
  {
    id: "cursor",
    name: "Cursor",
    aliases: ["cursor", "code editor", "my editor", "courser", "kurser"],
    hint: "native app",
  },
  {
    id: "notes",
    name: "Apple Notes",
    aliases: ["apple notes", "to my notes", "new note", "notes", "note"],
    hint: "native app",
  },
  {
    id: "perplexity",
    name: "Perplexity",
    aliases: ["perplexity", "perplexed", "perplex", "search ai"],
    hint: "perplexity.ai",
  },
  {
    id: "gmail",
    name: "Gmail",
    aliases: ["gmail", "google mail"],
    hint: "mail.google.com",
  },
  {
    id: "slack",
    name: "Slack",
    aliases: ["slack"],
    hint: "app.slack.com",
  },
  {
    id: "here",
    name: "Here",
    aliases: ["here", "right here", "this app", "current app", "this"],
    hint: "pastes in place",
  },
];

const ROUTING_PREFIXES = ["hey ", "okay ", "ok ", "open "];

export interface ResolvedRoute {
  destination: Destination;
  /** The exact alias text that matched (for the strikethrough joke). */
  alias: string;
  /** Transcript with the routing phrase stripped, like the app does. */
  content: string;
}

/**
 * Longest-match alias resolution against the start of the transcript —
 * same behavior as the app ("chat gpt" beats "gpt").
 */
export function resolveDestination(transcript: string): ResolvedRoute | null {
  const lower = transcript.trim().toLowerCase();
  let rest: string | null = null;
  for (const p of ROUTING_PREFIXES) {
    if (lower.startsWith(p)) {
      rest = lower.slice(p.length);
      break;
    }
  }
  if (rest === null) return null;

  let best: { dest: Destination; alias: string } | null = null;
  for (const dest of DESTINATIONS) {
    for (const alias of dest.aliases) {
      if (rest.startsWith(alias) && (!best || alias.length > best.alias.length)) {
        best = { dest, alias };
      }
    }
  }
  if (!best) return null;

  const content = transcript
    .trim()
    .slice(transcript.trim().length - rest.length + best.alias.length)
    .replace(/^[\s,.:—-]+/, "");
  return { destination: best.dest, alias: best.alias, content };
}

/** Deterministic-cleanup preview: what the app's rule-based polish does. */
export function cleanTranscript(raw: string): string {
  let t = raw
    .replace(/\b(um|uh|uhh|umm|like,)\s*/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim();
  if (t.length > 0) t = t[0].toUpperCase() + t.slice(1);
  if (t.length > 0 && !/[.!?]$/.test(t)) t += ".";
  return t;
}

// ─── Scripted simulation takes ─────────────────────────────────────────────
// Word-by-word with per-word delays (ms) so the fake dictation has human
// rhythm — bursts, hesitations, a filler word the cleanup then removes.

export interface SimWord {
  word: string;
  delay: number;
}

export interface SimTake {
  words: SimWord[];
  target: DestinationId;
  /** What lands in the tile after "cleanup". */
  cleaned: string;
}

export const SIM_TAKES: SimTake[] = [
  {
    words: [
      { word: "hey", delay: 0 },
      { word: "claudia,", delay: 260 },
      { word: "um,", delay: 420 },
      { word: "summarize", delay: 380 },
      { word: "the", delay: 160 },
      { word: "standup", delay: 200 },
      { word: "notes", delay: 220 },
    ],
    target: "claude",
    cleaned: "Summarize the standup notes.",
  },
  {
    words: [
      { word: "hey", delay: 0 },
      { word: "chat", delay: 240 },
      { word: "gbt,", delay: 180 },
      { word: "write", delay: 400 },
      { word: "a", delay: 140 },
      { word: "haiku", delay: 220 },
      { word: "about", delay: 180 },
      { word: "mondays", delay: 240 },
    ],
    target: "chatgpt",
    cleaned: "Write a haiku about Mondays.",
  },
  {
    words: [
      { word: "hey", delay: 0 },
      { word: "google", delay: 250 },
      { word: "dox,", delay: 180 },
      { word: "uh,", delay: 380 },
      { word: "draft", delay: 320 },
      { word: "the", delay: 150 },
      { word: "cover", delay: 190 },
      { word: "letter", delay: 210 },
    ],
    target: "docs",
    cleaned: "Draft the cover letter.",
  },
  {
    words: [
      { word: "remind", delay: 0 },
      { word: "me", delay: 150 },
      { word: "to", delay: 130 },
      { word: "stretch", delay: 220 },
      { word: "at", delay: 170 },
      { word: "three", delay: 190 },
      { word: "pm", delay: 160 },
    ],
    target: "here",
    cleaned: "Remind me to stretch at 3pm.",
  },
];

/** Pairs for the fuzzy-alias marquee belt. */
export const ALIAS_PAIRS: { heard: string; resolved: string }[] = [
  { heard: "hey claudia", resolved: "Claude" },
  { heard: "chat gbt", resolved: "ChatGPT" },
  { heard: "hey google dox", resolved: "Google Docs" },
  { heard: "hey jiminy", resolved: "Gemini" },
  { heard: "hey courser", resolved: "Cursor" },
  { heard: "hey clod", resolved: "Claude" },
  { heard: "chachi pt", resolved: "ChatGPT" },
  { heard: "hey perplexed", resolved: "Perplexity" },
  { heard: "to my notes", resolved: "Apple Notes" },
  { heard: "hey cloud", resolved: "Claude" },
  { heard: "hey germany", resolved: "Gemini" },
  { heard: "hey google dock", resolved: "Google Docs" },
];

// Replace with your GitHub release URL once the first DMG is up.
export const DOWNLOAD_URL = "#download";
