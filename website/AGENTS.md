# Notes for contributors and agents

- Static site, no server code. Edit texts in `src/content/{en,ru}.ts`, settings in `src/config/site.ts`.
- Pages are pre-rendered by `scripts/prerender.mjs`; every route must be in `src/lib/routes.ts`.
- Do not add trackers, third-party fonts/CDNs or runtime requests: `src/test/dist.test.ts` fails on them.
- Do not invent legal facts (operator, address, e-mail, retention): leave the field empty in `site.ts`.
- Images are the game's own (`assets/`); regenerate derived ones with `scripts/make_icons.py`.
- Before committing: `npm run build && npm run lint && npm test`.
