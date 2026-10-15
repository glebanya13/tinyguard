import { StrictMode } from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import "./styles.css";
import { App } from "./App";
import { site, hasValue } from "./config/site";
import { pageMeta } from "./lib/seo";
import { resolveRoute } from "./lib/routes";

const route = resolveRoute(window.location.pathname);
const rootEl = document.getElementById("root");
if (!rootEl) throw new Error("#root not found");
const app = (
  <StrictMode>
    <App route={route} />
  </StrictMode>
);

if (rootEl.children.length > 0) {
  hydrateRoot(rootEl, app);
} else {
  // Dev server: no pre-rendered HTML, set the document head here.
  document.documentElement.lang = route.locale;
  document.title = pageMeta(route).title;
  createRoot(rootEl).render(app);
}

// Optional analytics: only when the owner sets site.analytics.gaId (empty by default).
if (hasValue(site.analytics.gaId)) {
  const s = document.createElement("script");
  s.async = true;
  s.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(site.analytics.gaId)}`;
  document.head.appendChild(s);
}
