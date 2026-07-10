# Cadence — Pre-launch Priority 1 (step by step)

Five things, in order. Each one names exactly what's in the repo, what you click in a browser, and what to verify before moving on.

---

## 1. Sparkle auto-updates (≈ 30 min)

**What's already done in the repo**
- `Sparkle` SPM dependency added (`project.yml`).
- `Cadence/Services/UpdaterService.swift` — wraps `SPUStandardUpdaterController` with a daily background check.
- "Check for Updates…" appears in the hidden app menu **and** in the menu-bar popover.
- `Info.plist` keys via `project.yml`: `SUFeedURL`, `SUEnableAutomaticChecks`, `SUEnableInstallerLauncherService`, `SUPublicEDKey` (placeholder).
- `web/public/appcast.xml` — template appcast hosted next to the landing page.

**What you need to do**

### 1a. Generate your Sparkle EdDSA key pair (one-time, never lose this)

```bash
cd ~/Downloads
curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-2.9.2.tar.xz -o sparkle.tar.xz
tar xf sparkle.tar.xz
cd Sparkle-2.9.2
./bin/generate_keys
```

`generate_keys` prints:
- **Private key** → automatically stored in your Mac's Keychain as `ed25519`. **Back it up to 1Password** — if you lose it you can never publish updates to existing installs.
- **Public key** → copy this string (starts something like `MC4CAQAw…` — about 56 chars).

### 1b. Paste the public key into `project.yml`

Open `project.yml`, find this line:

```yaml
SUPublicEDKey: "REPLACE_WITH_ED25519_PUBLIC_KEY"
```

Replace with your public key. Then:

```bash
cd /Users/natelevy/Projects/Cadence
xcodegen generate
```

### 1c. (Later, when you ship) Sign each DMG

```bash
~/Downloads/Sparkle-2.9.2/bin/sign_update Cadence-0.1.0.dmg
```

This prints a `sparkle:edSignature="…"` line and a `length=…`. Paste both into a new `<item>` in `web/public/appcast.xml`, push the web folder, and your existing users will see an update prompt within 24 hours.

### 1d. Test "Check for Updates" works

Open Cadence → menu-bar icon → **Check for updates…**

It'll fail loudly because the appcast URL isn't live yet — that's fine. The button works.

---

## 2. Sentry crash reporting (≈ 10 min)

**What's already done**
- `Sentry` SPM dependency added.
- `Cadence/Services/CrashReporter.swift` — calls `SentrySDK.start` on launch when a DSN is set. Tags every event with `release: cadence@VERSION+BUILD`.
- `CloudConfig.plist` has a `SentryDSN` slot (currently empty).

**What you need to do**

### 2a. Sign up

Go to [sentry.io/signup](https://sentry.io/signup). Pick **macOS / Cocoa**. **GitHub Student Pack:** apply for the free Team plan via [education.github.com/pack](https://education.github.com/pack) — search for "Sentry."

### 2b. Create a project

Sentry → **Projects → Create Project** → platform **macOS / Cocoa** → name `cadence`.

It'll show you a DSN that looks like `https://abc123@o0.ingest.sentry.io/123456`. Copy it.

### 2c. Paste DSN into config

Open `/Users/natelevy/Projects/Cadence/Cadence/Resources/CloudConfig.plist`:

```xml
<key>SentryDSN</key>
<string>PASTE_DSN_HERE</string>
```

Save. Relaunch Cadence. The Console log will print `CrashReporter: Sentry active`.

### 2d. Test it

In Sentry, click the project's **Issues → Send test event** menu (top-right of the dashboard), or in your code add `CrashReporter.captureMessage("hello")` somewhere, build, run, then revert. The test event should appear in your Sentry dashboard within 30 seconds.

---

## 3. Landing page on Vercel (≈ 30 min)

**What's already done**
- `web/` directory: full Next.js 14 + Tailwind landing page.
- Hero, three-step flow, feature grid, support footer.
- `web/public/appcast.xml` — will be served at `https://your-domain/appcast.xml`.

**What you need to do**

### 3a. Local preview

```bash
cd /Users/natelevy/Projects/Cadence/web
npm install
npm run dev
open http://localhost:3000
```

Edit `web/app/page.tsx` to:
- Replace `DOWNLOAD_URL` with the eventual GitHub Releases URL of your DMG.
- Replace both `YOUR_USER` placeholders with your GitHub username.

### 3b. Deploy to Vercel

GitHub Student Pack gets you Vercel Pro free — claim at [education.github.com/pack](https://education.github.com/pack) → Vercel.

```bash
cd /Users/natelevy/Projects/Cadence/web
npx vercel              # first time: log in, link the project
npx vercel --prod
```

### 3c. Custom domain (only if you grabbed `cadence.me`)

If you claimed a `.me` domain via Namecheap (Student Pack):

1. Namecheap dashboard → Domain List → `cadence.me` → **Manage** → **Advanced DNS**
2. Add CNAME: `Host: @`  `Value: cname.vercel-dns.com`
3. Vercel → project → Settings → Domains → Add `cadence.me` and `www.cadence.me`
4. Vercel auto-issues a TLS cert in ~60 seconds

The `api.cadence.me` for the Cloudflare Worker is configured separately (Cloudflare → Workers → cadence-api → Triggers → Custom Domains). For now leave the app on the `workers.dev` URL.

---

## 4. Support email (≈ 5 min)

**What's already done**
- Menu bar popover: **Send feedback…** opens a mailto with version + macOS pre-filled.
- Settings → General → **Support & updates** card has both Send feedback and Check now.
- Onboarding's final screen mentions `support@cadence.me`.

**What you need to do — only once you own a domain**

### 4a. Email forwarding (Namecheap)

Namecheap → Domain List → `cadence.me` → **Manage** → **Domain** tab → scroll to **Redirect Email** → add:

- `support@cadence.me` → forwards to your inbox

Cost: free. Propagation: ~10 minutes.

Until your domain is live, replace `support@cadence.me` in two places with whatever email you want:

1. `Cadence/UI/MenuBar/MenuBarController.swift` — `sendFeedback()` function
2. `Cadence/UI/Settings/SettingsWindowController.swift` — "Support & updates" card

---

## 5. Onboarding audit (≈ 20 min)

**What's already done**
- Tightened the Welcome step and Done step copy.
- Done step now points users to the menu-bar icon for Settings/history/feedback.

**What you need to do**

1. Open the app, menu bar → **Settings → Developer → Reset onboarding**.
2. Quit (Cmd+Q), reopen. The 11-step flow runs.
3. **Write down every moment of confusion**. Specifically:
   - Were permissions prompts clear about *why*?
   - Did you understand what the "push-to-talk key" was?
   - Did "routing" make sense without explanation?
   - Did anything take more than 2 reads?

4. For each confusion point, tighten the `subtitle:` string in `Cadence/UI/Onboarding/OnboardingFlowView.swift`.

5. Have a friend who hasn't seen Cadence sit at your Mac with a fresh user account or VM and go through it. Watch silently. Note every pause.

---

## Email sign-in (magic link) — Supabase redirect URLs

The email link opens in your **browser** first, then hands off to the Cadence app. Both must be configured.

### 1. Supabase dashboard (one-time, ~2 min)

1. Open [Supabase](https://supabase.com/dashboard) → your Cadence project.
2. **Authentication** → **URL Configuration**.
3. Set **Site URL** to your local dev server (while developing):
   - `http://localhost:3000`  
   (Use `:3001` only if that's the port `npm run dev` prints.)
4. Under **Redirect URLs**, add **all** of these (one per line):
   - `http://localhost:3000/auth/callback`
   - `http://localhost:3001/auth/callback`
   - `cadence://auth/callback`
   - `https://web-six-xi-79.vercel.app/auth/callback` (or your production domain when you have one)
5. Click **Save**.

### 2. Cadence app config

In `Cadence/Resources/CloudConfig.plist`, `AuthRedirectURL` must match the port your Next dev server uses:

```xml
<key>AuthRedirectURL</key>
<string>http://localhost:3000/auth/callback</string>
```

After editing, rebuild/reinstall the app (or copy the plist into `/Applications/Cadence.app/Contents/Resources/`).

### 3. Local dev server must be running

```bash
cd web && npm run dev
```

Leave it running while you test sign-in. The magic link lands on `/auth/callback`, which forwards tokens to `cadence://` and opens Cadence.

### 4. Test flow

1. Cadence running (menu bar icon visible).
2. Sign in → enter email → **Send sign-in link**.
3. Open the email → click the link.
4. Browser shows “Opening Cadence…” → app activates → Settings shows your email (not “Guest session”).

---

## Quick reference: where each file lives

| Feature | Path |
|---------|------|
| Sparkle wiring | `Cadence/Services/UpdaterService.swift` |
| Sentry wiring | `Cadence/Services/CrashReporter.swift` |
| Sparkle Info.plist keys | `project.yml` (regenerate after edits) |
| Cloud config (DSN, Supabase URL, API URL, auth redirect) | `Cadence/Resources/CloudConfig.plist` |
| Email sign-in web bridge | `web/app/auth/callback/page.tsx` |
| Appcast template | `web/public/appcast.xml` |
| Landing page | `web/app/page.tsx` |
| Support email + Check Updates UI | `MenuBarController.swift`, `SettingsWindowController.swift` |
| Onboarding | `Cadence/UI/Onboarding/OnboardingFlowView.swift` |

---

## Done checklist

- [ ] Sparkle EdDSA key generated and backed up to 1Password
- [ ] Public key pasted into `project.yml`, `xcodegen generate` re-run
- [ ] Sentry project created, DSN in `CloudConfig.plist`
- [ ] First test event visible in Sentry dashboard
- [ ] Landing page renders locally
- [ ] Landing page deployed to Vercel (preview URL works)
- [ ] Custom domain attached (if you have one)
- [ ] `support@…` forwarding set up
- [ ] Onboarding walked through with a friend — top 3 friction points fixed

Once those are checked, you're ready for security audit + first 10 friends → notarized DMG → public launch.
