// Dev-only fixture: used when the stats page is opened with ?mock in `astro dev`.
// Guarded by import.meta.env.DEV at the call site, so it never ships in production.

import { isoWeekOf, isoWeekStart } from "./usageStats";

export function mockStats() {
  const now = Date.now();
  const DAY = 86_400_000;
  const checksDaily: { day: string; version: string; n: number }[] = [];
  const versions = ["0.8.0", "0.7.2", "0.7.0", "0.6.1", "0.5.0"];
  for (let i = 179; i >= 0; i--) {
    const day = new Date(now - i * DAY).toISOString().slice(0, 10);
    versions.forEach((version, k) => {
      const n = Math.round(Math.max(0, 60 + 40 * Math.sin(i / 9 + k)) * (k === 0 ? Math.min(1, (180 - i) / 60) : 1.2 / (k + 1)));
      if (n >= 5) checksDaily.push({ day, version, n });
    });
    checksDaily.push({ day, version: "other", n: 6 + (i % 7) });
  }
  const weekOf = (back: number) => isoWeekOf(new Date(isoWeekStart(isoWeekOf(new Date(now))) - back * 7 * DAY));
  const cohorts: { week: string; value: string; n: number }[] = [];
  for (let c = 12; c >= 1; c--) {
    const base = 40 + c * 7;
    for (let w = c; w >= 1; w--) {
      const k = c - w;
      const n = Math.round(base * Math.pow(0.82, k));
      if (n >= 5) cohorts.push({ week: weekOf(w), value: weekOf(c), n });
    }
  }
  for (let w = 1; w <= 12; w++) cohorts.push({ week: weekOf(w), value: "legacy", n: 300 - w * 5 });
  const dist = (values: [string, number][]) => {
    const rows: { week: string; value: string; n: number }[] = [];
    for (let w = 0; w <= 4; w++) for (const [value, n] of values) rows.push({ week: weekOf(w), value, n: n + w });
    return rows;
  };
  return {
    minimumGroupSize: 5,
    checksDaily,
    cohorts,
    models: dist([["MacBookPro18,3", 90], ["Mac14,2", 70], ["MacBookAir10,1", 40], ["Macmini9,1", 12], ["other", 22]]),
    os: dist([["15", 140], ["14", 70], ["13", 25], ["12", 8]]),
    arch: dist([["arm64", 200], ["x86_64", 45]]),
    countries: dist([["US", 80], ["CN", 60], ["DE", 25], ["JP", 18], ["FR", 9]]),
  };
}
