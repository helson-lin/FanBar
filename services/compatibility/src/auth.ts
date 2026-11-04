import { createRemoteJWKSet, jwtVerify } from 'jose';
import { HttpError } from './http.ts';

// One key set per isolate: jose caches and rotates the fetched keys itself, so
// admin requests don't each refetch the Access certificates.
const accessKeys = new Map<string, ReturnType<typeof createRemoteJWKSet>>();
function accessKeySet(teamDomain: string) {
  let keys = accessKeys.get(teamDomain);
  if (!keys) {
    keys = createRemoteJWKSet(new URL(`${teamDomain}/cdn-cgi/access/certs`));
    accessKeys.set(teamDomain, keys);
  }
  return keys;
}

export function localDevelopment(request: Request, env: Env): boolean {
  return env.ENVIRONMENT === 'development'
    && ['localhost', '127.0.0.1', '[::1]'].includes(new URL(request.url).hostname);
}

const accessConfigured = (env: Env) =>
  Boolean(env.ACCESS_AUD) && /^https:\/\/[a-z0-9-]+\.cloudflareaccess\.com$/.test(env.ACCESS_TEAM_DOMAIN);

export interface Administrator {
  /** Written to the audit log: the Access email, or the subject when the token has none. */
  actor: string;
  kind: 'access' | 'localDevelopment';
  email: string | null;
  /** When the Access session token stops being accepted. */
  expiresAt: string | null;
}

/**
 * Cloudflare Access is the only way in. There is no administrator key: the Access
 * application covers /admin* and /api/admin/*, and this still verifies the JWT itself
 * (signature, issuer, audience) instead of trusting that the gateway ran.
 * Local development without Access configured is let through, never in production.
 */
export async function administrator(request: Request, env: Env): Promise<Administrator> {
  if (!accessConfigured(env)) {
    if (localDevelopment(request, env)) {
      return { actor: 'local-development', kind: 'localDevelopment', email: null, expiresAt: null };
    }
    throw new HttpError(403, 'ADMIN_ACCESS_NOT_CONFIGURED');
  }
  const token = request.headers.get('Cf-Access-Jwt-Assertion');
  if (!token) throw new HttpError(403, 'ADMIN_AUTHENTICATION_REQUIRED');
  try {
    const { payload } = await jwtVerify(token, accessKeySet(env.ACCESS_TEAM_DOMAIN), {
      issuer: env.ACCESS_TEAM_DOMAIN, audience: env.ACCESS_AUD, algorithms: ['RS256'],
    });
    if (!payload.sub) throw new Error('missing subject');
    const email = typeof payload.email === 'string' && payload.email ? payload.email : null;
    return {
      actor: email ?? payload.sub, kind: 'access', email,
      expiresAt: payload.exp ? new Date(payload.exp * 1000).toISOString() : null,
    };
  } catch { throw new HttpError(403, 'ADMIN_AUTHENTICATION_REQUIRED'); }
}
export function requireAdminMutation(request: Request): void {
  if (request.headers.get('X-FanBar-Admin') !== '1'
      || request.headers.get('Origin') !== new URL(request.url).origin) {
    throw new HttpError(403, 'SAME_ORIGIN_REQUIRED');
  }
}
export type Limiter = 'read' | 'write' | 'diagnostic';
export async function rateLimit(request: Request, env: Env, limiter: Limiter): Promise<void> {
  if (!env.LIMIT_SALT) throw new HttpError(503, 'SERVICE_NOT_CONFIGURED');
  const address = request.headers.get('CF-Connecting-IP') ?? (localDevelopment(request, env) ? 'local' : 'unknown');
  // This keyed daily value only reaches the short-lived limiter, never D1 or logs.
  const keyMaterial = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(env.LIMIT_SALT), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const key = new Uint8Array(await crypto.subtle.sign(
    'HMAC', keyMaterial, new TextEncoder().encode(`${new Date().toISOString().slice(0, 10)}:${address}`)
  ));
  const binding = { read: env.READ_LIMIT, write: env.WRITE_LIMIT, diagnostic: env.DIAGNOSTIC_LIMIT }[limiter];
  const result = await binding.limit({
    key: Array.from(key, byte => byte.toString(16).padStart(2, '0')).join(''),
  });
  if (!result.success) throw new HttpError(429, 'RATE_LIMITED');
}
