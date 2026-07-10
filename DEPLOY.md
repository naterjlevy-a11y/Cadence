# Cadence — production setup

Ship Cadence **outside the Mac App Store** (Developer ID + notarized DMG).  
This guide wires **Supabase** (auth + DB), **Cloudflare Workers** (Groq proxy), and optional **Stripe** (billing).

---

## 1. Supabase (~15 min)

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL** → run `supabase/migrations/20240601000000_initial.sql`.
3. **Authentication → Providers**:
   - Enable **Anonymous sign-ins** (instant free tier, no signup wall).
   - Enable **Apple** — add your Services ID + key from Apple Developer (Sign in with Apple).
4. Copy **Project URL** and **anon public** key from Settings → API.

---

## 2. Cloudflare Worker (~20 min)

```bash
cd cloud/worker
npm install
npx wrangler login
```

Set secrets:

```bash
npx wrangler secret put GROQ_API_KEY
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
# optional later:
npx wrangler secret put STRIPE_WEBHOOK_SECRET
```

Deploy:

```bash
npm run deploy
```

In Cloudflare dashboard → **Workers & Pages** → your worker → **Triggers** → add route:

`api.yourdomain.com/*`

(GitHub Student Pack: free `.me` domain on Namecheap → point `api` CNAME to the worker.)

---

## 3. Cadence app config

```bash
cp Cadence/Resources/CloudConfig.example.plist Cadence/Resources/CloudConfig.plist
```

Edit `CloudConfig.plist`:

| Key | Value |
|-----|--------|
| `SupabaseURL` | `https://xxxx.supabase.co` |
| `SupabaseAnonKey` | anon key |
| `APIBaseURL` | `https://api.yourdomain.com` |
| `SentryDSN` | optional, from sentry.io (GitHub SDP) |

`CloudConfig.plist` is **gitignored**. For release builds, CI can inject it from GitHub Secrets.

Regenerate Xcode project:

```bash
xcodegen generate
```

Enable **Sign in with Apple** capability in Xcode → Signing & Capabilities (matches `Cadence.entitlements`).

---

## 4. How users get transcription

| Mode | What happens |
|------|----------------|
| **Auto** (default) | Signed into Cadence Cloud → your proxy. Else BYOK Groq key. Else Apple Speech. |
| **Cloud only** | Proxy only (needs sign-in / anonymous session). |
| **BYOK** | User's own Groq key (Settings → Dictation). |

On first launch with cloud configured, the app creates an **anonymous Supabase session** automatically (~3 h/month free quota in DB).

---

## 5. Stripe (when you charge)

1. [dashboard.stripe.com](https://dashboard.stripe.com) → Product → recurring price.
2. Create a **Checkout Session** from a small backend route (or Supabase Edge Function) with:
   - `client_reference_id` = Supabase `user.id`
   - `metadata.supabase_user_id` = same
3. Point Stripe webhook to: `https://api.yourdomain.com/v1/stripe/webhook`
4. Worker sets `profiles.plan = 'pro'` on `checkout.session.completed`.

Use **Stripe Customer Portal** for cancel / card updates (no custom UI).

---

## 6. Release (GitHub Actions)

Tag a release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Workflow: `.github/workflows/release.yml` — set secrets listed in that file.

Distribute `Cadence.dmg` from your website. Add **Sparkle** for auto-updates later.

---

## 7. GitHub Student Developer Pack (useful bits)

| Benefit | Use for |
|---------|---------|
| Namecheap `.me` | `cadence.me` + `api.cadence.me` |
| Sentry team | Crash reports — add SPM `sentry-cocoa`, uncomment `CrashReporter.swift` |
| GitHub Actions | Release workflow (included) |
| 1Password | Store Groq / Supabase / Stripe secrets |

Skip Heroku/Azure for this stack — Cloudflare + Supabase free tiers are enough to start.

---

## Security checklist

- [ ] Never commit `CloudConfig.plist`, `.env`, or Groq keys
- [ ] `GROQ_API_KEY` only in Wrangler secrets
- [ ] Supabase **service role** only on the Worker, never in the Mac app
- [ ] App only gets **anon** key + user JWT
- [ ] Rotate keys if a build leaks

---

## Mac App Store?

**Not viable** for Cadence (global hotkey tap, Accessibility paste, Chrome cookies).  
Use **Developer ID + notarization** — same path as Wispr Flow, Raycast, Cursor.

Your Apple Developer account is still required for **signing + notarization + Sign in with Apple**.
