import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

/**
 * Fully static output: `vite build` produces the client bundle, a second SSR build produces the
 * renderer, and `scripts/prerender.mjs` writes one index.html per page into dist/.
 * SITE_BASE sets the public sub-path (for example "/bimbleguard/" for GitHub Pages).
 */
function normalizeBase(raw: string | undefined): string {
  let b = (raw ?? "/").trim();
  if (!b.startsWith("/")) b = `/${b}`;
  if (!b.endsWith("/")) b = `${b}/`;
  return b;
}

export default defineConfig({
  base: normalizeBase(process.env["SITE_BASE"]),
  define: { __BUILD_YEAR__: JSON.stringify(String(new Date().getFullYear())) },
  plugins: [react(), tailwindcss()],
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  build: { target: "es2022", sourcemap: false },
});
