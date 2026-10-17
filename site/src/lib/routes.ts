import type { Locale } from "./i18n";

export function homePath(locale: Locale): string {
  return locale === "zh" ? "/zh" : "/";
}

export function comparisonPath(locale: Locale): string {
  return locale === "zh" ? "/zh/compare/macs-fan-control" : "/compare/macs-fan-control";
}

export function compatibilityPath(locale: Locale): string {
  return locale === "zh" ? "/zh/compatibility" : "/compatibility";
}

export function alternateLocalePath(pathname: string, locale: Locale): string {
  if (locale === "en") {
    if (pathname === "/compatibility") return "/zh/compatibility";
    if (pathname === "/compare/macs-fan-control") return "/zh/compare/macs-fan-control";
    return "/zh";
  }

  if (pathname === "/zh/compatibility") return "/compatibility";
  if (pathname === "/zh/compare/macs-fan-control") return "/compare/macs-fan-control";
  return "/";
}
