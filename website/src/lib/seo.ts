import { hasValue, resolveSiteUrl, site } from "@/config/site";
import { getContent } from "@/content";
import { allRoutes, pathFor, withBase, type RouteInfo } from "./routes";

const esc = (s: string): string =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function pageMeta(route: RouteInfo): { title: string; description: string } {
  const m = getContent(route.locale).meta;
  return m[route.key];
}

/** Absolute URL of a page, or "" while the site URL is not configured. */
export function absoluteUrl(path: string, siteUrl: string): string {
  if (!hasValue(siteUrl)) return "";
  return `${siteUrl.replace(/\/+$/, "")}${path}`;
}

/** The tags placed inside <head> of a pre-rendered page (no tracking, no third-party hosts). */
export function headTags(route: RouteInfo, siteUrlOverride?: string): string {
  const siteUrl = resolveSiteUrl(siteUrlOverride);
  const c = getContent(route.locale);
  const { title, description } = pageMeta(route);
  const tags: string[] = [
    `<title>${esc(title)}</title>`,
    `<meta name="description" content="${esc(description)}" />`,
    `<meta name="theme-color" content="#fffdf3" />`,
    `<link rel="icon" href="${withBase("/favicon.ico")}" sizes="any" />`,
    `<link rel="apple-touch-icon" href="${withBase("/apple-touch-icon.png")}" />`,
  ];
  if (route.key === "notFound") {
    tags.push(`<meta name="robots" content="noindex" />`);
    return tags.join("\n    ");
  }
  const url = absoluteUrl(route.path, siteUrl);
  if (url) tags.push(`<link rel="canonical" href="${esc(url)}" />`);
  if (url) {
    for (const r of allRoutes().filter((x) => x.key === route.key)) {
      tags.push(
        `<link rel="alternate" hreflang="${r.locale}" href="${esc(absoluteUrl(r.path, siteUrl))}" />`,
      );
    }
    tags.push(
      `<link rel="alternate" hreflang="x-default" href="${esc(absoluteUrl(pathFor(route.key, site.defaultLocale), siteUrl))}" />`,
    );
  }
  const image = absoluteUrl("/og-image.png", siteUrl);
  tags.push(
    `<meta property="og:type" content="website" />`,
    `<meta property="og:site_name" content="${esc(site.brand.name)}" />`,
    `<meta property="og:title" content="${esc(title)}" />`,
    `<meta property="og:description" content="${esc(description)}" />`,
    `<meta property="og:locale" content="${c.ogLocale}" />`,
    `<meta name="twitter:card" content="summary_large_image" />`,
  );
  if (url) tags.push(`<meta property="og:url" content="${esc(url)}" />`);
  if (image) {
    tags.push(
      `<meta property="og:image" content="${esc(image)}" />`,
      `<meta property="og:image:width" content="1200" />`,
      `<meta property="og:image:height" content="630" />`,
    );
  }
  return tags.join("\n    ");
}
