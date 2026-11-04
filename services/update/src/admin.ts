import { isoWeek } from './fields.ts';
import { MINIMUM_GROUP_SIZE } from './stats.ts';
import { DAY_MS, utcDay, WEEKLY_TABLES, type WeeklyDimension } from './storage.ts';

/**
 * Full aggregates for the maintainer admin on report.getfanbar.com. Unlike /api/stats,
 * groups smaller than the public minimum are included. Only reachable through the
 * UpdateAdmin service binding: it has no URL, and the caller has already checked
 * Cloudflare Access.
 */
export const ADMIN_RANGES = [7, 30, 90] as const;
export type AdminRange = (typeof ADMIN_RANGES)[number];
const ADMIN_WEEKS = 8;

type DailyRow = { day: string; version: string; n: number };
type WeeklyRow = { week: string; value: string; n: number };

export interface AdminStats {
  generatedAt: string;
  range: AdminRange;
  /** Groups below this size are hidden from /api/stats, not from this response. */
  publicMinimumGroupSize: number;
  /** The last `range` UTC days, oldest first; the last entry is today. */
  days: string[];
  /** Every version count for the last max(2 × range, 14) days, so the admin can compare periods. */
  daily: DailyRow[];
  /** The last eight ISO weeks, newest first. */
  weeks: string[];
  weekly: Record<WeeklyDimension, WeeklyRow[]>;
  currentWeek: { week: string; checks: number; optedIn: number };
  /** Known releases, newest first. Versions outside this list are counted as `other`. */
  releases: string[];
  /** UTC day the daily task last ran, or null before its first run. */
  dailyTaskDay: string | null;
}

export const isAdminRange = (value: number): value is AdminRange => (ADMIN_RANGES as readonly number[]).includes(value);

const versionParts = (version: string) => version.split(/[.-]/).map((part) => (/^\d+$/.test(part) ? Number(part) : part));
function newestFirst(a: string, b: string) {
  const left = versionParts(a);
  const right = versionParts(b);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const x = left[i];
    const y = right[i];
    if (x === y) continue;
    // A plain release (no suffix) is newer than its pre-releases.
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    if (typeof x === 'number' && typeof y === 'number') return y - x;
    return String(y).localeCompare(String(x));
  }
  return 0;
}

function mondayOf(date: Date) {
  const day = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() || 7) - 1));
  return utcDay(day);
}

export async function adminStats(env: Env, range: AdminRange): Promise<AdminStats> {
  const now = new Date();
  const days = Array.from({ length: range }, (_, i) => utcDay(new Date(now.getTime() - (range - 1 - i) * DAY_MS)));
  const span = Math.max(range * 2, 14);
  const firstDay = utcDay(new Date(now.getTime() - (span - 1) * DAY_MS));
  const weeks = Array.from({ length: ADMIN_WEEKS }, (_, i) => isoWeek(new Date(now.getTime() - i * 7 * DAY_MS)));
  const tables = Object.entries(WEEKLY_TABLES) as [WeeklyDimension, string][];

  const [daily, releases, task, ...weekly] = await env.DB.batch([
    env.DB.prepare('SELECT day, version, n FROM checks_daily WHERE day >= ? ORDER BY day, version').bind(firstDay),
    env.DB.prepare('SELECT version FROM releases'),
    env.DB.prepare("SELECT day FROM task_runs WHERE task = 'daily'"),
    ...tables.map(([, table]) => env.DB.prepare(
      `SELECT week, value, n FROM ${table} WHERE week >= ? ORDER BY week DESC, n DESC, value`,
    ).bind(weeks[weeks.length - 1])),
  ]);

  const dailyRows = daily.results as DailyRow[];
  const weeklyRows = Object.fromEntries(tables.map(([name], index) => [name, weekly[index].results as WeeklyRow[]])) as AdminStats['weekly'];
  const monday = mondayOf(now);
  const taskDay = (task.results[0] as { day?: string } | undefined)?.day;

  return {
    generatedAt: now.toISOString(),
    range,
    publicMinimumGroupSize: MINIMUM_GROUP_SIZE,
    days,
    daily: dailyRows,
    weeks,
    weekly: weeklyRows,
    currentWeek: {
      week: weeks[0],
      checks: dailyRows.filter((row) => row.day >= monday).reduce((sum, row) => sum + row.n, 0),
      // Every opted-in check carries a cohort, so the cohort table counts them once each.
      optedIn: weeklyRows.cohorts.filter((row) => row.week === weeks[0]).reduce((sum, row) => sum + row.n, 0),
    },
    releases: (releases.results as { version: string }[]).map((row) => row.version).sort(newestFirst),
    dailyTaskDay: taskDay || null,
  };
}
