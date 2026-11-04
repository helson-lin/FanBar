import { WorkerEntrypoint } from 'cloudflare:workers';
import { adminStats, isAdminRange } from './admin.ts';
import { countUpdateCheck } from './counting.ts';
import { runDailyTask, runDailyTaskOncePerDay } from './daily.ts';
import { home } from './home.ts';
import { publicStats } from './stats.ts';

function redirect(env: Env) {
  return new Response(null, {
    status: 302,
    headers: { Location: env.APPCAST_URL, 'Cache-Control': 'no-store' },
  });
}

export default {
  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    if (pathname === '/') return home();
    if (pathname === '/api/stats') return publicStats(request, env, ctx);
    if (pathname !== '/appcast.xml') return new Response('Not found', { status: 404 });
    try {
      ctx.waitUntil(countUpdateCheck(request, env));
      ctx.waitUntil(runDailyTaskOncePerDay(env).catch((error: unknown) => {
        console.error('daily task not run', error instanceof Error ? error.message : 'unknown error');
      }));
    } catch {
      // Counting must never stop the update check from being served.
    }
    return redirect(env);
  },
  // Unused while the account has no cron slot (see runDailyTaskOncePerDay); kept so a
  // cron trigger can be added back without a code change.
  async scheduled(_controller, env, _ctx) {
    await runDailyTask(env);
  },
} satisfies ExportedHandler<Env>;

/**
 * Internal RPC for the maintainer admin on report.getfanbar.com, bound there as
 * UPDATE_SERVICE. A named entrypoint has no URL: only a Worker with a service binding
 * can call it, so it does no authentication of its own.
 */
export class UpdateAdmin extends WorkerEntrypoint<Env> {
  async stats(range: number) {
    if (!isAdminRange(range)) throw new RangeError('range must be 7, 30 or 90');
    return adminStats(this.env, range);
  }
}
