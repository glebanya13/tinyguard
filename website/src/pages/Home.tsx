import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import { pathFor, withBase } from "@/lib/routes";
import { Gallery } from "@/components/site/Gallery";
import { PlayButton } from "@/components/site/ui";

export function Home({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  return (
    <>
      <section className="relative isolate flex min-h-[calc(100vh-5rem)] items-center overflow-hidden bg-navy text-white">
        <img
          src={withBase("/img/hero.jpg")}
          alt=""
          width={1920}
          height={1080}
          fetchPriority="high"
          className="absolute inset-0 -z-20 h-full w-full object-cover"
        />
        <div
          className="absolute inset-0 -z-10 bg-gradient-to-r from-navy/90 via-navy/55 to-transparent"
          aria-hidden
        />
        <div className="container-site py-16 md:py-24">
          <p className="text-eyebrow inline-block rounded-full border-[3px] border-navy bg-purple px-4 py-2 text-white">
            {c.home.badge}
          </p>
          <h1 className="text-hero mt-5">{c.home.title}</h1>
          <p className="mt-6 max-w-xl text-xl font-semibold leading-relaxed md:text-2xl">
            {c.home.lead}
          </p>
          <div className="mt-9 flex flex-wrap gap-4">
            <PlayButton locale={locale} />
            <a href={withBase(pathFor("privacy", locale))} className="btn btn-white">
              {c.ui.navPrivacy}
            </a>
          </div>
          <p className="mt-8 flex items-center gap-2 font-bold">
            <span className="size-3 rounded-full bg-green" aria-hidden /> {c.ui.madeFor}
          </p>
        </div>
      </section>
      <section className="sky-gradient section-y">
        <div className="container-site">
          <div className="mx-auto mb-12 max-w-3xl text-center">
            <h2 className="text-h2">{c.home.introTitle}</h2>
            <p className="mt-6 text-lg leading-relaxed text-body md:text-xl">{c.home.introText}</p>
          </div>
          <Gallery locale={locale} />
        </div>
      </section>
    </>
  );
}
