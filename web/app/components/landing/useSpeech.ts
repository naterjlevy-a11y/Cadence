"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type SR = {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((e: SpeechResultEvent) => void) | null;
  onend: (() => void) | null;
  onerror: ((e: { error: string }) => void) | null;
};

type SpeechResultEvent = {
  resultIndex: number;
  results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }>;
};

function getSRConstructor(): (new () => SR) | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as Record<string, unknown>;
  return (w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null) as
    | (new () => SR)
    | null;
}

/**
 * SpeechRecognition wrapper. continuous + interimResults; auto-restarts
 * around Chrome's habit of ending sessions early; keeps the last interim
 * as the final take if no final result arrived by stop().
 */
export function useSpeech(onTranscript: (text: string, isFinal: boolean) => void) {
  const [supported, setSupported] = useState(false);
  const recRef = useRef<SR | null>(null);
  const listeningRef = useRef(false);
  const finalsRef = useRef("");
  const interimRef = useRef("");
  const cbRef = useRef(onTranscript);
  cbRef.current = onTranscript;

  useEffect(() => {
    setSupported(getSRConstructor() !== null);
    return () => {
      listeningRef.current = false;
      recRef.current?.abort();
    };
  }, []);

  const start = useCallback(() => {
    const Ctor = getSRConstructor();
    if (!Ctor || listeningRef.current) return;
    finalsRef.current = "";
    interimRef.current = "";
    listeningRef.current = true;

    const rec = new Ctor();
    rec.continuous = true;
    rec.interimResults = true;
    rec.lang = navigator.language || "en-US";
    rec.onresult = (e) => {
      let interim = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) finalsRef.current += r[0].transcript + " ";
        else interim += r[0].transcript;
      }
      interimRef.current = interim;
      cbRef.current((finalsRef.current + interim).trim(), false);
    };
    rec.onend = () => {
      // Chrome ends sessions on its own; restart while we're meant to listen.
      if (listeningRef.current && recRef.current === rec) {
        try {
          rec.start();
        } catch {
          /* already started */
        }
      }
    };
    rec.onerror = () => {
      /* "no-speech" etc. — onend handles restart; denial is handled by mic hook */
    };
    recRef.current = rec;
    try {
      rec.start();
    } catch {
      /* ignore double-start */
    }
  }, []);

  const stop = useCallback((): string => {
    listeningRef.current = false;
    recRef.current?.stop();
    recRef.current = null;
    const text = (finalsRef.current + interimRef.current).trim();
    cbRef.current(text, true);
    return text;
  }, []);

  return { supported, start, stop };
}
