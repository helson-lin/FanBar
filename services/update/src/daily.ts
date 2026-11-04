import { isoWeek } from './fields.ts';
import { DAY_MS, utcDay, WEEKLY_TABLES } from './storage.ts';

const RELEASES_API = 'https://api.github.com/repos/helson-lin/FanBar/releases?per_page=100';
// Plain releases (0.8.2) and pre-releases such as betas (0.9.0-beta.1, 0.9.0b1).
const VERSION = /^\d+\.\d+(\.\d+)?(-?[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$/;
const RETENTION_DAYS = 730;

/** Adds newly published versions. A failed sync keeps the existing list untouched. */
async function syncReleases(env: Env) {
  const response = await fetch(RELEASES_API, {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'fanbar-update-service' },
  });
  if (!response.ok) throw new Error(`GitHub releases returned ${response.status}`);
  const releases = await response.json<{ tag_name?: unknown }[]>();
  const versions = releases
    .map((release) => (typeof release.tag_name === 'string' ? release.tag_name.replace(/^v/, '') : ''))
    .filter((version) => VERSION.test(version));
  if (versions.length === 0) return;
  await env.DB.batch(versions.map((version) =>
    env.DB.prepare('INSERT OR IGNORE INTO releases (version) VALUES (?)').bind(version)));
}

async function deleteExpired(env: Env) {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * DAY_MS);
  const cutoffWeek = isoWeek(cutoff);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM checks_daily WHERE day < ?').bind(utcDay(cutoff)),
    ...Object.values(WEEKLY_TABLES).map((table) => env.DB.prepare(`DELETE FROM ${table} WHERE week < ?`).bind(cutoffWeek)),
  ]);
}

export async function runDailyTask(env: Env) {
  const results = await Promise.allSettled([syncReleases(env), deleteExpired(env)]);
  for (const result of results) {
    if (result.status === 'rejected') {
      console.error('daily task step failed', result.reason instanceof Error ? result.reason.message : 'unknown error');
    }
  }
}

// Per isolate: once today's run is claimed here, later requests skip the D1 write.
let claimedDay = '';

/**
 * Runs the daily task from the first update check of each UTC day: the Cloudflare
 * account has no cron trigger left. The conditional UPDATE lets exactly one request
 * claim the day, however many isolates race for it. A failed step waits until the
 * next day, like a missed cron run; the release list is kept as it was.
 */
export async function runDailyTaskOncePerDay(env: Env) {
  const today = utcDay(new Date());
  if (claimedDay === today) return;
  const claim = await env.DB.prepare("UPDATE task_runs SET day = ? WHERE task = 'daily' AND day <> ?")
    .bind(today, today).run();
  claimedDay = today;
  if (claim.meta.changes === 1) await runDailyTask(env);
}
