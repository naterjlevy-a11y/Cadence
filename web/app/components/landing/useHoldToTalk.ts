"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  SIM_TAKES,
  cleanTranscript,
  resolveDestination,
  type DestinationId,
  type SimTake,
} from "./copy";
import { useMicLevel } from "./useMicLevel";
import { useSpeech } from "./useSpeech";

export type DemoState =
  | "boot"
  | "attract"
  | "requesting"
  | "armed"
  | "listening"
  | "routing"
  | "settle"
  | "sim-listening"
  | "sim-routing"
  | "fallback";

export interface RouteRequest {
  targetId: DestinationId;
  cleaned: string;
  seq: number;
}

const MIN_HOLD_MS = 200; // same constraint as the app
const TAIL_MS = 120; // same tail as the app
const ATTRACT_DELAY_MS = 2600;
const ATTRACT_LOOP_GAP_MS = 3200;

/**
 * The hero demo state machine. Simulation is a first-class citizen:
 * the attract loop and the no-mic fallback run the exact same visuals
 * as the live path.
 */
export function useHoldToTalk() {
  const [state, setState] = useState<DemoState>("boot");
  const [capability, setCapability] = useState<"unknown" | "live" | "fallback">("unknown");
  const [words, setWords] = useState<string[]>([]);
  const [litId, setLitId] = useState<DestinationId | null>(null);
  const [routeRequest, setRouteRequest] = useState<RouteRequest | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [pressed, setPressed] = useState(false);

  const stateRef = useRef(state);
  stateRef.current = state;
  const interactedRef = useRef(false);
  const visibleRef = useRef(true);
  const micGrantedRef = useRef<boolean | null>(null);
  const holdStartRef = useRef(0);
  const timersRef = useRef<number[]>([]);
  const seqRef = useRef(0);
  const takeIdxRef = useRef(0);
  const currentTakeRef = useRef<SimTake | null>(null);
  const attractTimerRef = useRef<number | null>(null);
  const toastTimerRef = useRef<number | null>(null);

  const mic = useMicLevel();
  const transcriptRef = useRef("");
  const speech = useSpeech((text) => {
    if (stateRef.current !== "listening") return;
    transcriptRef.current = text;
    setWords(text.length ? text.split(/\s+/) : []);
    setLitId(resolveDestination(text)?.destination.id ?? null);
  });

  const clearTimers = useCallback(() => {
    timersRef.current.forEach((t) => window.clearTimeout(t));
    timersRef.current = [];
    if (attractTimerRef.current !== null) {
      window.clearTimeout(attractTimerRef.current);
      attractTimerRef.current = null;
    }
  }, []);

  const showToast = useCallback((msg: string) => {
    setToast(msg);
    if (toastTimerRef.current !== null) window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = window.setTimeout(() => setToast(null), 3200);
  }, []);

  // ── capability detection ────────────────────────────────────────────────
  useEffect(() => {
    const w = window as unknown as Record<string, unknown>;
    const hasSR = Boolean(w.SpeechRecognition ?? w.webkitSpeechRecognition);
    const hasMic = Boolean(navigator.mediaDevices?.getUserMedia);
    const cap = hasSR && hasMic ? "live" : "fallback";
    setCapability(cap);
    setState(cap === "live" ? "attract" : "fallback");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── simulation engine (attract loop + fallback presses) ────────────────
  const playSimWords = useCallback(
    (take: SimTake, onDone?: () => void) => {
      setWords([]);
      setLitId(null);
      let elapsed = 0;
      const spoken: string[] = [];
      take.words.forEach(({ word, delay }, i) => {
        elapsed += delay;
        timersRef.current.push(
          window.setTimeout(() => {
            spoken.push(word);
            setWords([...spoken]);
            const joined = spoken.join(" ");
            setLitId(resolveDestination(joined)?.destination.id ?? null);
            if (i === take.words.length - 1) onDone?.();
          }, elapsed)
        );
      });
      return elapsed;
    },
    []
  );

  const requestRoute = useCallback((targetId: DestinationId, cleaned: string) => {
    seqRef.current += 1;
    setRouteRequest({ targetId, cleaned, seq: seqRef.current });
  }, []);

  const nextTake = useCallback((): SimTake => {
    const take = SIM_TAKES[takeIdxRef.current % SIM_TAKES.length];
    takeIdxRef.current += 1;
    return take;
  }, []);

  const scheduleAttract = useCallback(
    (delay: number) => {
      if (interactedRef.current) return;
      if (attractTimerRef.current !== null) window.clearTimeout(attractTimerRef.current);
      attractTimerRef.current = window.setTimeout(() => {
        if (interactedRef.current || !visibleRef.current) {
          scheduleAttract(ATTRACT_LOOP_GAP_MS);
          return;
        }
        const s = stateRef.current;
        if (s !== "attract" && s !== "fallback" && s !== "armed") return;
        const take = nextTake();
        currentTakeRef.current = take;
        setState("sim-listening");
        setPressed(true);
        playSimWords(take, () => {
          timersRef.current.push(
            window.setTimeout(() => {
              setPressed(false);
              setState("sim-routing");
              timersRef.current.push(
                window.setTimeout(() => requestRoute(take.target, take.cleaned), TAIL_MS)
              );
            }, 350)
          );
        });
      }, delay);
    },
    [nextTake, playSimWords, requestRoute]
  );

  useEffect(() => {
    if (state === "attract" || state === "fallback") scheduleAttract(ATTRACT_DELAY_MS);
  }, [state, scheduleAttract]);

  // ── press / release ─────────────────────────────────────────────────────
  const pressStart = useCallback(async () => {
    const s = stateRef.current;
    if (s === "listening" || s === "routing" || s === "requesting") return;
    interactedRef.current = true;
    clearTimers();
    setWords([]);
    setLitId(null);
    setToast(null);
    holdStartRef.current = Date.now();
    setPressed(true);

    if (capability === "live" && micGrantedRef.current !== false) {
      if (micGrantedRef.current === null) {
        setState("requesting");
        const ok = await mic.start();
        micGrantedRef.current = ok;
        if (!ok) {
          setPressed(false);
          setState("fallback");
          showToast("No mic? No problem — press again and we'll fake it beautifully.");
          return;
        }
      } else {
        const ok = await mic.start();
        if (!ok) {
          micGrantedRef.current = false;
          setPressed(false);
          setState("fallback");
          showToast("Mic unavailable — switching to the scripted demo.");
          return;
        }
      }
      transcriptRef.current = "";
      setState("listening");
      speech.start();
    } else {
      // fallback: scripted take, timed to the visitor's actual hold
      const take = nextTake();
      currentTakeRef.current = take;
      setState("sim-listening");
      playSimWords(take);
    }
  }, [capability, clearTimers, mic, nextTake, playSimWords, showToast, speech]);

  const pressEnd = useCallback(() => {
    const s = stateRef.current;
    setPressed(false);
    if (s !== "listening" && s !== "sim-listening") return;
    const held = Date.now() - holdStartRef.current;

    if (held < MIN_HOLD_MS) {
      if (s === "listening") {
        speech.stop();
        mic.stop();
      }
      clearTimers();
      setWords([]);
      setLitId(null);
      setState(capability === "live" && micGrantedRef.current ? "armed" : "fallback");
      showToast("Hold it a beat longer — the app wants 200ms too.");
      return;
    }

    if (s === "listening") {
      setState("routing");
      window.setTimeout(() => {
        const finalText = speech.stop();
        mic.stop();
        if (!finalText.trim()) {
          setState("armed");
          showToast("We heard nothing, so we typed nothing. (The app does this too — silence detection.)");
          setWords([]);
          setLitId(null);
          return;
        }
        const route = resolveDestination(finalText);
        const targetId: DestinationId = route?.destination.id ?? "here";
        const cleaned = cleanTranscript(route ? route.content : finalText);
        setLitId(targetId);
        requestRoute(targetId, cleaned);
      }, TAIL_MS);
    } else {
      // fallback press: route whatever the script got through
      clearTimers();
      const take = currentTakeRef.current;
      if (!take) return;
      setState("sim-routing");
      window.setTimeout(() => requestRoute(take.target, take.cleaned), TAIL_MS);
    }
  }, [capability, clearTimers, mic, requestRoute, showToast, speech]);

  /** HeroDemo calls this when the fly+gulp animation finishes. */
  const completeRouting = useCallback(() => {
    setState("settle");
    timersRef.current.push(
      window.setTimeout(() => {
        setWords([]);
        setLitId(null);
        setRouteRequest(null);
        const live = capability === "live" && micGrantedRef.current === true;
        setState(live ? "armed" : interactedRef.current ? "fallback" : "attract");
        if (!interactedRef.current) scheduleAttract(ATTRACT_LOOP_GAP_MS);
      }, 1200)
    );
  }, [capability, scheduleAttract]);

  // ── global guards ───────────────────────────────────────────────────────
  useEffect(() => {
    const isInteractive = (el: Element | null) =>
      !!el &&
      (["INPUT", "TEXTAREA", "SELECT", "SUMMARY"].includes(el.tagName) ||
        (el as HTMLElement).isContentEditable);

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.code !== "Space") return;
      if (!visibleRef.current) return;
      if (isInteractive(document.activeElement)) return;
      // Always eat the default (page scroll / button click) while the demo
      // is on screen — including key-repeat events, which also scroll.
      e.preventDefault();
      e.stopPropagation();
      if (e.repeat) return;
      void pressStart();
    };
    const onKeyUp = (e: KeyboardEvent) => {
      if (e.code !== "Space") return;
      if (visibleRef.current) e.preventDefault();
      if (stateRef.current === "listening" || stateRef.current === "sim-listening") {
        pressEnd();
      }
    };
    const hardStop = () => {
      if (stateRef.current === "listening") {
        speech.stop();
        mic.stop();
        setPressed(false);
        setWords([]);
        setLitId(null);
        setState("armed");
      } else if (stateRef.current === "sim-listening") {
        clearTimers();
        setPressed(false);
        setWords([]);
        setLitId(null);
        setState("fallback");
      }
    };
    const onVis = () => document.hidden && hardStop();

    window.addEventListener("keydown", onKeyDown, { capture: true });
    window.addEventListener("keyup", onKeyUp, { capture: true });
    window.addEventListener("blur", hardStop);
    document.addEventListener("visibilitychange", onVis);
    return () => {
      window.removeEventListener("keydown", onKeyDown, { capture: true });
      window.removeEventListener("keyup", onKeyUp, { capture: true });
      window.removeEventListener("blur", hardStop);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [pressStart, pressEnd, clearTimers, mic, speech]);

  useEffect(() => () => clearTimers(), [clearTimers]);

  const setVisible = useCallback((v: boolean) => {
    visibleRef.current = v;
  }, []);

  /** Explicit "watch it instead →" trigger. */
  const runSimulation = useCallback(() => {
    interactedRef.current = true;
    clearTimers();
    const take = nextTake();
    currentTakeRef.current = take;
    setState("sim-listening");
    setPressed(true);
    playSimWords(take, () => {
      timersRef.current.push(
        window.setTimeout(() => {
          setPressed(false);
          setState("sim-routing");
          timersRef.current.push(
            window.setTimeout(() => requestRoute(take.target, take.cleaned), TAIL_MS)
          );
        }, 350)
      );
    });
  }, [clearTimers, nextTake, playSimWords, requestRoute]);

  const listening = state === "listening" || state === "sim-listening";
  return {
    state,
    capability,
    words,
    litId,
    routeRequest,
    toast,
    pressed,
    listening,
    micLevelGetter: state === "listening" ? mic.getLevel : null,
    pressStart,
    pressEnd,
    completeRouting,
    setVisible,
    runSimulation,
  };
}
