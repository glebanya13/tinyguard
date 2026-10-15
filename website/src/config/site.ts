/**
 * Central configuration of the Bimbleguard website: the single place the owner edits.
 * Empty values mean "not configured": related blocks, buttons and lines are hidden
 * instead of rendered broken, and `npm run build` lists what is still missing.
 */
export type Locale = "ru" | "en";

export interface Localized {
  ru: string;
  en: string;
}

export interface SiteConfig {
  brand: { name: string; shortName: string };
  /** Short store description (80 characters or less in Google Play). */
  tagline: Localized;
  /** Meta description of the pages. */
  description: Localized;
  defaultLocale: Locale;
  locales: Locale[];
  /** Public https origin plus sub-path, no trailing slash. Example: "https://example.org/bimbleguard". */
  siteUrl: string;
  /** Google Play listing URL. Empty: the button is hidden and "Coming soon" is shown. */
  playUrl: string;
  contacts: { email: string };
  /** Third-party analytics. Empty = none (default). The game itself has no analytics either. */
  analytics: { gaId: string };
  privacy: {
    /** Who operates the game and its online services (person or company). */
    operatorName: string;
    /** Date of the current text of the privacy policy (YYYY-MM-DD), from docs/PRIVACY.md. */
    version: string;
    /** The owner has reviewed the policy text and confirms it. Build warns while false. */
    reviewed: boolean;
    /** Optional retention policy for inactive accounts (docs/PRIVACY.md leaves it to the owner). */
    inactiveRetentionNote: Localized;
  };
  deletion: {
    /** Optional: how fast e-mail deletion requests are handled. Do not invent: leave empty if unknown. */
    responseNote: Localized;
  };
}

export const site: SiteConfig = {
  brand: { name: "Bimbleguard", shortName: "Bimbleguard" },
  tagline: {
    ru: "Защити замок: ставь башни, веди героя, выстой в осаде. Без рекламы.",
    en: "Defend the castle: build towers, lead your hero, survive the siege. No ads.",
  },
  description: {
    ru: "Bimbleguard: лёгкая 3D-защита башнями в мультяшном стиле для телефона. Строй башни, веди героя, выстой в осаде. Без рекламы, работает без интернета.",
    en: "Bimbleguard is a light, cartoon-style 3D tower defense made for phones. Build towers, lead your hero, survive the siege. No ads, works offline.",
  },
  defaultLocale: "en",
  locales: ["en", "ru"],
  siteUrl: "", // e.g. "https://example.org" or "https://user.github.io/bimbleguard"
  playUrl: "", // e.g. "https://play.google.com/store/apps/details?id=..."
  contacts: { email: "" },
  analytics: { gaId: "" },
  privacy: {
    operatorName: "",
    version: "2026-10-14",
    reviewed: false,
    inactiveRetentionNote: { ru: "", en: "" },
  },
  deletion: { responseNote: { ru: "", en: "" } },
};

export const hasValue = (v: string | undefined | null): v is string => !!v && v.trim().length > 0;

/** Effective site URL: the SITE_URL build variable (CI) wins over the value above. */
export function resolveSiteUrl(override?: string): string {
  const raw = hasValue(override) ? override : site.siteUrl;
  return raw.trim().replace(/\/+$/, "");
}

/** Missing values the owner must fill in before publishing. Used by the build and the tests. */
export function missingOwnerValues(
  cfg: SiteConfig = site,
  siteUrl: string = cfg.siteUrl,
): string[] {
  const out: string[] = [];
  if (!hasValue(cfg.contacts.email))
    out.push("contacts.email: e-mail для связи и запросов на удаление");
  if (!hasValue(cfg.privacy.operatorName))
    out.push("privacy.operatorName: оператор (имя или организация)");
  if (!cfg.privacy.reviewed)
    out.push("privacy.reviewed: проверьте текст политики и поставьте true");
  if (!hasValue(siteUrl))
    out.push("siteUrl: публичный адрес сайта (canonical, hreflang, sitemap, og:image)");
  if (!hasValue(cfg.playUrl)) out.push("playUrl: ссылка Google Play (до публикации кнопка скрыта)");
  return out;
}
