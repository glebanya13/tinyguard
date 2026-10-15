import { Fragment } from "react";
import type { Locale } from "@/config/site";
import { localHref } from "@/lib/routes";

const TOKEN = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g;
const LINK = /^\[([^\]]+)\]\(([^)]+)\)$/;

/** Minimal inline markup: **bold**, `code`, [label](/internal/ or https://external). */
export function Rich({ text, locale }: { text: string; locale: Locale }) {
  return (
    <>
      {text.split(TOKEN).map((part, i) => {
        if (part.startsWith("**")) return <strong key={i}>{part.slice(2, -2)}</strong>;
        if (part.startsWith("`")) return <code key={i}>{part.slice(1, -1)}</code>;
        const m = LINK.exec(part);
        if (m) {
          const href = m[2] ?? "";
          const label = m[1] ?? "";
          return href.startsWith("/") ? (
            <a key={i} href={localHref(locale, href)} className="link">
              {label}
            </a>
          ) : (
            <a key={i} href={href} target="_blank" rel="noopener noreferrer" className="link">
              {label}
            </a>
          );
        }
        return <Fragment key={i}>{part}</Fragment>;
      })}
    </>
  );
}
