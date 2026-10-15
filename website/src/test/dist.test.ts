// @vitest-environment node
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { allRoutes } from "@/lib/routes";

const root = path.resolve(import.meta.dirname, "../..");
const dist = path.join(root, "dist");
const read = (p: string): string => fs.readFileSync(path.join(dist, p), "utf8");
const walk = (dir: string): string[] =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : [p];
  });

beforeAll(() => {
  execSync("npm run build", {
    cwd: root,
    env: { ...process.env, SITE_URL: "https://example.test/g" },
    stdio: "pipe",
  });
}, 180_000);

describe("static build", () => {
  it("pre-renders every route with visible content and the right language", () => {
    for (const r of allRoutes()) {
      const html = read(path.join(r.path, "index.html"));
      expect(html, r.path).toContain(`<html lang="${r.locale}"`);
      expect(html, r.path).toMatch(/<h1[^>]*>[^<]+<\/h1>/);
      expect(html, r.path).toContain("<title>");
      expect(html, r.path).toContain(`rel="canonical" href="https://example.test/g${r.path}"`);
      expect(html, r.path).toContain('hreflang="en"');
      expect(html, r.path).toContain('hreflang="ru"');
    }
    expect(read("404.html")).toContain('content="noindex"');
  });

  it("pre-renders the screenshot slider with phone frames", () => {
    for (const f of ["index.html", "ru/index.html", "about/index.html"]) {
      const html = read(f);
      expect(html, f).toContain('aria-roledescription="carousel"');
      expect(html.match(/aria-roledescription="slide"/g), f).toHaveLength(8);
      expect(html, f).toContain("1 / 8");
    }
  });

  it("writes sitemap.xml, robots.txt and .nojekyll", () => {
    const sm = read("sitemap.xml");
    for (const r of allRoutes()) expect(sm).toContain(`<loc>https://example.test/g${r.path}</loc>`);
    expect(read("robots.txt")).toContain("Sitemap: https://example.test/g/sitemap.xml");
    expect(fs.existsSync(path.join(dist, ".nojekyll"))).toBe(true);
    expect(fs.existsSync(path.join(dist, "CNAME"))).toBe(false);
  });

  it("has no forbidden words in dist, sources or docs", () => {
    const bad = /lovable|supabase|tashkent|ташкент|studio|студи/i;
    const files = [
      ...walk(dist).filter((f) => /\.(html|js|css|xml|txt)$/.test(f)),
      ...walk(path.join(root, "src")).filter((f) => !f.includes(`${path.sep}test${path.sep}`)),
      path.join(root, "README.md"),
      path.join(root, "AGENTS.md"),
      path.join(root, "package.json"),
    ];
    for (const f of files) expect(fs.readFileSync(f, "utf8"), f).not.toMatch(bad);
  });

  it("makes no requests to other hosts (only <a> links may point outside)", () => {
    for (const f of walk(dist).filter((f) => f.endsWith(".html"))) {
      const html = fs.readFileSync(f, "utf8").replace(/<a\b[^>]*>/g, "");
      // canonical/alternate links and og:url are never fetched, so they are allowed.
      const links = [...html.matchAll(/<(?:script|img|iframe|source|video)\b[^>]*>|<link\b[^>]*>/g)]
        .map((m) => m[0])
        .filter(
          (t) => /(?:src|href)="(https?:)?\/\//.test(t) && !/rel="(canonical|alternate)"/.test(t),
        );
      expect(links, f).toEqual([]);
    }
    for (const f of walk(dist).filter((f) => f.endsWith(".css"))) {
      expect(fs.readFileSync(f, "utf8"), f).not.toMatch(/url\(\s*["']?https?:/);
    }
  });

  it("keeps secrets out of the website folder", () => {
    expect(fs.existsSync(path.join(root, ".env"))).toBe(false);
  });
});
