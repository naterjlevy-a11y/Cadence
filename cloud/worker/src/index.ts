/**
 * Cadence API — Cloudflare Worker
 *
 * Routes:
 *   GET  /health
 *   POST /v1/transcribe     — proxy audio → Groq Whisper (auth required)
 *   POST /v1/polish         — neaten a transcript → Groq LLM (auth required)
 *   GET  /v1/quota          — remaining seconds this month (auth required)
 *   POST /v1/checkout       — create a Stripe subscription Checkout Session (auth required)
 *   POST /v1/portal         — create a Stripe Customer Portal session (auth required)
 *   GET  /embedded-checkout — Stripe Embedded Checkout page (client_secret query param)
 *   POST /v1/stripe/webhook — Stripe subscription events (signature-verified)
 */

export interface Env {
  GROQ_API_KEY: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  FREE_MONTHLY_SECONDS?: string;
  // Stripe — set via `wrangler secret put`. Use a RESTRICTED key (rk_…).
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;   // pk_test_… or pk_live_… (safe to expose to clients)
  STRIPE_PRICE_ID?: string;          // the $5/mo recurring Price (price_…)
  STRIPE_WEBHOOK_SECRET?: string;    // whsec_… from the webhook endpoint
  CHECKOUT_SUCCESS_URL?: string;     // return_url after embedded checkout completes
  CHECKOUT_CANCEL_URL?: string;
}

const GROQ_TRANSCRIBE = "https://api.groq.com/openai/v1/audio/transcriptions";
const GROQ_CHAT = "https://api.groq.com/openai/v1/chat/completions";
const POLISH_MODEL = "llama-3.3-70b-versatile";
const TRANSCRIBE_MODEL = "whisper-large-v3-turbo";
const STRIPE_API = "https://api.stripe.com/v1";

/** Groq's own upload ceiling. Reject earlier so we don't pay to find out. */
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
/** Polish has no natural duration, so bill it against the same second-denominated
 *  meter at a deliberately cheap rate: ~1s per 200 characters, min 1s. */
const POLISH_SECONDS_PER_CHAR = 1 / 200;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return cors(new Response(null, { status: 204 }), request);
    }

    if (url.pathname === "/health") {
      return cors(json({ ok: true, service: "cadence-api" }), request);
    }

    if (url.pathname === "/v1/transcribe" && request.method === "POST") {
      return cors(await handleTranscribe(request, env, ctx), request);
    }

    if (url.pathname === "/v1/polish" && request.method === "POST") {
      return cors(await handlePolish(request, env, ctx), request);
    }

    if (url.pathname === "/v1/quota" && request.method === "GET") {
      return cors(await handleQuota(request, env), request);
    }

    if (url.pathname === "/v1/checkout" && request.method === "POST") {
      return cors(await handleCheckout(request, env), request);
    }

    if (url.pathname === "/v1/portal" && request.method === "POST") {
      return cors(await handlePortal(request, env), request);
    }

    if (url.pathname === "/embedded-checkout" && request.method === "GET") {
      return handleEmbeddedCheckoutPage(request, env);
    }

    if (url.pathname === "/v1/stripe/webhook" && request.method === "POST") {
      return await handleStripeWebhook(request, env);
    }

    return cors(json({ error: "not_found" }, 404), request);
  },
};

async function handleTranscribe(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("multipart/form-data")) {
    return json({ error: "expected_multipart" }, 400);
  }

  // Verified auth. `decodeJwtUserId` only decoded the payload — it checked no
  // signature and no expiry, so a hand-written three-segment string passed.
  // `authenticate` round-trips to /auth/v1/user, which actually verifies.
  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);
  const userId = user.id;

  // Quota is now checked BEFORE Groq is called. Previously both were fired in
  // parallel and the 429 was returned after Groq had already transcribed and
  // billed us, so an over-quota client could loop indefinitely at our expense.
  const quota = await checkQuotaStrict(env, userId);
  if (!quota.ok) {
    return json({ error: "quota_unavailable", message: "Try again shortly." }, 503);
  }
  if (!quota.allowed) {
    return json(
      {
        error: "quota_exceeded",
        message: "Monthly transcription limit reached. Upgrade or use your own Groq key in Settings.",
        used_seconds: quota.usedSeconds,
        limit_seconds: quota.limitSeconds,
      },
      429
    );
  }

  // Rebuild the upload server-side rather than forwarding the client's body
  // verbatim. This pins the model (a client could otherwise select a costlier
  // one) and forces verbose_json so Groq returns the true audio `duration` —
  // billing used to be derived from uploaded byte count, which a client could
  // deflate ~30x just by lowering its bitrate.
  let inbound: FormData;
  try {
    inbound = await request.formData();
  } catch {
    return json({ error: "expected_multipart" }, 400);
  }
  // This tsconfig types FormData.get() as `string`, but the Workers runtime
  // hands back a File for a binary part. Narrow structurally rather than
  // trusting the lib types.
  const part = inbound.get("file") as unknown;
  if (!part || typeof part === "string") return json({ error: "missing_file" }, 400);
  const file = part as Blob & { name?: string };
  if (typeof file.size !== "number") return json({ error: "missing_file" }, 400);
  if (file.size > MAX_AUDIO_BYTES) return json({ error: "audio_too_large" }, 413);

  const outbound = new FormData();
  outbound.set("file", file as Blob, file.name || "audio.wav");
  outbound.set("model", TRANSCRIBE_MODEL);
  outbound.set("response_format", "verbose_json");
  const language = inbound.get("language");
  if (typeof language === "string" && language) outbound.set("language", language);

  const groqRes = await fetch(GROQ_TRANSCRIBE, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
    body: outbound,
  });

  if (!groqRes.ok) {
    console.error("Groq error", groqRes.status, (await groqRes.text()).slice(0, 300));
    return json({ error: "upstream_failed", status: groqRes.status }, 502);
  }

  const data = (await groqRes.json()) as { duration?: number };

  // Bill the duration Groq measured, not anything the client told us.
  const billedSeconds = Math.max(1, Math.ceil(data.duration ?? 1));
  ctx.waitUntil(recordUsage(env, userId, billedSeconds));

  return json(data);
}

async function handlePolish(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  // Was: `if (!token || !decodeJwtUserId(token))` — an unverified payload
  // decode, so any well-formed string authenticated. This endpoint had no
  // quota accounting of any kind, making it an open, uncounted LLM proxy.
  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);

  const quota = await checkQuotaStrict(env, user.id);
  if (!quota.ok) {
    return json({ error: "quota_unavailable", message: "Try again shortly." }, 503);
  }
  if (!quota.allowed) {
    // Polish is a convenience, so degrade instead of erroring: the app falls
    // back to its local rule-based cleanup when it gets the text unchanged.
    const body = (await request.json().catch(() => ({}))) as { text?: string };
    return json({ text: (body.text ?? "").trim() });
  }

  let payload: { text?: string; flavor?: string };
  try {
    payload = (await request.json()) as { text?: string; flavor?: string };
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const text = (payload.text ?? "").trim();
  if (!text) return json({ text: "" });
  // Guard against runaway prompts / abuse.
  if (text.length > 8000) return json({ text });

  const flavor = payload.flavor ?? "generic";
  const styleHints: Record<string, string> = {
    code: "The target is a code editor or terminal. Use straight ASCII quotes and hyphens; never smart quotes or em dashes.",
    document: "The target is a document or email. Use clean paragraphs and proper punctuation.",
    chat: "The target is an AI chat box. Keep it natural and direct.",
    generic: "",
  };

  const system =
    "You clean up dictated speech-to-text. Fix punctuation, capitalization, and obvious transcription errors. " +
    "Remove filler words (um, uh, like, you know). Keep the user's exact wording and meaning — do NOT add, remove, " +
    "summarize, answer, or change content. Output ONLY the cleaned text, nothing else. " +
    (styleHints[flavor] ?? "");

  const groqRes = await fetch(GROQ_CHAT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: POLISH_MODEL,
      temperature: 0,
      max_tokens: 2048,
      messages: [
        { role: "system", content: system },
        { role: "user", content: text },
      ],
    }),
  });

  if (!groqRes.ok) {
    // Fail open — the app falls back to its rule-based cleanup.
    return json({ text });
  }

  const data = (await groqRes.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const polished = data.choices?.[0]?.message?.content?.trim();

  // Meter it. Previously every polish call was free spend on our Groq key,
  // even for legitimate signed-in users.
  ctx.waitUntil(
    recordUsage(env, user.id, Math.max(1, Math.ceil(text.length * POLISH_SECONDS_PER_CHAR)))
  );

  return json({ text: polished && polished.length > 0 ? polished : text });
}

/**
 * Quota lookup that FAILS CLOSED.
 *
 * The previous implementation (`fetchProfileWithJWT`) returned a synthetic
 * `{plan:"free", monthly_seconds_used:0}` whenever PostgREST responded with a
 * non-2xx — which is exactly what a forged JWT produced. Zero usage always
 * satisfies the limit check, so a bad token bought unlimited transcription.
 *
 * Callers must treat `ok === false` as "refuse the request", never as "allow".
 */
interface StrictQuota {
  ok: boolean;
  allowed: boolean;
  plan: string;
  usedSeconds: number;
  limitSeconds: number;
}

async function checkQuotaStrict(env: Env, userId: string): Promise<StrictQuota> {
  const deny: StrictQuota = {
    ok: false,
    allowed: false,
    plan: "free",
    usedSeconds: 0,
    limitSeconds: 0,
  };

  const url =
    `${env.SUPABASE_URL}/rest/v1/profiles` +
    `?id=eq.${encodeURIComponent(userId)}&select=plan,monthly_seconds_used`;

  let res: Response;
  try {
    res = await fetch(url, {
      headers: { ...supabaseServiceHeaders(env), Accept: "application/json" },
    });
  } catch (err) {
    console.error("quota lookup threw", err);
    return deny;
  }

  if (!res.ok) {
    console.error("quota lookup failed", res.status);
    return deny;
  }

  const rows = (await res.json()) as Profile[];
  const profile = rows[0];
  // No row for a verified user means the signup trigger did not run. Refuse
  // rather than inventing a free profile we cannot meter.
  if (!profile) {
    console.error("no profile row for verified user");
    return deny;
  }

  const freeLimit = parseInt(env.FREE_MONTHLY_SECONDS ?? "10800", 10);
  const limit = profile.plan === "pro" ? Number.MAX_SAFE_INTEGER : freeLimit;
  const used = profile.monthly_seconds_used ?? 0;

  return {
    ok: true,
    allowed: used < limit,
    plan: profile.plan,
    usedSeconds: used,
    limitSeconds: limit,
  };
}

async function handleQuota(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);

  const quota = await checkQuota(env, user.id);
  return json({
    plan: quota.plan,
    used_seconds: quota.usedSeconds,
    limit_seconds: quota.limitSeconds,
    remaining_seconds: Math.max(0, quota.limitSeconds - quota.usedSeconds),
  });
}

// ── Stripe: Checkout + Portal ────────────────────────────────────────────────

async function handleCheckout(request: Request, env: Env): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_PRICE_ID) {
    return json({ error: "stripe_not_configured" }, 501);
  }
  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);

  let embedded = true;
  try {
    const body = (await request.json()) as { embedded?: boolean };
    if (body.embedded === false) embedded = false;
  } catch {
    // Default to embedded checkout for the macOS app.
  }

  const profile = await getProfileFull(env, user.id);
  const returnURL = env.CHECKOUT_SUCCESS_URL ?? "https://cadence.app/welcome?checkout=complete";

  const form: Record<string, string> = {
    mode: "subscription",
    "line_items[0][price]": env.STRIPE_PRICE_ID,
    "line_items[0][quantity]": "1",
    client_reference_id: user.id,
    "subscription_data[metadata][supabase_user_id]": user.id,
    "metadata[supabase_user_id]": user.id,
    allow_promotion_codes: "true",
  };

  if (embedded) {
    form.ui_mode = "embedded_page";
    form.return_url = returnURL;
  } else {
    const cancelURL = env.CHECKOUT_CANCEL_URL ?? "https://cadence.app/pricing";
    form.success_url = returnURL;
    form.cancel_url = cancelURL;
  }

  if (profile.stripe_customer_id) {
    form.customer = profile.stripe_customer_id;
  } else if (user.email) {
    form.customer_email = user.email;
  }

  const res = await stripeForm(env, "/checkout/sessions", form);
  if (!res.ok) {
    const detail = await res.text();
    console.error("checkout create failed", res.status, detail.slice(0, 300));
    let message = "checkout_failed";
    try {
      const parsed = JSON.parse(detail) as { error?: { message?: string }; message?: string };
      message = parsed.error?.message ?? parsed.message ?? detail.slice(0, 200);
    } catch {
      message = detail.slice(0, 200) || "checkout_failed";
    }
    return json({ error: "checkout_failed", detail: message }, 502);
  }
  const session = (await res.json()) as { url?: string; client_secret?: string };
  if (embedded) {
    if (!session.client_secret) return json({ error: "no_client_secret" }, 502);
    return json({
      client_secret: session.client_secret,
      publishable_key: env.STRIPE_PUBLISHABLE_KEY ?? null,
      return_url: returnURL,
    });
  }
  if (!session.url) return json({ error: "no_checkout_url" }, 502);
  return json({ url: session.url });
}

/** Serves a minimal page that mounts Stripe Embedded Checkout in a WKWebView. */
function handleEmbeddedCheckoutPage(request: Request, env: Env): Response {
  const url = new URL(request.url);
  const clientSecret = url.searchParams.get("client_secret") ?? "";
  const pk = url.searchParams.get("pk") ?? env.STRIPE_PUBLISHABLE_KEY ?? "";
  if (!clientSecret || !pk) {
    return new Response("Missing client_secret or publishable key.", { status: 400 });
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Cadence Pro</title>
  <script src="https://js.stripe.com/v3/"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0f0f12; color: #fff; min-height: 100vh; }
    #checkout { min-height: 100vh; padding: 24px 16px; }
    .header { text-align: center; padding: 20px 0 8px; }
    .header h1 { font-size: 22px; font-weight: 600; letter-spacing: -0.02em; }
    .header p { font-size: 13px; color: rgba(255,255,255,0.55); margin-top: 6px; }
    #error { color: #ff6b6b; text-align: center; padding: 16px; font-size: 13px; display: none; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Cadence Pro</h1>
    <p>Unlimited dictation · $5/month · Cancel anytime</p>
  </div>
  <div id="error"></div>
  <div id="checkout"></div>
  <script>
    const stripe = Stripe(${JSON.stringify(pk)});
    stripe.initEmbeddedCheckout({ clientSecret: ${JSON.stringify(clientSecret)} })
      .then(function(checkout) { checkout.mount("#checkout"); })
      .catch(function(err) {
        document.getElementById("error").style.display = "block";
        document.getElementById("error").textContent = err.message || "Could not load checkout.";
      });
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": "default-src 'self' https://js.stripe.com https://*.stripe.com; script-src 'self' 'unsafe-inline' https://js.stripe.com; frame-src https://*.stripe.com; style-src 'self' 'unsafe-inline'",
    },
  });
}

async function handlePortal(request: Request, env: Env): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "stripe_not_configured" }, 501);
  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);

  const profile = await getProfileFull(env, user.id);
  if (!profile.stripe_customer_id) {
    return json({ error: "no_subscription" }, 404);
  }
  const returnURL = env.CHECKOUT_CANCEL_URL ?? "https://cadence.app/account";
  const res = await stripeForm(env, "/billing_portal/sessions", {
    customer: profile.stripe_customer_id,
    return_url: returnURL,
  });
  if (!res.ok) {
    console.error("portal create failed", res.status);
    return json({ error: "portal_failed" }, 502);
  }
  const session = (await res.json()) as { url?: string };
  if (!session.url) return json({ error: "no_portal_url" }, 502);
  return json({ url: session.url });
}

/** POST form-encoded body to the Stripe REST API with the secret/restricted key. */
async function stripeForm(env: Env, path: string, fields: Record<string, string>): Promise<Response> {
  const body = new URLSearchParams(fields).toString();
  return fetch(`${STRIPE_API}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
}

// ── Stripe: Webhook (signature-verified) ─────────────────────────────────────

async function handleStripeWebhook(request: Request, env: Env): Promise<Response> {
  if (!env.STRIPE_WEBHOOK_SECRET) {
    return json({ error: "stripe_not_configured" }, 501);
  }

  const signature = request.headers.get("stripe-signature");
  if (!signature) return json({ error: "missing_signature" }, 400);

  const body = await request.text();

  // Verify the signature BEFORE trusting any field. A forged request can
  // otherwise mark anyone "pro" for free.
  const valid = await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET);
  if (!valid) {
    console.warn("Stripe webhook signature verification failed");
    return json({ error: "invalid_signature" }, 400);
  }

  let event: { type?: string; data?: { object?: Record<string, unknown> } };
  try {
    event = JSON.parse(body);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const eventType = event.type ?? "unknown";
  const obj = event.data?.object as Record<string, unknown> | undefined;
  console.log("Stripe webhook:", eventType);

  switch (eventType) {
    case "checkout.session.completed": {
      const userId =
        (obj?.client_reference_id as string) ??
        (obj?.metadata as Record<string, string>)?.supabase_user_id ??
        "";
      const customerId = (obj?.customer as string) ?? "";
      if (userId) await setPlan(env, userId, "pro", customerId);
      break;
    }
    case "customer.subscription.created":
    case "customer.subscription.updated": {
      const userId = (obj?.metadata as Record<string, string>)?.supabase_user_id ?? "";
      const customerId = (obj?.customer as string) ?? "";
      const status = (obj?.status as string) ?? "";
      // Active/trialing = pro; anything else (canceled, unpaid, past_due) = free.
      const isActive = status === "active" || status === "trialing";
      if (userId) await setPlan(env, userId, isActive ? "pro" : "free", customerId);
      break;
    }
    case "customer.subscription.deleted": {
      const userId = (obj?.metadata as Record<string, string>)?.supabase_user_id ?? "";
      if (userId) await setPlan(env, userId, "free", "");
      break;
    }
    default:
      break;
  }

  return json({ received: true });
}

/**
 * Verify a Stripe webhook signature using Web Crypto (Workers have no Node
 * crypto). Implements the same scheme as `stripe.webhooks.constructEvent`:
 * sign `"{t}.{payload}"` with HMAC-SHA256 and compare to a `v1=` signature,
 * rejecting timestamps older than the tolerance to block replay attacks.
 */
async function verifyStripeSignature(
  payload: string,
  header: string,
  secret: string,
  toleranceSeconds = 300
): Promise<boolean> {
  const parts = header.split(",").reduce<Record<string, string>>((acc, part) => {
    const [k, v] = part.split("=");
    if (k && v) acc[k.trim()] = v.trim();
    return acc;
  }, {});

  const timestamp = parts["t"];
  const expected = parts["v1"];
  if (!timestamp || !expected) return false;

  // Reject stale timestamps (replay protection).
  const age = Math.abs(Date.now() / 1000 - parseInt(timestamp, 10));
  if (!Number.isFinite(age) || age > toleranceSeconds) return false;

  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(`${timestamp}.${payload}`));
  const computed = [...new Uint8Array(sigBuf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return timingSafeEqual(computed, expected);
}

/** Constant-time string compare to avoid leaking via timing. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

// ── Auth ─────────────────────────────────────────────────────────────────────

interface AuthUser {
  id: string;
  email?: string;
}

async function authenticate(request: Request, env: Env): Promise<AuthUser | null> {
  const auth = request.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: env.SUPABASE_ANON_KEY,
    },
  });

  if (!res.ok) return null;
  const data = (await res.json()) as { id?: string; email?: string };
  if (!data.id) return null;
  return { id: data.id, email: data.email };
}

// ── Quota (Supabase profiles) ────────────────────────────────────────────────

interface QuotaInfo {
  allowed: boolean;
  plan: string;
  usedSeconds: number;
  limitSeconds: number;
}

async function checkQuota(env: Env, userId: string): Promise<QuotaInfo> {
  const profile = await getProfile(env, userId);
  const freeLimit = parseInt(env.FREE_MONTHLY_SECONDS ?? "10800", 10);
  const limit = profile.plan === "pro" ? 999_999 : freeLimit;
  const used = profile.monthly_seconds_used ?? 0;
  return {
    allowed: used < limit,
    plan: profile.plan,
    usedSeconds: used,
    limitSeconds: limit,
  };
}

interface Profile {
  plan: string;
  monthly_seconds_used: number;
}

async function getProfile(env: Env, userId: string): Promise<Profile> {
  const url = `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}&select=plan,monthly_seconds_used`;
  const res = await fetch(url, {
    headers: supabaseServiceHeaders(env),
  });
  if (!res.ok) {
    console.error("profile fetch failed", res.status);
    return { plan: "free", monthly_seconds_used: 0 };
  }
  const rows = (await res.json()) as Profile[];
  return rows[0] ?? { plan: "free", monthly_seconds_used: 0 };
}

interface FullProfile extends Profile {
  stripe_customer_id?: string | null;
}

async function getProfileFull(env: Env, userId: string): Promise<FullProfile> {
  const url = `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}&select=plan,monthly_seconds_used,stripe_customer_id`;
  const res = await fetch(url, { headers: supabaseServiceHeaders(env) });
  if (!res.ok) {
    console.error("profile (full) fetch failed", res.status);
    return { plan: "free", monthly_seconds_used: 0, stripe_customer_id: null };
  }
  const rows = (await res.json()) as FullProfile[];
  return rows[0] ?? { plan: "free", monthly_seconds_used: 0, stripe_customer_id: null };
}

async function recordUsage(env: Env, userId: string, seconds: number): Promise<void> {
  const url = `${env.SUPABASE_URL}/rest/v1/rpc/increment_transcription_seconds`;
  // One retry: this write is the only thing standing between the free tier and
  // unlimited use, and it previously ignored the response entirely — a 5xx or a
  // rate-limit silently dropped the usage and the meter never moved.
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          ...supabaseServiceHeaders(env),
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ p_user_id: userId, p_seconds: seconds }),
      });
      if (res.ok) return;
      console.error("recordUsage failed", res.status, "attempt", attempt);
    } catch (err) {
      console.error("recordUsage threw", err, "attempt", attempt);
    }
  }
  console.error("recordUsage GAVE UP — unmetered usage", { userId, seconds });
}

async function setPlan(
  env: Env,
  userId: string,
  plan: string,
  stripeCustomerId: string
): Promise<void> {
  const url = `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}`;
  await fetch(url, {
    method: "PATCH",
    headers: {
      ...supabaseServiceHeaders(env),
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    // Never clear stripe_customer_id. Passing "" on downgrade used to null it,
    // which broke /v1/portal (no way to resubscribe or manage billing) and made
    // a re-subscribe mint a SECOND Stripe customer for the same person.
    body: JSON.stringify({
      plan,
      ...(stripeCustomerId ? { stripe_customer_id: stripeCustomerId } : {}),
      updated_at: new Date().toISOString(),
    }),
  });
}

function supabaseServiceHeaders(env: Env): Record<string, string> {
  return {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
  };
}


// ── Helpers ───────────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * The Mac app is a native client: it sends no Origin and ignores CORS entirely,
 * so it needs nothing from this function. The wildcard that used to live here
 * only ever benefited browsers — which meant any page on the internet could
 * drive /v1/transcribe and /v1/polish directly from JS.
 *
 * Echo an allowed origin or send no CORS headers at all.
 */
const ALLOWED_ORIGINS = new Set([
  "http://localhost:3000",
  "http://localhost:3001",
]);

function cors(response: Response, request?: Request): Response {
  const origin = request?.headers.get("origin");
  if (!origin || !ALLOWED_ORIGINS.has(origin)) return response;

  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Vary", "Origin");
  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  return new Response(response.body, { status: response.status, headers });
}
