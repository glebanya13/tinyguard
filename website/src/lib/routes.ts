import { site, type Locale } from "@/config/site";

export type PageKey =
  "home" | "about" | "privacy" | "deleteAccount" | "support" | "contact" | "terms" | "notFound";
export type RealPageKey = Exclude<PageKey, "notFound">;

export interface RouteInfo {
  key: PageKey;
  locale: Locale;
  /** Site-relative path without the base, leading and trailing slash ("/", "/en/privacy/"). */
  path: string;
}

export const PAGES: { key: RealPageKey; slug: string }[] = [
  { key: "home", slug: "" },
  { key: "about", slug: "about" },
  { key: "privacy", slug: "privacy" },
  { key: "deleteAccount", slug: "delete-account" },
  { key: "support", slug: "support" },
  { key: "contact", slug: "contact" },
  { key: "terms", slug: "terms" },
];

const prefix = (locale: Locale): string => (locale === site.defaultLocale ? "" : `/${locale}`);

export function pathFor(key: RealPageKey, locale: Locale): string {
  const slug = PAGES.find((p) => p.key === key)?.slug ?? "";
  return `${prefix(locale)}/${slug ? `${slug}/` : ""}`.replace(/^$/, "/");
}

/** Every real page in every locale (the pre-rendered set, without the 404 page). */
export function allRoutes(): RouteInfo[] {
  return site.locales.flatMap((locale) =>
    PAGES.map((p) => ({ key: p.key, locale, path: pathFor(p.key, locale) })),
  );
}

export function notFoundRoute(locale: Locale = site.defaultLocale): RouteInfo {
  return { key: "notFound", locale, path: "/404.html" };
}

/** Joins the deployment base ("/" or "/sub/") and a site-relative path. */
export function withBase(path: string, base: string = import.meta.env.BASE_URL): string {
  return `${base.replace(/\/+$/, "")}${path.startsWith("/") ? path : `/${path}`}`;
}

/** Maps a browser pathname to a route; unknown paths give the 404 route of the guessed locale. */
export function resolveRoute(pathname: string, base: string = import.meta.env.BASE_URL): RouteInfo {
  const b = base.replace(/\/+$/, "");
  let p = pathname.startsWith(b) ? pathname.slice(b.length) : pathname;
  p = p.replace(/\/index\.html$/, "/");
  if (!p.startsWith("/")) p = `/${p}`;
  if (!p.endsWith("/")) p = `${p}/`;
  const found = allRoutes().find((r) => r.path === p);
  if (found) return found;
  const locale = site.locales.find((l) => l !== site.defaultLocale && p.startsWith(`/${l}/`));
  return notFoundRoute(locale ?? site.defaultLocale);
}

/** The same page in another locale (the language switch target). */
export function otherLocale(route: RouteInfo): Locale {
  return route.locale === "ru" ? "en" : "ru";
}

export function mirrorPath(route: RouteInfo): string {
  const other = otherLocale(route);
  return route.key === "notFound" ? pathFor("home", other) : pathFor(route.key, other);
}

export function localHref(locale: Locale, internalPath: string): string {
  return withBase(`${prefix(locale)}${internalPath}`);
}
