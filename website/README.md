# Bimbleguard website

Static website of the game (English main, Russian mirror under `/ru/`). React 19 + Vite + Tailwind 4,
pre-rendered to plain HTML: every page has its own `index.html` with content visible without JavaScript.
No server, no database, no forms, no analytics, no third-party requests (fonts are bundled).

This is a separate sub-project: it does not affect the Godot game (`website/.gdignore`).

## Commands

```
cd website
npm install
npm run dev        # dev server
npm run build      # dist/ : static HTML + JS + CSS
npm run preview    # serve dist/ locally
npm run lint       # eslint + tsc
npm test           # vitest (runs a full build, checks routes, forbidden words, external requests)
python3 scripts/make_icons.py   # regenerates icons, og-image and screenshots from ../assets (deterministic)
```

Build variables:

- `SITE_BASE` - public sub-path, default `/` (GitHub Pages project site: `SITE_BASE=/repo-name/ npm run build`).
- `SITE_URL` - public address for canonical/hreflang/sitemap/og:image, overrides `siteUrl` in `site.ts`
  (for example `https://user.github.io/repo-name`, no trailing slash).

## What the owner must fill in (`src/config/site.ts`)

Empty values are hidden on the site; the build prints what is still missing.

| Field | Why |
|---|---|
| `contacts.email` | Contact page and mailto buttons, deletion requests by e-mail, privacy contact |
| `privacy.operatorName` | Operator shown on the privacy policy |
| `privacy.reviewed` | Set `true` after you reviewed `docs/PRIVACY.md` and the site text (terms are a plain template: have them checked) |
| `siteUrl` | Canonical, hreflang, sitemap, og:image (or `SITE_URL` at build) |
| `playUrl` | Google Play link; empty shows "Coming Soon" buttons |
| `privacy.inactiveRetentionNote` | Optional: retention of inactive accounts (`docs/PRIVACY.md` leaves it open) |
| `deletion.responseNote` | Optional: how fast deletion e-mails are handled (not invented) |
| `analytics.gaId` | Empty by default; the site has no trackers |

Then put the final URLs into `GameInfo.PRIVACY_URL` / `DELETION_URL` / `SUPPORT_EMAIL` (`scripts/game_info.gd`)
and Google Play Console: privacy `https://<host>/privacy/`, deletion `https://<host>/delete-account/`.

## Replaceable images (`public/img/`)

- `hero.jpg` - hero background (1920x1080, up to ~250 KB). The default is the blurred game logo art with a navy
  gradient. To replace it, just put your own file at `public/img/hero.jpg` (it is never overwritten by
  `make_icons.py`; delete it and rerun the script to get the default back). A dark gradient on the left keeps the text readable.
- `logo-96.webp`, `logo-720.webp`, `favicon.ico`, `apple-touch-icon.png`, `icon-*.png`, `og-image.png` come from
  `assets/brand/logo.png` and `assets/store/` via `scripts/make_icons.py`.
- `shot_*.webp` - gallery (from `assets/store/shot_*.png`).

## Publishing

The result is `website/dist/`. Pages live at `/`, `/about/`, `/privacy/`, `/terms/`, `/contact/`, `/support/`,
`/delete-account/` and `/ru/...`.

- **GitHub Pages**: build with `SITE_BASE=/<repo>/` (or `/` for a user site / custom domain), publish `dist/`
  (for example with an Actions workflow using `actions/upload-pages-artifact` + `actions/deploy-pages`).
  `404.html` and `.nojekyll` are already included.
- **Cloudflare Pages / Netlify**: build command `npm run build`, root `website`, output `dist`. Node 22+.
- Any static host works. Not yet verified on a real host.
