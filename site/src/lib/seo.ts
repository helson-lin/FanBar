// Search- and answer-engine metadata: canonical URLs, language tags, and the
// JSON-LD graph. Copy lives in src/lib/i18n.ts; this file only shapes it.

import { defaultLocale, locales, type Dictionary, type Locale } from "./i18n";
import { github, heroScreenshot, releases, screenshotAssets } from "./links";

export const siteUrl = "https://fanbar.jarin.me";
export const siteName = "FanBar";

// BCP 47 tags, shared by <html lang>, hreflang alternates, and Open Graph.
export const HTML_LANG: Record<Locale, string> = { en: "en", zh: "zh-Hans" };
export const OG_LOCALE: Record<Locale, string> = { en: "en_US", zh: "zh_CN" };

// English lives at the bare domain; Vercel permanently redirects "/en" here.
export const LOCALE_PATHS: Record<Locale, string> = { en: "/", zh: "/zh" };
export const LOCALE_URLS: Record<Locale, string> = {
  en: siteUrl,
  zh: `${siteUrl}/zh`,
};

// Absolute hreflang map, plus the x-default the default locale answers to.
export function languageAlternates(
  urls: Record<Locale, string>,
): Record<string, string> {
  const tags = locales.map((locale) => [HTML_LANG[locale], urls[locale]] as const);
  return { ...Object.fromEntries(tags), "x-default": urls[defaultLocale] };
}

const gplLicense = "https://www.gnu.org/licenses/gpl-3.0.html";

export function structuredData(locale: Locale, dict: Dictionary) {
  const url = LOCALE_URLS[locale];
  const publisherId = `${siteUrl}/#publisher`;
  const appId = `${siteUrl}/#app`;
  const screenshots = [heroScreenshot.src, ...Object.values(screenshotAssets).map((a) => a.src)].map(
    (src) => `${siteUrl}${src}`,
  );

  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": publisherId,
        name: siteName,
        url: siteUrl,
        logo: {
          "@type": "ImageObject",
          url: `${siteUrl}/icon-512.png`,
          width: 512,
          height: 512,
        },
        sameAs: [github],
      },
      {
        "@type": "WebSite",
        "@id": `${siteUrl}/#website`,
        url: siteUrl,
        name: siteName,
        description: dict.meta.description,
        inLanguage: Object.values(HTML_LANG),
        publisher: { "@id": publisherId },
      },
      {
        "@type": "WebPage",
        "@id": `${url}#webpage`,
        url,
        name: dict.meta.title,
        description: dict.meta.description,
        inLanguage: HTML_LANG[locale],
        isPartOf: { "@id": `${siteUrl}/#website` },
        about: { "@id": appId },
      },
      {
        "@type": "SoftwareApplication",
        "@id": appId,
        name: siteName,
        alternateName: "FanBar for macOS",
        applicationCategory: "UtilitiesApplication",
        applicationSubCategory: "Fan control and temperature monitoring",
        operatingSystem: "macOS 11 Big Sur or later",
        description: dict.meta.description,
        url,
        downloadUrl: releases,
        softwareHelp: `${github}#readme`,
        license: gplLicense,
        isAccessibleForFree: true,
        offers: {
          "@type": "Offer",
          price: "0",
          priceCurrency: "USD",
          availability: "https://schema.org/InStock",
        },
        inLanguage: Object.values(HTML_LANG),
        screenshot: screenshots,
        featureList: Object.values(dict.highlights.items).map(
          (item) => `${item.title}: ${item.description}`,
        ),
        author: { "@id": publisherId },
        publisher: { "@id": publisherId },
      },
      {
        "@type": "FAQPage",
        "@id": `${url}#faq`,
        inLanguage: HTML_LANG[locale],
        isPartOf: { "@id": `${url}#webpage` },
        mainEntity: dict.faq.items.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
    ],
  };
}
