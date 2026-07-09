"use client";

import { useCallback, useEffect, useRef } from "react";

/**
 * Mic amplitude for the live waveform. Acquires the stream per listening
 * session and fully releases it on stop — the browser's mic indicator must
 * go dark the moment the key is released. Never leaves the mic hot.
 */
export function useMicLevel() {
  const ctxRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const bufRef = useRef<Uint8Array<ArrayBuffer> | null>(null);

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    analyserRef.current = null;
    if (ctxRef.current && ctxRef.current.state !== "closed") {
      void ctxRef.current.close();
    }
    ctxRef.current = null;
  }, []);

  /** Returns true if mic granted + analyser live; false if denied/failed. */
  const start = useCallback(async (): Promise<boolean> => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const ctx = new AudioContext();
      ctxRef.current = ctx;
      const src = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      src.connect(analyser);
      analyserRef.current = analyser;
      bufRef.current = new Uint8Array(new ArrayBuffer(analyser.fftSize));
      return true;
    } catch {
      stop();
      return false;
    }
  }, [stop]);

  /** RMS amplitude 0..1, safe to call every frame. */
  const getLevel = useCallback((): number => {
    const analyser = analyserRef.current;
    const buf = bufRef.current;
    if (!analyser || !buf) return 0;
    analyser.getByteTimeDomainData(buf);
    let sum = 0;
    for (let i = 0; i < buf.length; i++) {
      const v = (buf[i] - 128) / 128;
      sum += v * v;
    }
    return Math.min(1, Math.sqrt(sum / buf.length) * 3);
  }, []);

  useEffect(() => stop, [stop]);

  return { start, stop, getLevel };
}
