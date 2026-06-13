"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

/**
 * Supabase sometimes redirects to the Site URL root with tokens in the hash:
 *   http://localhost:3000/#access_token=…
 * Forward those to /auth/callback so the bridge page can open Mellotron.
 */
export function AuthHashBridge() {
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    if (pathname === "/auth/callback") return;
    const hash = window.location.hash;
    const search = window.location.search;
    const looksLikeAuth =
      hash.includes("access_token=") ||
      hash.includes("error=") ||
      search.includes("code=");
    if (looksLikeAuth) {
      router.replace(`/auth/callback${search}${hash}`);
    }
  }, [pathname, router]);

  return null;
}
