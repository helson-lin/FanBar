import { isoWeek } from './fields.ts';
import { DAY_MS, utcDay, WEEKLY_TABLES } from './storage.ts';

export const MINIMUM_GROUP_SIZE = 5;
const STATS_DAYS = 180;
const STATS_WEEKS = 26;
const CACHE_SECONDS = 3600;

async function readStats(env: Env) {
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
  return body;
}

/**
 * Public, unauthenticated and fetched on every stats page view, so production answers
 * from the edge cache for an hour instead of running six D1 queries per request.
 * The cache key ignores the query string, so `?anything` cannot bypass it.
 */
export async function publicStats(request: Request, env: Env, ctx: ExecutionContext) {
  const cors = { 'Access-Control-Allow-Origin': env.STATS_ORIGIN };
  const cache = env.ENVIRONMENT === 'production' ? caches.default : undefined;
  const cacheKey = new Request(new URL('/api/stats', request.url).toString(), { method: 'GET' });
  const cached = await cache?.match(cacheKey);
  if (cached) return cached;
  let body: Record<string, unknown>;
  try {
    body = await readStats(env);
  } catch (error) {
    console.error('stats not served', error instanceof Error ? error.message : 'unknown error');
    return Response.json({ error: 'unavailable' }, { status: 503, headers: { ...cors, 'Cache-Control': 'no-store' } });
  }
  const response = Response.json(body, {
    headers: { ...cors, 'Cache-Control': `public, max-age=${CACHE_SECONDS}` },
  });
  if (cache) ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}
