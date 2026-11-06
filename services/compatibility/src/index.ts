import { deleteDiagnostic, diagnosticList, diagnosticPolicy, submitDiagnostic } from './diagnostics.ts';
import { administrator, rateLimit, requireAdminMutation } from './auth.ts';
import { createVerification, deleteVerification, reportDetail, reportList, reviewReport } from './admin.ts';
import { boundedJSON, HttpError, json, secureResponse } from './http.ts';
import { auditLog, overview, verificationList } from './insights.ts';
import { publicMatrix } from './matrix.ts';
import { updateStats } from './updates.ts';
import { DIAGNOSTIC_MAXIMUM_BYTES, policy } from './policy.ts';
import { cleanup, deleteReport, ownerReceipt, publicReport, submitReport } from './reports.ts';

const reportPath = /^\/api\/reports\/([0-9a-f-]{36})(\/receipt)?$/i;
const adminReportPath = /^\/api\/admin\/reports\/([0-9a-f-]{36})(\/review)?$/i;
const verificationPath = /^\/api\/admin\/verifications\/([0-9a-f-]{36})$/i;
async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === '/api/diagnostics/policy' && request.method === 'GET') return json(diagnosticPolicy(url.origin));
  if (path === '/api/diagnostics' && request.method === 'POST') {
    // Large anonymous payloads get a stricter per-address limiter than reports.
    await rateLimit(request, env, 'diagnostic');
    return submitDiagnostic(request, env, await boundedJSON(request, DIAGNOSTIC_MAXIMUM_BYTES));
  }
  const diagnosticMatch = path.match(/^\/api\/diagnostics\/([0-9a-f-]{36})$/i);
  if (diagnosticMatch && request.method === 'DELETE') {
    await rateLimit(request, env, 'write');
    return deleteDiagnostic(request, env, diagnosticMatch[1]);
  }
  if (path === '/api/policy'  && request.method === 'GET') return json(policy(url.origin, url.searchParams.get('version')));
  if (path === '/api/reports' && request.method === 'POST') {
    await rateLimit(request, env, 'write');
    return submitReport(request, env, await boundedJSON(request));
  }
  const reportMatch = path.match(reportPath);
  if (reportMatch) {
    await rateLimit(request, env, request.method === 'GET' ? 'read' : 'write');
    if (request.method === 'DELETE' && !reportMatch[2]) return deleteReport(request, env, reportMatch[1]);
    if (request.method === 'GET') return reportMatch[2]
      ? ownerReceipt(request, env, reportMatch[1]) : publicReport(env, reportMatch[1]);
    throw new HttpError(405, 'METHOD_NOT_ALLOWED');
  }
  if (path === '/api/compatibility' && request.method === 'GET') {
    await rateLimit(request, env, 'read');
    const model = url.searchParams.get('model') ?? '';
    if (model.length > 64) throw new HttpError(400, 'INVALID_MODEL');
    const offset = Number(url.searchParams.get('offset') ?? 0);
    if (!Number.isInteger(offset) || offset < 0 || offset > 100000) throw new HttpError(400, 'INVALID_OFFSET');
    return publicMatrix(env, model, offset);
  }
  if (path.startsWith('/api/admin/')) {
    await rateLimit(request, env, request.method === 'GET' ? 'read' : 'write');
    const admin = await administrator(request, env);
    const actor = admin.actor;
    if (request.method !== 'GET') requireAdminMutation(request);
    if (path === '/api/admin/session' && request.method === 'GET') return json(admin);
    if (path === '/api/admin/updates' && request.method === 'GET') return updateStats(env, url);
    if (path === '/api/admin/diagnostics' && request.method === 'GET') return diagnosticList(env, url);
    if (path === '/api/admin/overview' && request.method === 'GET') return overview(env);
    if (path === '/api/admin/audit' && request.method === 'GET') return auditLog(env, url);
    if (path === '/api/admin/verifications' && request.method === 'GET') return verificationList(env);
    if (path === '/api/admin/reports' && request.method === 'GET') return reportList(env, url);
    const match = path.match(adminReportPath);
    if (match && request.method === 'GET' && !match[2]) return reportDetail(env, match[1]);
    if (match && request.method === 'PUT' && match[2]) return reviewReport(request, env, match[1], actor);
    if (path === '/api/admin/verifications' && request.method === 'POST') return createVerification(request, env, actor);
    const verification = path.match(verificationPath);
    if (verification && request.method === 'DELETE') return deleteVerification(env, verification[1], actor);
    throw new HttpError(404, 'NOT_FOUND');
  }
  if (path.startsWith('/api/')) throw new HttpError(404, 'NOT_FOUND');
  if (path === '/admin' || path === '/admin/' || path === '/admin.html') {
    // Access normally stops a signed-out visitor at the edge; this keeps the page closed anyway.
    // The refusal is a short static page, never the admin bundle.
    try { await administrator(request, env); }
    catch (error) {
      if (error instanceof HttpError) return closedAdminPage(error);
      throw error;
    }
    const asset = new URL('/admin.html', request.url);
    const response = await env.ASSETS.fetch(new Request(asset, request));
    const headers = new Headers(response.headers);
    headers.set('Cache-Control', 'no-store');
    return new Response(response.body, { status: response.status, headers });
  }
  // HTML canonical redirects are disabled because admin routes resolve assets
  // internally. Resolve the root explicitly rather than relying on that behavior.
  if (path === '/') return env.ASSETS.fetch(new Request(new URL('/index.html', request.url), request));
  return env.ASSETS.fetch(request);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try { return secureResponse(await route(request, env)); }
    catch (error) {
      if (error instanceof HttpError) {
        const response = json({ error: { code: error.code } }, error.status);
        if (error.status === 429) response.headers.set('Retry-After', '60');
        if (error.code === 'DIAGNOSTIC_CAPACITY_REACHED') response.headers.set('Retry-After', '3600');
        return secureResponse(response);
      }
      // Explicit logs contain no payload, credentials, request URL, IP or exception text.
      console.error(JSON.stringify({ event: 'requestFailed', code: 'INTERNAL_ERROR' }));
      return secureResponse(json({ error: { code: 'INTERNAL_ERROR' } }, 500));
    }
  },
  async scheduled(_event, env): Promise<void> { await cleanup(env); },
} satisfies ExportedHandler<Env>;

const closedAdminText: Record<string, [string, string]> = {
  ADMIN_ACCESS_NOT_CONFIGURED: [
    'Cloudflare Access is not configured for this admin. Every admin route returns 403; there is no key sign-in.',
    'Create a self-hosted Access application for /admin* and /api/admin/*, allow only the maintainer email, then set ACCESS_TEAM_DOMAIN and ACCESS_AUD and redeploy.',
  ],
  ADMIN_AUTHENTICATION_REQUIRED: [
    'Sign in through Cloudflare Access to open the admin.',
    'If you just signed in, your session may have expired. Reload the page to sign in again.',
  ],
};

function closedAdminPage(error: HttpError): Response {
  const [title, detail] = closedAdminText[error.code] ?? ['The admin is unavailable.', ''];
  const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">`
    + `<title>FanBar admin</title><h1>FanBar admin</h1><p>${title}</p><p>${detail}</p><p><code>${error.code}</code></p></html>`;
  return new Response(html, {
    status: error.status,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
