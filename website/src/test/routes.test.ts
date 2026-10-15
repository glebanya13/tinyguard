import { describe, expect, it } from "vitest";
import { allRoutes, mirrorPath, notFoundRoute, resolveRoute } from "@/lib/routes";
import { missingOwnerValues, site } from "@/config/site";

describe("routes", () => {
  it("has every page in both locales", () => {
    expect(allRoutes()).toHaveLength(14);
    const paths = allRoutes().map((r) => r.path);
    expect(new Set(paths).size).toBe(paths.length);
    expect(paths).toContain("/");
    expect(paths).toContain("/privacy/");
    expect(paths).toContain("/delete-account/");
    expect(paths).toContain("/ru/");
    expect(paths).toContain("/ru/privacy/");
  });

  it("resolves pathnames with and without base and trailing slash", () => {
    expect(resolveRoute("/privacy", "/").key).toBe("privacy");
    expect(resolveRoute("/bg/ru/terms/", "/bg/")).toMatchObject({ key: "terms", locale: "ru" });
    expect(resolveRoute("/nope/", "/").key).toBe("notFound");
    expect(resolveRoute("/ru/nope/", "/").locale).toBe("ru");
  });

  it("mirrors pages between languages", () => {
    expect(mirrorPath(resolveRoute("/privacy/", "/"))).toBe("/ru/privacy/");
    expect(mirrorPath(notFoundRoute("ru"))).toBe("/");
  });

  it("lists missing owner values and hides empty config", () => {
    expect(missingOwnerValues(site, "")).toEqual(
      expect.arrayContaining([expect.stringContaining("siteUrl")]),
    );
    expect(site.analytics.gaId).toBe("");
  });
});
