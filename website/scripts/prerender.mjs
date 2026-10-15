// Pre-renders every page into dist/<path>/index.html (plus 404.html, sitemap.xml, robots.txt).
// Run by `npm run build` after the client and SSR builds. No server is needed to host the result.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(import.meta.dirname, "..");
const dist = path.join(root, "dist");
const ssrDir = path.join(root, "dist-ssr");

const mod = await import(pathToFileURL(path.join(ssrDir, "entry-server.js")).href);
const { routes, notFoundRoute, headTags, render, missingOwnerValues, resolveSiteUrl } = mod;

const template = fs.readFileSync(path.join(dist, "index.html"), "utf8");
if (!template.includes("<!--app-head-->") || !template.includes("<!--app-html-->")) {
  throw new Error("dist/index.html lost its <!--app-head--> / <!--app-html--> markers");
}
const siteUrl = resolveSiteUrl(process.env.SITE_URL);

function page(route) {
  return template
    .replace(/<html lang="[^"]*"/, `<html lang="${route.locale}"`)
    .replace("<!--app-head-->", () => headTags(route, siteUrl))
    .replace("<!--app-html-->", () => render(route));
}

for (const route of routes) {
  const dir = path.join(dist, route.path);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "index.html"), page(route));
}
fs.writeFileSync(path.join(dist, "404.html"), page(notFoundRoute("en")));

// sitemap.xml and robots.txt (absolute URLs need the site URL).
const abs = (p) => `${siteUrl}${p}`;
const sitemap = siteUrl
  ? routes
      .map((r) => {
        const alts = routes
          .filter((x) => x.key === r.key)
          .map(
            (x) => `    <xhtml:link rel="alternate" hreflang="${x.locale}" href="${abs(x.path)}"/>`,
          )
          .join("\n");
        return `  <url>\n    <loc>${abs(r.path)}</loc>\n${alts}\n  </url>`;
      })
      .join("\n")
  : "  <!-- siteUrl is not configured: set it in src/config/site.ts or SITE_URL to list pages here -->";
fs.writeFileSync(
  path.join(dist, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${sitemap}\n</urlset>\n`,
);
fs.writeFileSync(
  path.join(dist, "robots.txt"),
  `User-agent: *\nAllow: /\n${siteUrl ? `\nSitemap: ${abs("/sitemap.xml")}\n` : ""}`,
);
fs.writeFileSync(path.join(dist, ".nojekyll"), "");

fs.rmSync(ssrDir, { recursive: true, force: true });

const missing = missingOwnerValues(undefined, siteUrl);
console.log(`prerendered ${routes.length} pages + 404.html into dist/`);
if (missing.length) {
  console.log("\nOWNER TODO (src/config/site.ts), hidden on the site until filled:");
  for (const m of missing) console.log(`  - ${m}`);
}
