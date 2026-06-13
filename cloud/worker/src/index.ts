/**
 * Mellotron API — Cloudflare Worker
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
const STRIPE_API = "https://api.stripe.com/v1";

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return cors(new Response(null, { status: 204 }));
    }

    if (url.pathname === "/health") {
      return cors(json({ ok: true, service: "mellotron-api" }));
    }

    if (url.pathname === "/v1/transcribe" && request.method === "POST") {
      return cors(await handleTranscribe(request, env, ctx));
    }

    if (url.pathname === "/v1/polish" && request.method === "POST") {
      return cors(await handlePolish(request, env));
    }

    if (url.pathname === "/v1/quota" && request.method === "GET") {
      return cors(await handleQuota(request, env));
    }

    if (url.pathname === "/v1/checkout" && request.method === "POST") {
      return cors(await handleCheckout(request, env));
    }

    if (url.pathname === "/v1/portal" && request.method === "POST") {
      return cors(await handlePortal(request, env));
    }

    if (url.pathname === "/embedded-checkout" && request.method === "GET") {
      return handleEmbeddedCheckoutPage(request, env);
    }

    if (url.pathname === "/v1/stripe/webhook" && request.method === "POST") {
      return await handleStripeWebhook(request, env);
    }

    return cors(json({ error: "not_found" }, 404));
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

  const auth = request.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "unauthorized" }, 401);

  // Single Supabase round-trip: PostgREST with the user's JWT validates auth
  // AND fetches their quota row via RLS (auth.uid() = id). One call replaces
  // /auth/v1/user + GET /rest/v1/profiles.
  const userId = decodeJwtUserId(token);
  if (!userId) return json({ error: "invalid_token" }, 401);

  // Buffer body BEFORE awaiting anything else so we can fan out without
  // racing the request stream lifecycle.
  const audioBody = await request.arrayBuffer();
  const audioSeconds = Math.max(1, Math.ceil((audioBody.byteLength / 32_000) * 0.7));

  // Parallel: kick off quota check AND Groq request together. If quota
  // exceeded, we discard the Groq response. ~400ms saved per call.
  const freeLimit = parseInt(env.FREE_MONTHLY_SECONDS ?? "10800", 10);
  const quotaPromise = fetchProfileWithJWT(env, token).catch(() => ({
    plan: "free",
    monthly_seconds_used: 0,
  }));
  const groqPromise = fetch(GROQ_TRANSCRIBE, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      "Content-Type": contentType,
    },
    body: audioBody,
  });

  const [profile, groqRes] = await Promise.all([quotaPromise, groqPromise]);
  const limit = profile.plan === "pro" ? 999_999 : freeLimit;
  const used = profile.monthly_seconds_used ?? 0;

  if (used >= limit) {
    return json(
      {
        error: "quota_exceeded",
        message: "Monthly transcription limit reached. Upgrade or use your own Groq key in Settings.",
        used_seconds: used,
        limit_seconds: limit,
      },
      429
    );
  }

  if (!groqRes.ok) {
    const body = await groqRes.text();
    console.error("Groq error", groqRes.status, body.slice(0, 300));
    return json(
      { error: "upstream_failed", status: groqRes.status, detail: body.slice(0, 200) },
      502
    );
  }

  const data = await groqRes.json();

  // Fire-and-forget usage write — doesn't block the response (~150ms saved).
  ctx.waitUntil(recordUsage(env, userId, audioSeconds));

  return json(data);
}

async function handlePolish(request: Request, env: Env): Promise<Response> {
  const auth = request.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token || !decodeJwtUserId(token)) return json({ error: "unauthorized" }, 401);

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
  return json({ text: polished && polished.length > 0 ? polished : text });
}

/**
 * Decode the `sub` claim from a Supabase JWT without verifying signature.
 * Verification happens at PostgREST when we use the JWT to fetch profiles
 * (RLS rejects bad signatures). This is a fast pre-check to extract the
 * user id without a network round-trip.
 */
function decodeJwtUserId(jwt: string): string | null {
  const parts = jwt.split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

async function fetchProfileWithJWT(env: Env, jwt: string): Promise<Profile> {
  // PostgREST validates the JWT and applies RLS — bad JWT = 401, valid JWT =
  // exactly the user's own profile row.
  const url = `${env.SUPABASE_URL}/rest/v1/profiles?select=plan,monthly_seconds_used`;
  const res = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${jwt}`,
      Accept: "application/json",
    },
  });
  if (!res.ok) {
    return { plan: "free", monthly_seconds_used: 0 };
  }
  const rows = (await res.json()) as Profile[];
  return rows[0] ?? { plan: "free", monthly_seconds_used: 0 };
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
  const returnURL = env.CHECKOUT_SUCCESS_URL ?? "https://mellotron.app/welcome?checkout=complete";

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
    const cancelURL = env.CHECKOUT_CANCEL_URL ?? "https://mellotron.app/pricing";
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
  <title>Mellotron Pro</title>
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
    <h1>Mellotron Pro</h1>
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
  const returnURL = env.CHECKOUT_CANCEL_URL ?? "https://mellotron.app/account";
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
  await fetch(url, {
    method: "POST",
    headers: {
      ...supabaseServiceHeaders(env),
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ p_user_id: userId, p_seconds: seconds }),
  });
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
    body: JSON.stringify({
      plan,
      stripe_customer_id: stripeCustomerId || null,
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

function cors(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  return new Response(response.body, { status: response.status, headers });
}
