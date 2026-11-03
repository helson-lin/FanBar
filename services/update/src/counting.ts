import * as fields from './fields.ts';
import { utcDay, WEEKLY_TABLES, type WeeklyDimension } from './storage.ts';

const SPARKLE_AGENT = /^FanBar\/([^\s]+) Sparkle\//;

// The address is only hashed into a rate-limit key; it is never stored.
async function withinLimit(request: Request, env: Env) {
  const address = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(env.LIMIT_SALT + address));
  const key = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return (await env.COUNT_LIMIT.limit({ key })).success;
}

function optedInValues(request: Request, env: Env, week: string): Partial<Record<WeeklyDimension, string>> {
  const query = new URL(request.url).searchParams;
  const cohorts = fields.cohort(query.get('fb_cohort'), env.FIRST_COHORT_WEEK, week);
  if (!cohorts) return {}; // No cohort means the person has not opted in.
  return {
    cohorts,
    models: fields.model(query.get('fb_model')),
    os: fields.osMajor(query.get('fb_os')),
    arch: fields.arch(query.get('fb_arch')),
    countries: fields.country(request.cf?.country),
  };
}

async function count(request: Request, env: Env) {
  const claimed = SPARKLE_AGENT.exec(request.headers.get('User-Agent') ?? '')?.[1];
  if (!claimed || !(await withinLimit(request, env))) return;
  const released = await env.DB.prepare('SELECT 1 FROM releases WHERE version = ?').bind(claimed).first();
  const now = new Date();
  const week = fields.isoWeek(now);
  const statements = [env.DB.prepare(
    'INSERT INTO checks_daily (day, version, n) VALUES (?, ?, 1) ON CONFLICT (day, version) DO UPDATE SET n = n + 1',
  ).bind(utcDay(now), released ? claimed : 'other')];
  for (const [dimension, value] of Object.entries(optedInValues(request, env, week))) {
    if (!value) continue;
    statements.push(env.DB.prepare(
      `INSERT INTO ${WEEKLY_TABLES[dimension as WeeklyDimension]} (week, value, n) VALUES (?, ?, 1)
       ON CONFLICT (week, value) DO UPDATE SET n = n + 1`,
    ).bind(week, value));
  }
  await env.DB.batch(statements);
}

/** Best effort: failures are logged without request details and never reach the caller. */
export function countUpdateCheck(request: Request, env: Env) {
  return count(request, env).catch((error: unknown) => {
    console.error('update check not counted', error instanceof Error ? error.message : 'unknown error');
  });
}
