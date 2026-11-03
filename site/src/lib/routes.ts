import type { Locale } from "./i18n";

const homePaths: Record<Locale, string> = {
  en: "/",
  zh: "/zh",
  "zh-tw": "/zh-tw",
  ja: "/ja",
  ru: "/ru",
  fr: "/fr",
};

export function homePath(locale: Locale): string {
  return homePaths[locale];
}

// Pages that exist only in English and Simplified Chinese fall back to English for the other locales.
export function comparisonPath(locale: Locale): string {
  return locale === "zh" ? "/zh/compare/macs-fan-control" : "/compare/macs-fan-control";
}

export function compatibilityPath(locale: Locale): string {
  return locale === "zh" ? "/zh/compatibility" : "/compatibility";
}

export function safetyPath(locale: Locale): string {
  return locale === "zh" ? "/zh/is-fanbar-safe" : "/is-fanbar-safe";
}

// Each row lists one page in every locale that has it.
const translatedPages: Partial<Record<Locale, string>>[] = [
  homePaths,
  { en: "/compare/macs-fan-control", zh: "/zh/compare/macs-fan-control" },
  { en: "/compatibility", zh: "/zh/compatibility" },
  { en: "/is-fanbar-safe", zh: "/zh/is-fanbar-safe" },
  { en: "/stats", zh: "/zh/stats" },
];

/** The same page in `target`, or `target`'s home page when it isn't translated. */
export function localizedPath(pathname: string, target: Locale): string {
  const normalized = pathname.length > 1 ? pathname.replace(/\/$/, "") : pathname;
  // Release notes exist in English and Chinese for every version.
  const release = normalized.match(/^(?:\/zh)?(\/releases(?:\/[^/]+)?)$/);
  if (release) return target === "zh" ? `/zh${release[1]}` : target === "en" ? release[1] : homePaths[target];
  const page = translatedPages.find((row) => Object.values(row).includes(normalized));
  return page?.[target] ?? homePaths[target];
}
