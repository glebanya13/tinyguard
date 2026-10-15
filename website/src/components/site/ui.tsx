import type { ReactNode } from "react";
import { Mail } from "lucide-react";
import { hasValue, site, type Locale } from "@/config/site";
import { getContent } from "@/content";
import type { Block, Doc, Faq } from "@/content/types";
import { cn } from "@/lib/utils";
import { Rich } from "./Rich";

export function SectionHead({
  eyebrow,
  title,
  lead,
  id,
}: {
  eyebrow?: string;
  title: string;
  lead?: string;
  id?: string;
}) {
  return (
    <div className="mb-10 max-w-3xl">
      {eyebrow && <p className="text-eyebrow mb-3 text-purple">{eyebrow}</p>}
      <h2 id={id} className="text-h2">
        {title}
      </h2>
      {lead && <p className="mt-4 text-lg leading-relaxed text-body">{lead}</p>}
    </div>
  );
}

export function PageHero({
  eyebrow,
  title,
  lead,
  children,
}: {
  eyebrow?: string;
  title: string;
  lead?: string;
  children?: ReactNode;
}) {
  return (
    <section className="sky-gradient border-b-[3px] border-navy py-14 md:py-20">
      <div className="container-site">
        {eyebrow && <p className="text-eyebrow mb-4 text-purple">{eyebrow}</p>}
        <h1 className="text-h1 max-w-4xl">{title}</h1>
        {lead && (
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-body md:text-xl">{lead}</p>
        )}
        {children && <div className="mt-8">{children}</div>}
      </div>
    </section>
  );
}

/** Orange "Coming Soon to Google Play" button; a real link once site.playUrl is set. */
export function PlayButton({ locale, className }: { locale: Locale; className?: string }) {
  const c = getContent(locale);
  const icon = (
    <svg viewBox="0 0 24 24" className="size-6" aria-hidden fill="currentColor">
      <path d="M5 3.5v17a1 1 0 0 0 1.5.9l14-8.5a1 1 0 0 0 0-1.8l-14-8.5A1 1 0 0 0 5 3.5Z" />
    </svg>
  );
  if (hasValue(site.playUrl)) {
    return (
      <a
        href={site.playUrl}
        target="_blank"
        rel="noopener noreferrer"
        className={cn("btn btn-orange", className)}
      >
        {icon} {c.ui.getOnPlay}
      </a>
    );
  }
  return (
    <span className={cn("btn btn-soon", className)}>
      {icon} {c.ui.comingSoonPlay}
    </span>
  );
}

export function FaqList({ items, locale }: { items: Faq[]; locale: Locale }) {
  return (
    <div className="divide-y divide-line border-y-2 border-line">
      {items.map((it) => (
        <details key={it.q} className="faq group">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 text-lg font-bold">
            {it.q}
            <span aria-hidden className="faq-mark text-purple">
              +
            </span>
          </summary>
          <p className="pb-5 pr-10 leading-relaxed text-body">
            <Rich text={it.a} locale={locale} />
          </p>
        </details>
      ))}
    </div>
  );
}

/** "Contact" block: hidden while no e-mail is configured. */
export function ContactBlock({ locale }: { locale: Locale }) {
  const email = site.contacts.email;
  if (!hasValue(email)) return null;
  const c = getContent(locale);
  return (
    <section id="contact" aria-labelledby="contact-title" className="card-step p-8 md:p-10">
      <h2 id="contact-title" className="text-h3">
        {c.ui.contactTitle}
      </h2>
      <p className="mt-3 max-w-xl text-body">{c.ui.contactLead}</p>
      <a href={`mailto:${email}`} className="btn btn-orange mt-6 break-all">
        <Mail className="size-4" aria-hidden /> {email}
      </a>
    </section>
  );
}

function BlockView({ block, locale }: { block: Block; locale: Locale }) {
  switch (block.t) {
    case "p":
      return (
        <p className="leading-relaxed">
          <Rich text={block.text} locale={locale} />
        </p>
      );
    case "note":
      return (
        <p className="rounded-xl border-[3px] border-navy bg-[#f3efd9] p-4 leading-relaxed">
          <Rich text={block.text} locale={locale} />
        </p>
      );
    case "ul":
      return (
        <ul className="list-disc space-y-2 pl-6 leading-relaxed marker:text-purple">
          {block.items.map((t) => (
            <li key={t}>
              <Rich text={t} locale={locale} />
            </li>
          ))}
        </ul>
      );
    case "ol":
      return (
        <ol className="list-decimal space-y-2 pl-6 leading-relaxed marker:font-bold marker:text-purple">
          {block.items.map((t) => (
            <li key={t}>
              <Rich text={t} locale={locale} />
            </li>
          ))}
        </ol>
      );
    case "table":
      return (
        <div className="overflow-x-auto rounded-xl border-[3px] border-navy">
          <table className="w-full min-w-[40rem] border-collapse text-left text-sm">
            <thead className="bg-[#f3efd9]">
              <tr>
                {block.head.map((h) => (
                  <th key={h} scope="col" className="px-4 py-3 font-bold">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {block.rows.map((row) => (
                <tr key={row[0]} className="align-top">
                  {row.map((cell, i) => (
                    <td key={i} className="px-4 py-3 leading-relaxed">
                      <Rich text={cell} locale={locale} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
  }
}

export interface DocViewProps {
  doc: Doc;
  locale: Locale;
  hideSections?: string[];
  extra?: Record<string, ReactNode>;
  top?: ReactNode;
}

export function DocView({ doc, locale, hideSections = [], extra = {}, top }: DocViewProps) {
  const sections = doc.sections.filter((s) => !hideSections.includes(s.id));
  return (
    <>
      <PageHero eyebrow={doc.eyebrow} title={doc.title} lead={doc.lead} />
      <div className="container-site section-y">
        <div className="mx-auto max-w-3xl space-y-12">
          {top}
          {sections.map((s) => (
            <section
              key={s.id}
              id={s.id}
              aria-labelledby={`${s.id}-h`}
              className="scroll-mt-28 space-y-4"
            >
              <h2 id={`${s.id}-h`} className="text-h3">
                {s.title}
              </h2>
              {s.blocks.map((b, i) => (
                <BlockView key={i} block={b} locale={locale} />
              ))}
              {extra[s.id]}
            </section>
          ))}
          <ContactBlock locale={locale} />
        </div>
      </div>
    </>
  );
}
