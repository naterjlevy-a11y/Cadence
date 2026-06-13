"use client";

import { useEffect, useState } from "react";

/**
 * Supabase magic links land here (http://localhost:3000/auth/callback#tokens…)
 * because custom URL schemes can't be used directly in email redirects.
 * This page immediately forwards tokens to the Mellotron app via mellotron://
 */
export default function AuthCallbackPage() {
  const [status, setStatus] = useState<"opening" | "manual">("opening");
  const [deepLink, setDeepLink] = useState("mellotron://auth/callback");
  const [missingTokens, setMissingTokens] = useState(false);

  useEffect(() => {
    const target = `mellotron://auth/callback${window.location.search}${window.location.hash}`;
    setDeepLink(target);

    const hasTokens =
      window.location.hash.includes("access_token=") ||
      window.location.search.includes("code=");

    if (!hasTokens) {
      setMissingTokens(true);
      setStatus("manual");
      return;
    }

    window.location.href = target;
    const timer = window.setTimeout(() => setStatus("manual"), 2000);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <main className="flex min-h-dvh flex-col items-center justify-center bg-mello-ink px-6 text-center text-mello-paper">
      <div className="max-w-md">
        <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-white/50">
          Mellotron sign-in
        </p>
        <h1 className="mt-4 font-display text-4xl tracking-tightest">
          {status === "opening" ? (
            <>
              Opening <span className="italic-display text-mello">Mellotron…</span>
            </>
          ) : (
            <>
              Almost <span className="italic-display text-mello">there.</span>
            </>
          )}
        </h1>
        <p className="mt-4 text-sm leading-relaxed text-white/65">
          {status === "opening"
            ? "Your browser is handing the session to the Mellotron app. You can close this tab once Mellotron opens."
            : "If Mellotron didn’t open automatically, click the button below. Make sure Mellotron is installed and running."}
        </p>

        {deepLink && (
          <a
            href={deepLink}
            className="mt-8 inline-flex rounded-2xl bg-mello px-6 py-3 text-base font-semibold text-mello-ink transition hover:bg-mello-glow"
          >
            Open Mellotron
          </a>
        )}

        {missingTokens && (
          <p className="mt-6 text-xs text-white/45">
            No sign-in tokens were found in this URL. Request a new link from Mellotron → Settings →
            Sign in.
          </p>
        )}
      </div>
    </main>
  );
}
