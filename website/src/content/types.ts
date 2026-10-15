import type { Locale } from "@/config/site";

export type Block =
  | { t: "p"; text: string }
  | { t: "ul"; items: string[] }
  | { t: "ol"; items: string[] }
  | { t: "table"; head: string[]; rows: string[][] }
  | { t: "note"; text: string };

export interface Section {
  id: string;
  title: string;
  blocks: Block[];
}

export interface Doc {
  eyebrow: string;
  title: string;
  lead: string;
  sections: Section[];
}

export interface Faq {
  q: string;
  a: string;
}

export type IconName =
  | "map"
  | "route"
  | "swords"
  | "castle"
  | "hourglass"
  | "trophy"
  | "users"
  | "wifiOff"
  | "languages"
  | "star"
  | "axe"
  | "coins"
  | "hammer"
  | "shieldCheck";

export interface Content {
  locale: Locale;
  htmlLang: string;
  ogLocale: string;
  ui: {
    skip: string;
    menu: string;
    closeMenu: string;
    mainNav: string;
    mobileNav: string;
    homeAria: string;
    navHome: string;
    navAbout: string;
    navPrivacy: string;
    navContact: string;
    navTerms: string;
    navSupport: string;
    comingSoon: string;
    comingSoonPlay: string;
    getOnPlay: string;
    madeFor: string;
    footerTagline: string;
    copyright: string;
    langOther: string;
    langOtherName: string;
    langSwitchLabel: string;
    close: string;
    openShot: string;
    operator: string;
    contact: string;
    policyVersion: string;
    contactTitle: string;
    contactLead: string;
    contactSoon: string;
    notFoundTitle: string;
    notFoundLead: string;
    notFoundBack: string;
  };
  meta: Record<
    "home" | "about" | "privacy" | "deleteAccount" | "support" | "contact" | "terms" | "notFound",
    { title: string; description: string }
  >;
  home: { badge: string; title: string; lead: string; introTitle: string; introText: string };
  about: {
    eyebrow: string;
    title: string;
    lead: string;
    features: {
      title: string;
      lead: string;
      items: { icon: IconName; title: string; text: string }[];
    };
    towers: {
      title: string;
      lead: string;
      costLabel: string;
      items: { name: string; role: string; cost: string }[];
    };
    gallery: { title: string; lead: string; shots: { file: string; alt: string }[] };
    how: {
      title: string;
      lead: string;
      steps: { title: string; text: string }[];
      controls: string;
    };
    faq: { title: string; lead: string; items: Faq[] };
  };
  contact: Doc;
  privacy: Doc;
  deleteAccount: Doc;
  support: Doc & { faq: Faq[]; faqTitle: string };
  terms: Doc;
}
