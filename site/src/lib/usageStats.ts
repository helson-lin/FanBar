// Pure data transforms for the public usage-statistics page. No DOM, no fetch.
// Input shapes mirror GET https://update.getfanbar.com/api/stats
// (services/update/SPEC.md §2). Rows with n < minimumGroupSize never arrive.

export interface DailyRow { day: string; version: string; n: number }
export interface WeeklyRow { week: string; value: string; n: number }

export interface StatsResponse {
  minimumGroupSize: number;
  checksDaily: DailyRow[];
  cohorts: WeeklyRow[];
  models: WeeklyRow[];
  os: WeeklyRow[];
  arch: WeeklyRow[];
  countries: WeeklyRow[];
}

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;
export const OTHER = "other";

function isRows(value: unknown): value is Record<string, unknown>[] {
  return Array.isArray(value) && value.every((row) => typeof row === "object" && row !== null);
}

/** Validate an untrusted payload; returns null if it is not usable stats. */
export function parseStats(payload: unknown): StatsResponse | null {
  if (typeof payload !== "object" || payload === null) return null;
  const p = payload as Record<string, unknown>;
  const minimumGroupSize = typeof p.minimumGroupSize === "number" ? p.minimumGroupSize : 5;
  const daily = isRows(p.checksDaily)
    ? p.checksDaily.filter((r) => typeof r.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(r.day) && typeof r.version === "string" && Number.isFinite(r.n))
    : [];
  const weekly = (key: string): WeeklyRow[] => {
    const rows = p[key];
    return isRows(rows)
      ? rows.filter((r) => typeof r.week === "string" && /^\d{4}-W\d{2}$/.test(r.week) && typeof r.value === "string" && Number.isFinite(r.n)) as unknown as WeeklyRow[]
      : [];
  };
  return {
    minimumGroupSize,
    checksDaily: daily as unknown as DailyRow[],
    cohorts: weekly("cohorts"),
    models: weekly("models"),
    os: weekly("os"),
    arch: weekly("arch"),
    countries: weekly("countries"),
  };
}

/** True when there is nothing at all to show. */
export function isEmptyStats(stats: StatsResponse): boolean {
  return !stats.checksDaily.length
    && !stats.cohorts.length && !stats.models.length && !stats.os.length && !stats.arch.length && !stats.countries.length;
}

// ---- ISO weeks (UTC) -------------------------------------------------------

/** Monday 00:00 UTC of an ISO week "YYYY-Www", as epoch ms. */
export function isoWeekStart(week: string): number {
  const match = /^(\d{4})-W(\d{2})$/.exec(week);
  if (!match) return Number.NaN;
  const year = Number(match[1]);
  const w = Number(match[2]);
  const jan4 = Date.UTC(year, 0, 4);
  const jan4Weekday = (new Date(jan4).getUTCDay() + 6) % 7; // Monday = 0
  return jan4 - jan4Weekday * DAY_MS + (w - 1) * WEEK_MS;
}

/** ISO week label for a date, UTC. */
export function isoWeekOf(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const weekday = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - weekday + 3); // Thursday of this week decides the year
  const year = d.getUTCFullYear();
  const week = 1 + Math.round((d.getTime() - isoWeekStart(`${year}-W01`)) / WEEK_MS);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

/** Whole weeks from `from` to `to` (negative if `to` is earlier). */
export function weeksBetween(from: string, to: string): number {
  return Math.round((isoWeekStart(to) - isoWeekStart(from)) / WEEK_MS);
}

/**
 * Latest week strictly before the current ISO week that has any row.
 * The current week is still filling in, so it is never "complete".
 */
export function latestCompleteWeek(rows: { week: string }[], now: Date): string | null {
  const current = isoWeekOf(now);
  let best: string | null = null;
  for (const { week } of rows) {
    if (week < current && (best === null || week > best)) best = week;
  }
  return best;
}

// ---- Daily update checks by version ---------------------------------------

function compareVersionsDesc(a: string, b: string): number {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pb[i] ?? 0) - (pa[i] ?? 0);
    if (diff) return diff;
  }
  return 0;
}

export interface DailySeries {
  /** Top versions, newest version first. */
  versions: string[];
  /** Every day in the window, oldest first. `counts[i]` aligns with `versions`; `other` is the rest. */
  days: { day: string; counts: number[]; other: number; total: number }[];
  totalChecks: number;
}

/** Top-N versions by total checks (the `other` bucket is never ranked) plus an "other" remainder. */
export function groupDaily(rows: DailyRow[], topN = 5, windowDays = 180): DailySeries {
  if (!rows.length) return { versions: [], days: [], totalChecks: 0 };
  const totals = new Map<string, number>();
  for (const { version, n } of rows) {
    if (version !== OTHER) totals.set(version, (totals.get(version) ?? 0) + n);
  }
  const versions = [...totals.entries()]
    .sort((a, b) => b[1] - a[1] || compareVersionsDesc(a[0], b[0]))
    .slice(0, topN)
    .map(([version]) => version)
    .sort(compareVersionsDesc);
  const index = new Map(versions.map((v, i) => [v, i]));
  const lastDay = rows.reduce((max, r) => (r.day > max ? r.day : max), rows[0].day);
  const lastMs = Date.parse(`${lastDay}T00:00:00Z`);
  const days: DailySeries["days"] = [];
  const byDay = new Map<string, DailySeries["days"][number]>();
  for (let i = windowDays - 1; i >= 0; i--) {
    const day = new Date(lastMs - i * DAY_MS).toISOString().slice(0, 10);
    const entry = { day, counts: versions.map(() => 0), other: 0, total: 0 };
    days.push(entry);
    byDay.set(day, entry);
  }
  let totalChecks = 0;
  for (const { day, version, n } of rows) {
    const entry = byDay.get(day);
    if (!entry) continue;
    const slot = index.get(version);
    if (slot === undefined) entry.other += n;
    else entry.counts[slot] += n;
    entry.total += n;
    totalChecks += n;
  }
  return { versions, days, totalChecks };
}

// ---- Retention by install week --------------------------------------------

export interface CohortRetention {
  cohort: string;
  /** Opted-in users the cohort reported in its own install week. */
  base: number;
  /** ratio[k] = retention k weeks after install, or null where there is no row (hidden <5 or not yet reached). */
  ratios: (number | null)[];
}

export interface Retention {
  cohorts: CohortRetention[];
  /** Longest weeks-since-install offset present (columns 0..maxOffset). */
  maxOffset: number;
  /** Count of `legacy` reports in the most recent week that has one, or null. */
  legacy: { week: string; n: number } | null;
}

/**
 * retention(c, w) = n(w, c) / n(c, c). Cohorts without an own-week row are skipped
 * (their base is unknown or below the minimum group size). `legacy` is reported
 * separately and never enters the table.
 */
export function computeRetention(rows: WeeklyRow[]): Retention {
  const counts = new Map<string, Map<string, number>>(); // cohort -> week -> n
  let legacy: Retention["legacy"] = null;
  for (const { week, value, n } of rows) {
    if (value === "legacy") {
      if (!legacy || week > legacy.week) legacy = { week, n };
      continue;
    }
    if (!/^\d{4}-W\d{2}$/.test(value)) continue;
    if (!counts.has(value)) counts.set(value, new Map());
    counts.get(value)!.set(week, n);
  }
  const cohorts: CohortRetention[] = [];
  let maxOffset = 0;
  for (const cohort of [...counts.keys()].sort()) {
    const byWeek = counts.get(cohort)!;
    const base = byWeek.get(cohort);
    if (!base) continue;
    const ratios: (number | null)[] = [];
    for (const [week, n] of byWeek) {
      const offset = weeksBetween(cohort, week);
      if (offset < 0) continue;
      ratios[offset] = n / base;
      if (offset > maxOffset) maxOffset = offset;
    }
    for (let i = 0; i < ratios.length; i++) ratios[i] ??= null;
    cohorts.push({ cohort, base, ratios });
  }
  return { cohorts, maxOffset, legacy };
}

// ---- Distribution for one week --------------------------------------------

export interface RankedRow { value: string; n: number; share: number; isOther: boolean }

/** Rank one week's rows; keep `limit` named rows, fold the rest and any `other` into one trailing row. */
export function rankWeek(rows: WeeklyRow[], week: string, limit = 8): { total: number; rows: RankedRow[] } {
  const inWeek = rows.filter((r) => r.week === week);
  const total = inWeek.reduce((sum, r) => sum + r.n, 0);
  if (!total) return { total: 0, rows: [] };
  const named = inWeek.filter((r) => r.value !== OTHER).sort((a, b) => b.n - a.n || a.value.localeCompare(b.value));
  const kept = named.slice(0, limit);
  const rest = named.slice(limit).reduce((sum, r) => sum + r.n, 0)
    + inWeek.filter((r) => r.value === OTHER).reduce((sum, r) => sum + r.n, 0);
  const out: RankedRow[] = kept.map((r) => ({ value: r.value, n: r.n, share: r.n / total, isOther: false }));
  if (rest > 0) out.push({ value: OTHER, n: rest, share: rest / total, isOther: true });
  return { total, rows: out };
}
