import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import { pathFor, withBase } from "@/lib/routes";
import { Logo } from "./Header";

export function Footer({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  const links = [
    { key: "privacy", label: c.ui.navPrivacy },
    { key: "terms", label: c.ui.navTerms },
    { key: "support", label: c.ui.navSupport },
    { key: "deleteAccount", label: locale === "en" ? "Delete account" : "Удаление аккаунта" },
    { key: "contact", label: c.ui.navContact },
  ] as const;
  return (
    <footer className="border-t-[3px] border-navy bg-white">
      <div className="container-site flex flex-col justify-between gap-8 py-10 md:flex-row md:items-center">
        <div>
          <Logo locale={locale} size={44} />
          <p className="mt-3 max-w-md text-body">{c.ui.footerTagline}</p>
        </div>
        <nav aria-label="Footer" className="flex flex-wrap gap-x-7 gap-y-3">
          {links.map((l) => (
            <a
              key={l.key}
              href={withBase(pathFor(l.key, locale))}
              className="font-display text-lg font-semibold hover:text-purple"
            >
              {l.label}
            </a>
          ))}
        </nav>
      </div>
      <p className="border-t border-line py-5 text-center text-sm text-body">
        &copy; {__BUILD_YEAR__} {c.ui.copyright}
      </p>
    </footer>
  );
}
