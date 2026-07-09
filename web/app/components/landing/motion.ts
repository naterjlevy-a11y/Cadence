"use client";

import { createScope, createSpring, type Scope } from "animejs";
import { useEffect, useRef, type DependencyList } from "react";

/**
 * One spring vocabulary for the whole page so every element feels like
 * part of the same physical object. Created lazily (inside effects only)
 * to stay SSR-safe.
 */
let _springs: {
  snappy: ReturnType<typeof createSpring>;
  soft: ReturnType<typeof createSpring>;
  gulp: ReturnType<typeof createSpring>;
} | null = null;

export function getSprings() {
  if (!_springs) {
    _springs = {
      // UI feedback: keycap release, tile pulses
      snappy: createSpring({ stiffness: 320, damping: 22 }),
      // Ambient: cursor repulsion recovery, hover drift
      soft: createSpring({ stiffness: 120, damping: 14 }),
      // The destination tile swallowing words
      gulp: createSpring({ stiffness: 500, damping: 18 }),
    };
  }
  return _springs;
}

/**
 * React wrapper around anime v4's createScope. Runs `setup` after mount,
 * reverts everything on unmount (handles StrictMode double-invoke).
 * Scope is created with a reduced-motion media query — check
 * `reducedMotion(scope)` inside setup and skip to end states.
 */
export function useAnimeScope(
  setup: (scope: Scope) => void,
  deps: DependencyList = []
) {
  const rootRef = useRef<HTMLElement | null>(null);
  const scopeRef = useRef<Scope | null>(null);

  useEffect(() => {
    if (!rootRef.current) return;
    const scope = createScope({
      root: rootRef.current,
      mediaQueries: { reduced: "(prefers-reduced-motion: reduce)" },
    }).add((self) => {
      if (self) setup(self);
    });
    scopeRef.current = scope;
    return () => {
      scope.revert();
      scopeRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return { rootRef, scopeRef };
}

export function reducedMotion(scope: Scope): boolean {
  return Boolean((scope.matches as Record<string, boolean>)?.reduced);
}

/** Plain check for non-scope contexts (canvas loops, state machines). */
export function prefersReducedMotion(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
