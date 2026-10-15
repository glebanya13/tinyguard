import type { ReactNode } from "react";
import { Footer } from "@/components/site/Footer";
import { Header } from "@/components/site/Header";
import { getContent } from "@/content";
import type { RouteInfo } from "@/lib/routes";
import { About } from "@/pages/About";
import { Contact, DeleteAccount, NotFound, Privacy, Support, Terms } from "@/pages/Docs";
import { Home } from "@/pages/Home";

function Page({ route }: { route: RouteInfo }): ReactNode {
  const l = route.locale;
  switch (route.key) {
    case "home":
      return <Home locale={l} />;
    case "about":
      return <About locale={l} />;
    case "privacy":
      return <Privacy locale={l} />;
    case "deleteAccount":
      return <DeleteAccount locale={l} />;
    case "support":
      return <Support locale={l} />;
    case "contact":
      return <Contact locale={l} />;
    case "terms":
      return <Terms locale={l} />;
    default:
      return <NotFound locale={l} />;
  }
}

export function App({ route }: { route: RouteInfo }) {
  const c = getContent(route.locale);
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[70] focus:rounded-full focus:bg-white focus:px-4 focus:py-2"
      >
        {c.ui.skip}
      </a>
      <Header route={route} />
      <main id="main" tabIndex={-1}>
        <Page route={route} />
      </main>
      <Footer locale={route.locale} />
    </>
  );
}
