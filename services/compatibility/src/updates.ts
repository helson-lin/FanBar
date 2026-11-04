import { HttpError, json } from './http.ts';

/**
 * The update service owns its database and schema; the admin reads its aggregates
 * through the UPDATE_SERVICE binding to its UpdateAdmin entrypoint (see
 * services/update/src/admin.ts for the response shape). That entrypoint has no URL,
 * so the only caller is this Worker, after Cloudflare Access has been verified.
 */
interface UpdateAdminRPC {
  stats(range: number): Promise<unknown>;
}

const RANGES = new Set([7, 30, 90]);

export async function updateStats(env: Env, url: URL): Promise<Response> {
  const range = Number(url.searchParams.get('range') ?? 30);
  if (!RANGES.has(range)) throw new HttpError(400, 'INVALID_RANGE');
  const service = env.UPDATE_SERVICE as unknown as UpdateAdminRPC | undefined;
  try {
    if (!service) throw new Error('binding missing');
    return json(await service.stats(range));
  } catch {
    // A failure on the update side must not break the compatibility admin around it.
    console.error(JSON.stringify({ event: 'updateStatsFailed', code: 'UPDATE_SERVICE_UNAVAILABLE' }));
    throw new HttpError(503, 'UPDATE_SERVICE_UNAVAILABLE');
  }
}
