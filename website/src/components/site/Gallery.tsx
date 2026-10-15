import { useEffect, useState } from "react";
import { X } from "lucide-react";
import type { Locale } from "@/config/site";
import { getContent } from "@/content";
import { withBase } from "@/lib/routes";

/** Screenshot gallery with a small click-to-enlarge lightbox (Esc or click closes it). */
export function Gallery({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  const [open, setOpen] = useState<number | null>(null);
  const shots = c.about.gallery.shots;

  useEffect(() => {
    if (open === null) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(null);
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open]);

  const current = open === null ? null : shots[open];
  return (
    <>
      <ul className="-mx-5 flex snap-x snap-mandatory gap-5 overflow-x-auto px-5 pb-4 sm:mx-0 sm:grid sm:snap-none sm:grid-cols-2 sm:gap-7 sm:overflow-visible sm:px-0 sm:pb-2 lg:grid-cols-3">
        {shots.map((s, i) => (
          <li key={s.file} className="w-[82%] shrink-0 snap-center sm:w-auto">
            <button
              type="button"
              aria-label={`${c.ui.openShot}: ${s.alt}`}
              onClick={() => setOpen(i)}
              className="card-step block w-full cursor-zoom-in overflow-hidden transition-transform hover:-translate-y-1"
            >
              <img
                src={withBase(`/img/${s.file}.webp`)}
                alt={s.alt}
                width={1280}
                height={720}
                loading="lazy"
                decoding="async"
                className="block h-auto w-full"
              />
            </button>
          </li>
        ))}
      </ul>
      {current && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={current.alt}
          className="fixed inset-0 z-[60] grid place-items-center bg-navy/90 p-4"
          onClick={() => setOpen(null)}
        >
          <button
            type="button"
            aria-label={c.ui.close}
            className="absolute right-4 top-4 grid size-12 place-items-center rounded-full border-[3px] border-navy bg-white text-navy"
            onClick={() => setOpen(null)}
          >
            <X className="size-6" aria-hidden />
          </button>
          <img
            src={withBase(`/img/${current.file}.webp`)}
            alt={current.alt}
            width={1280}
            height={720}
            className="max-h-[88vh] w-auto max-w-full rounded-2xl border-[3px] border-white"
          />
        </div>
      )}
    </>
  );
}
