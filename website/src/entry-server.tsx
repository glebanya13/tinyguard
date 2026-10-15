import { renderToString } from "react-dom/server";
import { App } from "./App";
import { allRoutes, notFoundRoute, type RouteInfo } from "./lib/routes";
import { headTags } from "./lib/seo";
import { missingOwnerValues, resolveSiteUrl } from "./config/site";

export const routes: RouteInfo[] = allRoutes();
export { notFoundRoute, headTags, missingOwnerValues, resolveSiteUrl };
export const render = (route: RouteInfo): string => renderToString(<App route={route} />);
