// Non-localized constants: URLs and image assets. Copy lives in
// src/lib/i18n.ts; this file only holds things that don't change by locale.

export const github = "https://github.com/helson-lin/FanBar";
export const releases = "https://github.com/helson-lin/FanBar/releases/latest";

export const heroScreenshot = {
  src: "/screenshots/fanbar-menu-rounded-772.webp",
  avifSrcSet:
    "/screenshots/fanbar-menu-rounded-386.avif 386w, /screenshots/fanbar-menu-rounded-772.avif 772w",
  webpSrcSet:
    "/screenshots/fanbar-menu-rounded-386.webp 386w, /screenshots/fanbar-menu-rounded-772.webp 772w",
  sizes: "(max-width: 767px) 300px, 430px",
  preloadSrc: "/screenshots/fanbar-menu-rounded-772.avif",
  width: 772,
  height: 1243,
} as const;

export const highlightKeys = [
  "status",
  "widget",
  "live",
  "modes",
  "curves",
  "source",
  "alerts",
  "safe",
  "language",
] as const;

export type HighlightKey = (typeof highlightKeys)[number];

export const highlightIcons = {
  status: "activity",
  widget: "layoutGrid",
  live: "activityChart",
  modes: "slidersHorizontal",
  curves: "waypoints",
  source: "thermometer",
  alerts: "bellRing",
  safe: "shieldCheck",
  language: "languages",
} as const satisfies Record<HighlightKey, string>;

export const screenshotKeys = ["popover", "cooling", "menubar"] as const;

export type ScreenshotKey = (typeof screenshotKeys)[number];

export const screenshotAssets: Record<
  ScreenshotKey,
  { src: string; width: number; height: number }
> = {
  popover: {
    src: "/screenshots/fanbar-menu-light-en.jpg",
    width: 912,
    height: 1384,
  },
  cooling: {
    src: "/screenshots/fanbar-settings-cooling-light-en.jpg",
    width: 1120,
    height: 1376,
  },
  menubar: {
    src: "/screenshots/fanbar-settings-menubar-light-en.jpg",
    width: 1120,
    height: 1058,
  },
};
