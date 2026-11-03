import { env } from 'cloudflare:workers';
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import worker from '../src/index.ts';

const SPARKLE_UA = (version: string) => `FanBar/${version} Sparkle/2.9.6`;

async function call(path: string, init: RequestInit = {}, workerEnv: Env = env) {
  const ctx = createExecutionContext();
  const response = await worker.fetch(new Request(`http://localhost${path}`, init) as Request<unknown, IncomingRequestCfProperties>, workerEnv, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

function check(query = '', userAgent = SPARKLE_UA('0.8.0'), ip = crypto.randomUUID(), country = 'JP') {
  return call(`/appcast.xml${query}`, { headers: { 'User-Agent': userAgent, 'CF-Connecting-IP': ip }, cf: { country } } as RequestInit);
}

async function checks(count: number, query = '', userAgent = SPARKLE_UA('0.8.0')) {
  for (let i = 0; i < count; i++) await check(query, userAgent);
}

async function stats() {
  const response = await call('/api/stats');
  expect(response.status).toBe(200);
  return response.json<any>();
}

const today = () => new Date().toISOString().slice(0, 10);

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

function at(isoTime: string) {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(isoTime));
}

beforeEach(async () => {
  await env.DB.batch([
    ...['checks_daily', 'cohort_weekly', 'model_weekly', 'os_weekly', 'arch_weekly', 'country_weekly']
      .map((table) => env.DB.prepare(`DELETE FROM ${table}`)),
    env.DB.prepare('DELETE FROM releases'),
    env.DB.prepare("INSERT INTO releases (version) VALUES ('0.7.0'), ('0.8.0')"),
  ]);
});

it('redirects every update check to the GitHub appcast without caching or query', async () => {
  const response = await check('?fb_cohort=2026-W46&fb_model=Mac14,2');
  expect(response.status).toBe(302);
  expect(response.headers.get('Location')).toBe(env.APPCAST_URL);
  expect(response.headers.get('Cache-Control')).toBe('no-store');
});

it('counts each Sparkle check toward today and its released version', async () => {
  await checks(6);
  await checks(5, '', SPARKLE_UA('0.7.0'));
  expect((await stats()).checksDaily).toEqual(expect.arrayContaining([
    { day: today(), version: '0.8.0', n: 6 },
    { day: today(), version: '0.7.0', n: 5 },
  ]));
});

it('hides any group with fewer than five checks', async () => {
  await checks(4);
  const body = await stats();
  expect(body.minimumGroupSize).toBe(5);
  expect(body.checksDaily).toEqual([]);
});

it('redirects but never counts checks that are not from FanBar Sparkle', async () => {
  for (const agent of ['Mozilla/5.0 (Macintosh)', 'curl/8.7.1', 'UptimeProbe/1.0', 'Other/0.8.0 Sparkle/2.9.6']) {
    const response = await check('', agent);
    expect(response.status).toBe(302);
  }
  await checks(5, '', 'curl/8.7.1');
  expect((await stats()).checksDaily).toEqual([]);
});

it('folds unreleased or malformed versions into other', async () => {
  await checks(3, '', SPARKLE_UA('9.9.9'));
  await checks(2, '', SPARKLE_UA('<script>'));
  expect((await stats()).checksDaily).toEqual([{ day: today(), version: 'other', n: 5 }]);
});

it('still redirects when the database fails', async () => {
  const brokenDB = { prepare() { throw new Error('D1 unavailable'); }, batch() { throw new Error('D1 unavailable'); } };
  const response = await call('/appcast.xml', { headers: { 'User-Agent': SPARKLE_UA('0.8.0') } },
    { ...env, DB: brokenDB as unknown as D1Database });
  expect(response.status).toBe(302);
  expect(response.headers.get('Location')).toBe(env.APPCAST_URL);
});

it('stops counting a flooding address but keeps redirecting it', async () => {
  const ip = '203.0.113.7';
  for (let i = 0; i < 15; i++) expect((await check('', SPARKLE_UA('0.8.0'), ip)).status).toBe(302);
  expect((await stats()).checksDaily).toEqual([{ day: today(), version: '0.8.0', n: 10 }]);
});

const OPTED_IN = '?fb_cohort=2026-W46&fb_model=Mac14,2&fb_os=27&fb_arch=arm64';

it('counts opted-in fields separately for the current UTC week', async () => {
  at('2026-11-18T12:00:00Z');
  await checks(5, OPTED_IN);
  const body = await stats();
  const week = '2026-W47';
  expect(body.cohorts).toEqual([{ week, value: '2026-W46', n: 5 }]);
  expect(body.models).toEqual([{ week, value: 'Mac14,2', n: 5 }]);
  expect(body.os).toEqual([{ week, value: '27', n: 5 }]);
  expect(body.arch).toEqual([{ week, value: 'arm64', n: 5 }]);
  expect(body.countries).toEqual([{ week, value: 'JP', n: 5 }]);
});

it('drops each invalid opted-in field on its own', async () => {
  at('2026-11-18T12:00:00Z');
  await checks(5, '?fb_cohort=2026-W46&fb_model=iPhone15,2&fb_os=99&fb_arch=ppc');
  await checks(5, '?fb_cohort=2026-W46&fb_model=Mac99,9&fb_os=abc&fb_arch=x86_64');
  const body = await stats();
  expect(body.checksDaily).toEqual([{ day: '2026-11-18', version: '0.8.0', n: 10 }]);
  expect(body.cohorts).toEqual([{ week: '2026-W47', value: '2026-W46', n: 10 }]);
  expect(body.models).toEqual([{ week: '2026-W47', value: 'other', n: 5 }]);
  expect(body.os).toEqual([]);
  expect(body.arch).toEqual([{ week: '2026-W47', value: 'x86_64', n: 5 }]);
});

it('accepts cohorts only from legacy or the first week through the current week', async () => {
  at('2026-11-18T12:00:00Z'); // 2026-W47; FIRST_COHORT_WEEK is 2026-W46
  for (const value of ['legacy', '2026-W46', '2026-W47']) await checks(5, `?fb_cohort=${value}`);
  for (const value of ['2026-W45', '2026-W48', '2026-W7', '2026-W54', 'W46', '']) {
    await checks(5, `?fb_cohort=${value}&fb_arch=arm64`);
  }
  const body = await stats();
  expect(body.cohorts.map((row: any) => row.value).sort()).toEqual(['2026-W46', '2026-W47', 'legacy']);
  expect(body.arch).toEqual([]);
});

it('ignores every opted-in field and the country when no cohort is sent', async () => {
  at('2026-11-18T12:00:00Z');
  await checks(5, '?fb_model=Mac14,2&fb_os=27&fb_arch=arm64');
  const body = await stats();
  expect(body.checksDaily).toEqual([{ day: '2026-11-18', version: '0.8.0', n: 5 }]);
  for (const name of ['cohorts', 'models', 'os', 'arch', 'countries']) expect(body[name]).toEqual([]);
});

it('splits weeks at Monday 00:00 UTC, including across the ISO year', async () => {
  const weekOf = async (isoTime: string) => {
    at(isoTime);
    await env.DB.prepare('DELETE FROM cohort_weekly').run();
    await checks(5, '?fb_cohort=legacy');
    return (await stats()).cohorts[0].week;
  };
  expect(await weekOf('2026-11-22T23:59:59Z')).toBe('2026-W47');
  expect(await weekOf('2026-11-23T00:00:00Z')).toBe('2026-W48');
  expect(await weekOf('2026-12-31T12:00:00Z')).toBe('2026-W53');
  expect(await weekOf('2027-01-03T23:59:59Z')).toBe('2026-W53');
  expect(await weekOf('2027-01-04T00:00:00Z')).toBe('2027-W01');
});

it('serves only the appcast and stats paths', async () => {
  for (const path of ['/', '/appcast', '/api/stats/extra', '/admin']) expect((await call(path)).status).toBe(404);
  expect((await call('/appcast.xml', { method: 'HEAD' })).status).toBe(302);
});

it('publishes stats cacheably to the site origin only', async () => {
  const response = await call('/api/stats');
  expect(response.headers.get('Access-Control-Allow-Origin')).toBe(env.STATS_ORIGIN);
  expect(response.headers.get('Cache-Control')).toBe('public, max-age=3600');
});

it('limits stats to the last 180 days and 26 weeks', async () => {
  at('2026-05-01T12:00:00Z');
  await checks(5, '?fb_cohort=legacy');
  at('2026-11-18T12:00:00Z');
  await checks(5, '?fb_cohort=legacy');
  const body = await stats();
  expect(body.checksDaily.map((row: any) => row.day)).toEqual(['2026-11-18']);
  expect(body.cohorts.map((row: any) => row.week)).toEqual(['2026-W47']);
});

async function runDailyTask() {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController({ cron: '23 4 * * *' }), env, ctx);
  await waitOnExecutionContext(ctx);
}

function githubReleases(tags: string[]) {
  return vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json(tags.map((tag_name) => ({ tag_name }))));
}

it('learns newly published versions from GitHub every day', async () => {
  const fetch = githubReleases(['v0.9.0', 'v0.8.0', 'nightly-build']);
  await runDailyTask();
  expect(String(fetch.mock.calls[0][0])).toBe('https://api.github.com/repos/helson-lin/FanBar/releases?per_page=100');
  vi.restoreAllMocks();
  await checks(5, '', SPARKLE_UA('0.9.0'));
  await checks(5, '', SPARKLE_UA('nightly-build'));
  expect((await stats()).checksDaily.map((row: any) => row.version).sort()).toEqual(['0.9.0', 'other']);
});

it('keeps the known versions when GitHub is unavailable', async () => {
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('rate limited', { status: 403 }));
  await runDailyTask();
  vi.restoreAllMocks();
  await checks(5);
  expect((await stats()).checksDaily).toEqual([{ day: today(), version: '0.8.0', n: 5 }]);
});

it('deletes counts older than 730 days', async () => {
  githubReleases([]);
  at('2024-11-01T12:00:00Z');
  await checks(5, '?fb_cohort=legacy');
  at('2026-11-18T12:00:00Z');
  await checks(5, '?fb_cohort=legacy');
  await runDailyTask();
  // Retention is invisible through /api/stats (180-day window), so read storage directly here only.
  const days = await env.DB.prepare('SELECT day FROM checks_daily').all();
  const weeks = await env.DB.prepare('SELECT week FROM cohort_weekly').all();
  expect(days.results).toEqual([{ day: '2026-11-18' }]);
  expect(weeks.results).toEqual([{ week: '2026-W47' }]);
});
