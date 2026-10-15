import { hasValue, site, type Locale } from "@/config/site";
import { getContent } from "@/content";
import { pathFor, withBase } from "@/lib/routes";
import { ContactBlock, DocView, FaqList, PageHero } from "@/components/site/ui";

const loc = (l: { ru: string; en: string }, locale: Locale): string => l[locale];

export function Privacy({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  const rows: [string, string][] = [];
  if (hasValue(site.privacy.operatorName)) rows.push([c.ui.operator, site.privacy.operatorName]);
  if (hasValue(site.contacts.email)) rows.push([c.ui.contact, site.contacts.email]);
  rows.push([c.ui.policyVersion, site.privacy.version]);
  const retention = loc(site.privacy.inactiveRetentionNote, locale);
  return (
    <DocView
      doc={c.privacy}
      locale={locale}
      top={
        <dl className="card-step grid gap-x-6 gap-y-2 p-6 sm:grid-cols-[auto_1fr]">
          {rows.map(([k, v]) => (
            <div key={k} className="contents">
              <dt className="font-extrabold">{k}</dt>
              <dd className="break-all text-body">{v}</dd>
            </div>
          ))}
        </dl>
      }
      extra={
        hasValue(retention) ? { retention: <p className="leading-relaxed">{retention}</p> } : {}
      }
    />
  );
}

export function DeleteAccount({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  const note = loc(site.deletion.responseNote, locale);
  const hasMail = hasValue(site.contacts.email);
  return (
    <DocView
      doc={c.deleteAccount}
      locale={locale}
      hideSections={hasMail ? [] : ["email"]}
      extra={hasMail && hasValue(note) ? { email: <p className="leading-relaxed">{note}</p> } : {}}
    />
  );
}

export function Terms({ locale }: { locale: Locale }) {
  return <DocView doc={getContent(locale).terms} locale={locale} />;
}

export function Support({ locale }: { locale: Locale }) {
  const s = getContent(locale).support;
  return (
    <DocView
      doc={s}
      locale={locale}
      extra={{
        report: (
          <div className="pt-8">
            <h2 className="text-h3 mb-4">{s.faqTitle}</h2>
            <FaqList items={s.faq} locale={locale} />
          </div>
        ),
      }}
    />
  );
}

export function Contact({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  return (
    <>
      <PageHero eyebrow={c.contact.eyebrow} title={c.contact.title} lead={c.contact.lead} />
      <div className="container-site section-y">
        <div className="mx-auto max-w-3xl">
          {hasValue(site.contacts.email) ? (
            <ContactBlock locale={locale} />
          ) : (
            <p className="card-step p-8 text-lg text-body">{c.ui.contactSoon}</p>
          )}
        </div>
      </div>
    </>
  );
}

export function NotFound({ locale }: { locale: Locale }) {
  const c = getContent(locale);
  return (
    <>
      <PageHero title={c.ui.notFoundTitle} lead={c.ui.notFoundLead}>
        <a href={withBase(pathFor("home", locale))} className="btn btn-orange">
          {c.ui.notFoundBack}
        </a>
      </PageHero>
    </>
  );
}
