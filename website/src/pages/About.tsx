import {
  Axe,
  Castle,
  Coins,
  Hammer,
  Hourglass,
  Languages,
  Map as MapIcon,
  Route,
  ShieldCheck,
  Star,
  Swords,
  Trophy,
  Users,
  WifiOff,
  type LucideIcon,
} from "lucide-react";
import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import type { IconName } from "@/content/types";
import { ScreenshotSlider } from "@/components/site/ScreenshotSlider";
import { FaqList, PageHero, SectionHead } from "@/components/site/ui";

const ICONS: Record<IconName, LucideIcon> = {
  map: MapIcon,
  route: Route,
  swords: Swords,
  castle: Castle,
  hourglass: Hourglass,
  trophy: Trophy,
  users: Users,
  wifiOff: WifiOff,
  languages: Languages,
  star: Star,
  axe: Axe,
  coins: Coins,
  hammer: Hammer,
  shieldCheck: ShieldCheck,
};

export function About({ locale }: { locale: Locale }) {
  const a = getContent(locale).about;
  return (
    <>
      <PageHero eyebrow={a.eyebrow} title={a.title} lead={a.lead} />
      <section className="section-y" aria-labelledby="features-h">
        <div className="container-site">
          <SectionHead id="features-h" title={a.features.title} lead={a.features.lead} />
          <ul className="grid gap-7 sm:grid-cols-2 lg:grid-cols-3">
            {a.features.items.map((f) => {
              const Icon = ICONS[f.icon];
              return (
                <li key={f.title} className="card-step p-6">
                  <span className="grid size-12 place-items-center rounded-2xl border-[3px] border-navy bg-sky">
                    <Icon className="size-6" aria-hidden />
                  </span>
                  <h3 className="text-h3 mt-4">{f.title}</h3>
                  <p className="mt-2 leading-relaxed text-body">{f.text}</p>
                </li>
              );
            })}
          </ul>
        </div>
      </section>
      <section className="sky-gradient section-y" aria-labelledby="towers-h">
        <div className="container-site">
          <SectionHead id="towers-h" title={a.towers.title} lead={a.towers.lead} />
          <ul className="grid gap-7 sm:grid-cols-2 lg:grid-cols-4">
            {a.towers.items.map((t) => (
              <li key={t.name} className="card-step p-6">
                <h3 className="text-h3">{t.name}</h3>
                <p className="mt-2 leading-relaxed text-body">{t.role}</p>
                <p className="mt-4 text-sm font-extrabold">
                  {a.towers.costLabel}: {t.cost}
                </p>
              </li>
            ))}
          </ul>
        </div>
      </section>
      <section className="section-y" aria-labelledby="how-h">
        <div className="container-site">
          <SectionHead id="how-h" title={a.how.title} lead={a.how.lead} />
          <ol className="grid gap-7 md:grid-cols-2">
            {a.how.steps.map((s, i) => (
              <li key={s.title} className="card-step flex gap-4 p-6">
                <span
                  className="grid size-11 shrink-0 place-items-center rounded-full border-[3px] border-navy bg-orange font-display text-xl text-white"
                  aria-hidden
                >
                  {i + 1}
                </span>
                <div>
                  <h3 className="text-h3">{s.title}</h3>
                  <p className="mt-2 leading-relaxed text-body">{s.text}</p>
                </div>
              </li>
            ))}
          </ol>
          <p className="mt-8 max-w-3xl text-body">{a.how.controls}</p>
        </div>
      </section>
      <section className="sky-gradient section-y" aria-labelledby="shots-h">
        <div className="container-site">
          <SectionHead id="shots-h" title={a.gallery.title} lead={a.gallery.lead} />
        </div>
        <div className="mx-auto max-w-[1280px]">
          <ScreenshotSlider locale={locale} />
        </div>
      </section>
      <section className="section-y" aria-labelledby="faq-h">
        <div className="container-site max-w-4xl">
          <SectionHead id="faq-h" title={a.faq.title} lead={a.faq.lead} />
          <FaqList items={a.faq.items} locale={locale} />
        </div>
      </section>
    </>
  );
}
