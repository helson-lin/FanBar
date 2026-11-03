import { isoWeek } from './fields.ts';
import { DAY_MS, utcDay, WEEKLY_TABLES } from './storage.ts';

const MINIMUM_GROUP_SIZE = 5;
const STATS_DAYS = 180;
const STATS_WEEKS = 26;

export async function publicStats(env: Env) {
  const now = Date.now();
  const firstDay = utcDay(new Date(now - (STATS_DAYS - 1) * DAY_MS));
  const firstWeek = isoWeek(new Date(now - (STATS_WEEKS - 1) * 7 * DAY_MS));
  const [daily, ...weekly] = await env.DB.batch([
    env.DB.prepare('SELECT day, version, n FROM checks_daily WHERE n >= ? AND day >= ? ORDER BY day, version')
      .bind(MINIMUM_GROUP_SIZE, firstDay),
    ...Object.values(WEEKLY_TABLES).map((table) => env.DB.prepare(
      `SELECT week, value, n FROM ${table} WHERE n >= ? AND week >= ? ORDER BY week, value`,
    ).bind(MINIMUM_GROUP_SIZE, firstWeek)),
  ]);
  const body: Record<string, unknown> = { minimumGroupSize: MINIMUM_GROUP_SIZE, checksDaily: daily.results };
  Object.keys(WEEKLY_TABLES).forEach((name, index) => { body[name] = weekly[index].results; });
  return Response.json(body, {
    headers: { 'Access-Control-Allow-Origin': env.STATS_ORIGIN, 'Cache-Control': 'public, max-age=3600' },
  });
}
