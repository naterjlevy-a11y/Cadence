# Mellotron landing page

Next.js 14 + Tailwind. One-page hero with download button, three-step flow, feature grid, support email footer.

```bash
cd web
npm install
npm run dev          # http://localhost:3000
```

Deploy:

```bash
npx vercel              # link project (first time)
npx vercel --prod
```

Files:

- `app/page.tsx` — the entire site
- `app/layout.tsx` — `<head>` + global CSS
- `public/appcast.xml` — Sparkle update feed (also served at `mellotron.me/appcast.xml`)
- `tailwind.config.ts` — colour palette

Swap these tokens:

- `DOWNLOAD_URL` in `app/page.tsx` → your DMG URL
- `YOUR_USER` placeholder → your GitHub username
