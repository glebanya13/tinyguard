import { useEffect, useRef, useState } from "react";
import { Menu, X } from "lucide-react";
import { site, hasValue, type Locale } from "@/config/site";
import { getContent } from "@/content";
import { mirrorPath, pathFor, withBase, type RouteInfo } from "@/lib/routes";
import { cn } from "@/lib/utils";

export function Logo({ locale, size = 48 }: { locale: Locale; size?: number }) {
  const c = getContent(locale);
  return (
    <a
      href={withBase(pathFor("home", locale))}
      className="flex items-center gap-3"
      aria-label={c.ui.homeAria}
    >
      <img
        src={withBase("/img/logo-96.webp")}
        alt=""
        width={size}
        height={size}
        className="rounded-xl border-[3px] border-navy"
        style={{ width: size, height: size }}
      />
      <span className="font-display text-2xl font-bold text-navy sm:text-3xl">
        {site.brand.name}
      </span>
    </a>
  );
}

export function Header({ route }: { route: RouteInfo }) {
  const locale = route.locale;
  const c = getContent(locale);
  const [open, setOpen] = useState(false);
  const btn = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        btn.current?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  const links = [
    { key: "home", label: c.ui.navHome },
    { key: "about", label: c.ui.navAbout },
    { key: "privacy", label: c.ui.navPrivacy },
    { key: "contact", label: c.ui.navContact },
  ] as const;
  const linkCls = (key: string) =>
    cn(
      "rounded-full px-3 py-2 text-base font-bold text-navy hover:text-purple",
      route.key === key && "underline decoration-[3px] underline-offset-8",
    );
  const soon = hasValue(site.playUrl) ? (
    <a
      href={site.playUrl}
      target="_blank"
      rel="noopener noreferrer"
      className="btn btn-orange min-h-11 px-5 text-base"
    >
      {c.ui.getOnPlay}
    </a>
  ) : (
    <span className="btn btn-soon min-h-11 px-5 text-base">{c.ui.comingSoon}</span>
  );
  const other = locale === "en" ? "ru" : "en";

  return (
    <header className="relative z-50 border-b-[3px] border-navy bg-cream">
      <div className="container-site flex items-center justify-between gap-4 py-3">
        <Logo locale={locale} />
        <nav aria-label={c.ui.mainNav} className="hidden items-center gap-1 lg:flex">
          {links.map((l) => (
            <a
              key={l.key}
              href={withBase(pathFor(l.key, locale))}
              className={linkCls(l.key)}
              aria-current={route.key === l.key ? "page" : undefined}
            >
              {l.label}
            </a>
          ))}
          <a
            href={withBase(mirrorPath(route))}
            lang={other}
            hrefLang={other}
            aria-label={`${c.ui.langSwitchLabel}: ${c.ui.langOtherName}`}
            className="rounded-full px-3 py-2 text-base font-bold text-navy hover:text-purple"
          >
            {c.ui.langOther}
          </a>
          <span className="ml-2">{soon}</span>
        </nav>
        <button
          ref={btn}
          type="button"
          className="grid size-12 place-items-center rounded-full border-[3px] border-navy bg-white text-navy lg:hidden"
          aria-expanded={open}
          aria-controls="mobile-menu"
          aria-label={open ? c.ui.closeMenu : c.ui.menu}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? <X className="size-6" aria-hidden /> : <Menu className="size-6" aria-hidden />}
        </button>
      </div>
      {open && (
        <nav
          id="mobile-menu"
          aria-label={c.ui.mobileNav}
          className="container-site flex flex-col gap-1 border-t-2 border-line pb-6 pt-3 lg:hidden"
        >
          {links.map((l) => (
            <a
              key={l.key}
              href={withBase(pathFor(l.key, locale))}
              className="rounded-xl px-2 py-3 text-xl font-bold"
            >
              {l.label}
            </a>
          ))}
          <a
            href={withBase(mirrorPath(route))}
            lang={other}
            hrefLang={other}
            className="rounded-xl px-2 py-3 text-xl font-bold"
          >
            {c.ui.langOtherName}
          </a>
          <div className="mt-3">{soon}</div>
        </nav>
      )}
    </header>
  );
}
