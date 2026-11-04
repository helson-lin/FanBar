import { countUpdateCheck } from './counting.ts';
import { runDailyTask } from './daily.ts';
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
    if (pathname === '/api/stats') return publicStats(request, env, ctx);
    if (pathname !== '/appcast.xml') return new Response('Not found', { status: 404 });
    try {
      ctx.waitUntil(countUpdateCheck(request, env));
    } catch {
      // Counting must never stop the update check from being served.
    }
    return redirect(env);
  },
  async scheduled(_controller, env, _ctx) {
    await runDailyTask(env);
  },
} satisfies ExportedHandler<Env>;
