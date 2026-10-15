import { useCallback, useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import { withBase } from "@/lib/routes";
import { cn } from "@/lib/utils";
import { PhoneFrame } from "./PhoneFrame";

const arrow =
  "grid size-14 shrink-0 place-items-center rounded-full border-[3px] border-navy bg-white text-navy disabled:opacity-40";

/** Scroll-snap carousel of screenshots in phone frames. Works without JS (plain horizontal scroll). */
export function ScreenshotSlider({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  const shots = c.about.gallery.shots;
  const track = useRef<HTMLUListElement>(null);
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(false);

  const goTo = useCallback((i: number) => {
    const el = track.current;
    const li = el?.children[i] as HTMLElement | undefined;
    if (!el || !li) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    el.scrollTo({
      left: li.offsetLeft - (el.clientWidth - li.clientWidth) / 2,
      behavior: reduce ? "auto" : "smooth",
    });
    setActive(i);
  }, []);

  const onScroll = useCallback(() => {
    const el = track.current;
    if (!el) return;
    const mid = el.scrollLeft + el.clientWidth / 2;
    let best = 0;
    let dist = Infinity;
    Array.from(el.children).forEach((n, i) => {
      const li = n as HTMLElement;
      const d = Math.abs(li.offsetLeft + li.clientWidth / 2 - mid);
      if (d < dist) {
        dist = d;
        best = i;
      }
    });
    setActive(best);
  }, []);

  useEffect(() => {
    if (!zoom) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setZoom(false);
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [zoom]);

  const cur = shots[active] ?? shots[0];
  if (!cur) return null;

  return (
    <section role="region" aria-roledescription="carousel" aria-label={c.ui.carousel}>
      <div className="relative">
        <button
          type="button"
          className={cn(arrow, "absolute left-2 top-1/2 z-10 -translate-y-1/2")}
          aria-label={c.ui.prev}
          disabled={active === 0}
          onClick={() => goTo(active - 1)}
        >
          <ChevronLeft className="size-7" aria-hidden />
        </button>
        <button
          type="button"
          className={cn(arrow, "absolute right-2 top-1/2 z-10 -translate-y-1/2")}
          aria-label={c.ui.next}
          disabled={active === shots.length - 1}
          onClick={() => goTo(active + 1)}
        >
          <ChevronRight className="size-7" aria-hidden />
        </button>
        <ul
          ref={track}
          tabIndex={0}
          onScroll={onScroll}
          onKeyDown={(e) => {
            if (e.key === "ArrowRight") {
              e.preventDefault();
              goTo(Math.min(active + 1, shots.length - 1));
            } else if (e.key === "ArrowLeft") {
              e.preventDefault();
              goTo(Math.max(active - 1, 0));
            }
          }}
          className="slider-track flex snap-x snap-mandatory items-center gap-3 overflow-x-auto py-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          {shots.map((s, i) => (
            <li
              key={s.file}
              role="group"
              aria-roledescription="slide"
              aria-label={`${i + 1} / ${shots.length}`}
              className={cn(
                "slider-item shrink-0 snap-center transition-[transform,opacity] duration-300",
                i === active ? "scale-100 opacity-100" : "scale-[0.8] opacity-60",
              )}
            >
              <button
                type="button"
                className={cn("block w-full", i === active ? "cursor-zoom-in" : "cursor-pointer")}
                aria-label={i === active ? `${c.ui.openShot}: ${s.alt}` : `${c.ui.goTo} ${i + 1}`}
                onClick={() => (i === active ? setZoom(true) : goTo(i))}
              >
                <PhoneFrame>
                  <img
                    src={withBase(`/img/${s.file}.webp`)}
                    alt={s.alt}
                    width={1280}
                    height={720}
                    loading={i < 2 ? "eager" : "lazy"}
                    decoding="async"
                    className="absolute inset-0 h-full w-full object-cover"
                  />
                </PhoneFrame>
              </button>
            </li>
          ))}
        </ul>
      </div>
      <div className="mt-2 min-w-40 text-center">
        <p className="font-display text-xl font-semibold">{cur.caption}</p>
        <p aria-live="polite" className="mt-1 text-sm font-bold text-body">
          {active + 1} / {shots.length}
        </p>
      </div>
      <div className="mt-5 flex justify-center gap-2">
        {shots.map((s, i) => (
          <button
            key={s.file}
            type="button"
            aria-label={`${c.ui.goTo} ${i + 1}`}
            aria-current={i === active ? "true" : undefined}
            onClick={() => goTo(i)}
            className="grid size-6 place-items-center"
          >
            <span
              className={cn(
                "block rounded-full border-2 border-navy transition-all",
                i === active ? "h-3 w-7 bg-navy" : "size-3 bg-white",
              )}
            />
          </button>
        ))}
      </div>
      {zoom && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={cur.alt}
          className="fixed inset-0 z-[60] grid place-items-center bg-navy/90 p-4"
          onClick={() => setZoom(false)}
        >
          <button
            type="button"
            aria-label={c.ui.close}
            className={cn(arrow, "absolute right-4 top-4")}
            onClick={() => setZoom(false)}
          >
            <X className="size-6" aria-hidden />
          </button>
          <img
            src={withBase(`/img/${cur.file}.webp`)}
            alt={cur.alt}
            width={1280}
            height={720}
            className="max-h-[88vh] w-auto max-w-full rounded-2xl border-[3px] border-white"
          />
        </div>
      )}
    </section>
  );
}
