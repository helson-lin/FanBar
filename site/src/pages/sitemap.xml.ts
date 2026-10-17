import type { APIRoute } from "astro";
import { HTML_LANG, LOCALE_URLS, siteUrl } from "@/lib/seo";

export const prerender = true;

export const GET: APIRoute = () => {
  const alternates = `
      <xhtml:link rel="alternate" hreflang="${HTML_LANG.en}" href="${LOCALE_URLS.en}" />
      <xhtml:link rel="alternate" hreflang="${HTML_LANG.zh}" href="${LOCALE_URLS.zh}" />
      <xhtml:link rel="alternate" hreflang="x-default" href="${LOCALE_URLS.en}" />`;
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>${LOCALE_URLS.en}</loc>${alternates}
  </url>
  <url>
    <loc>${LOCALE_URLS.zh}</loc>${alternates}
  </url>
  <url>
    <loc>${siteUrl}/compare/macs-fan-control</loc>
    <lastmod>2026-10-11</lastmod>
    <xhtml:link rel="alternate" hreflang="en" href="${siteUrl}/compare/macs-fan-control" />
    <xhtml:link rel="alternate" hreflang="zh-Hans" href="${siteUrl}/zh/compare/macs-fan-control" />
    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}/compare/macs-fan-control" />
  </url>
  <url>
    <loc>${siteUrl}/zh/compare/macs-fan-control</loc>
    <lastmod>2026-10-11</lastmod>
    <xhtml:link rel="alternate" hreflang="en" href="${siteUrl}/compare/macs-fan-control" />
    <xhtml:link rel="alternate" hreflang="zh-Hans" href="${siteUrl}/zh/compare/macs-fan-control" />
    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}/compare/macs-fan-control" />
  </url>
  <url>
    <loc>${siteUrl}/compatibility</loc>
    <lastmod>2026-10-11</lastmod>
    <xhtml:link rel="alternate" hreflang="en" href="${siteUrl}/compatibility" />
    <xhtml:link rel="alternate" hreflang="zh-Hans" href="${siteUrl}/zh/compatibility" />
    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}/compatibility" />
  </url>
  <url>
    <loc>${siteUrl}/zh/compatibility</loc>
    <lastmod>2026-10-11</lastmod>
    <xhtml:link rel="alternate" hreflang="en" href="${siteUrl}/compatibility" />
    <xhtml:link rel="alternate" hreflang="zh-Hans" href="${siteUrl}/zh/compatibility" />
    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}/compatibility" />
  </url>
  <url>
    <loc>${siteUrl}/api</loc>
    <lastmod>2026-10-12</lastmod>
  </url>
</urlset>
`;

  return new Response(body, {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
};
