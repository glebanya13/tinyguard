import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import { pathFor, withBase } from "@/lib/routes";
import { ScreenshotSlider } from "@/components/site/ScreenshotSlider";
import { PhoneFrame } from "@/components/site/PhoneFrame";
import { PlayButton } from "@/components/site/ui";

export function Home({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  return (
    <>
      <section className="relative isolate flex items-center overflow-hidden bg-navy text-white lg:min-h-[min(calc(100svh-5rem),860px)]">
        <img
          src={withBase("/img/hero.jpg")}
          alt=""
          width={1920}
          height={1080}
          fetchPriority="high"
          className="absolute inset-0 -z-20 h-full w-full object-cover"
        />
        <div
          className="absolute inset-0 -z-10 bg-gradient-to-r from-navy/85 via-navy/45 to-transparent"
          aria-hidden
        />
        <div className="container-site grid items-center gap-12 py-14 lg:grid-cols-[1.05fr_1fr] lg:py-16">
          <div>
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
          <div className="relative mx-auto w-full max-w-xl pb-6 lg:max-w-none">
            <img
              src={withBase("/img/logo-720.webp")}
              alt={c.home.artAlt}
              width={720}
              height={720}
              className="absolute -bottom-6 -left-2 w-[46%] rotate-6 rounded-[2rem] border-[3px] border-navy sm:-left-6 lg:-bottom-10 lg:-left-10"
            />
            <div className="hero-phone relative ml-[14%] sm:ml-[18%]">
              <PhoneFrame>
                <img
                  src={withBase(
                    `/img/${c.about.gallery.shots[1]?.file ?? "shot_02_level_1_valley"}.webp`,
                  )}
                  alt={c.about.gallery.shots[1]?.alt ?? ""}
                  width={1280}
                  height={720}
                  fetchPriority="high"
                  className="absolute inset-0 h-full w-full object-cover"
                />
              </PhoneFrame>
            </div>
          </div>
        </div>
      </section>
      <section className="sky-gradient section-y">
        <div className="container-site">
          <div className="mx-auto mb-12 max-w-3xl text-center">
            <h2 className="text-h2">{c.home.introTitle}</h2>
            <p className="mt-6 text-lg leading-relaxed text-body md:text-xl">{c.home.introText}</p>
          </div>
        </div>
        <div className="mx-auto max-w-[1280px]">
          <ScreenshotSlider locale={locale} />
        </div>
      </section>
    </>
  );
}
