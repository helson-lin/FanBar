import { env } from 'cloudflare:workers';
import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import worker from '../src/index.ts';
import { cleanup } from '../src/reports.ts';
import { reportSchema, type Report } from '../src/schema.ts';
import { LEGACY_POLICY_VERSION, POLICY_VERSION } from '../src/policy.ts';
import { accessToken, adminHeaders } from './access.ts';
const token = 'A'.repeat(43);
function fixture(): Report {
  return {
    schemaVersion: 1, reportID: crypto.randomUUID(),
    device: { modelIdentifier: 'Mac14,13', processor: 'Test Chip', macOSVersion: '15.0.0', appVersion: '1.0', helperVersion: '10' },
    fanCount: 2, selectedTemperatureSource: 'maxChip',
    capabilities: [
      ...(['cpuTemperature', 'gpuTemperature', 'ssdTemperature', 'batteryTemperature'] as const).map(capability => ({
        capability, status: 'available' as const, reasonCode: 'SENSOR_READ_SUCCEEDED' as const,
      })),
      { capability: 'fanReadings', status: 'available', reasonCode: 'FAN_READ_SUCCEEDED' },
      { capability: 'manualControl', status: 'requestSucceeded', reasonCode: 'CONTROL_REQUEST_SUCCEEDED' },
      { capability: 'smartCooling', status: 'unverified', reasonCode: 'CONTROL_NOT_ATTEMPTED' },
    ],
  };
}
function request(path: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}): Request {
  return new Request('http://localhost' + path, { method, headers: {
    'CF-Connecting-IP': crypto.randomUUID(), 'Content-Type': 'application/json', ...headers,
  }, ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }) });
}
function submit(report: Report, publish = false, credential = token, policyVersion = POLICY_VERSION) {
  return SELF.fetch(request('/api/reports', 'POST', report, {
    Authorization: 'Bearer ' + credential, 'X-FanBar-Policy-Version': policyVersion,
    'X-FanBar-Publish-Report': publish ? '1' : '0',
  }));
}
async function review(id: string, status = 'approved', origin = 'http://localhost') {
  return SELF.fetch(request('/api/admin/reports/' + id + '/review', 'PUT', { status, reason: 'reviewed' },
    await adminHeaders({ 'X-FanBar-Admin': '1', Origin: origin })));
}
async function matrix() {
  const response = await SELF.fetch(request('/api/compatibility'));
  expect(response.status).toBe(200);
  return response.json<{ groups: { community: { status: string; count: number }[]; developerVerifications: unknown[] }[] }>();
}
beforeEach(async () => { await env.DB.batch([
  env.DB.prepare('DELETE FROM reviews'), env.DB.prepare('DELETE FROM reports'), env.DB.prepare('DELETE FROM verifications'),
  env.DB.prepare('DELETE FROM withdrawals'),
]); });
describe('consent and closed schema', () => {
  it('asks for authentication when administrator keys are configured', async () => {
    const response = await SELF.fetch(request('/api/admin/reports'));
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({error:{code:'ADMIN_AUTHENTICATION_REQUIRED'}});
  });
  it('serves the root and public pages directly with HTML normalization disabled', async () => {
    const pages: Record<string, string> = {
      '/': 'index', '/index.html': 'index', '/privacy.html': 'privacy', '/withdraw.html': 'withdraw', '/report.html': 'report',
    };
    for (const [path, page] of Object.entries(pages)) {
      const response = await SELF.fetch(request(path));
      expect(response.status).toBe(200);
      expect(response.headers.get('location')).toBeNull();
      expect(response.headers.get('Content-Security-Policy')).toContain("script-src 'self'");
      const html = await response.text();
      expect(html).toContain('<div id="root"></div>');
      expect(html).toMatch(new RegExp(`<script type="module" crossorigin src="/assets/${page}-[\\w-]+\\.js"></script>`));
      // The CSP allows only same-origin files: no inline scripts or styles in the built pages.
      expect(html).not.toMatch(/<script>|<style|style=/);
    }
  });
  it('serves every administrator entry without canonical redirect loops', async () => {
    for (const path of ['/admin', '/admin/', '/admin.html']) {
      const response = await SELF.fetch(request(path, 'GET', undefined, await adminHeaders()));
      expect(response.status).toBe(200);
      expect(response.headers.get('location')).toBeNull();
      expect(response.headers.get('Cache-Control')).toBe('no-store');
      expect(await response.text()).toMatch(/src="\/assets\/admin-[\w-]+\.js"/);
    }
  });
  it('rejects hidden personal fields instead of silently stripping them', async () => {
    const report = fixture();
    const withSerial = { ...report, device: { ...report.device, serialNumber: 'private' } };
    expect(reportSchema.safeParse(withSerial).success).toBe(false);
    expect((await SELF.fetch(request('/api/reports', 'POST', withSerial, {
      Authorization: 'Bearer ' + token, 'X-FanBar-Policy-Version': POLICY_VERSION, 'X-FanBar-Publish-Report': '0',
    }))).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reports').first('count')).toBe(0);
  });
  it('requires publication choice, current policy and owner credential', async () => {
    expect((await SELF.fetch(request('/api/reports', 'POST', fixture()))).status).toBe(409);
    expect((await SELF.fetch(request('/api/reports', 'POST', fixture(), { 'X-FanBar-Policy-Version': POLICY_VERSION }))).status).toBe(400);
    expect((await SELF.fetch(request('/api/reports', 'POST', fixture(), {
      'X-FanBar-Policy-Version': POLICY_VERSION, 'X-FanBar-Publish-Report': '0',
    }))).status).toBe(401);
  });
  it('rejects duplicate capabilities and inconsistent evidence', async () => {
    const report = fixture(); report.capabilities[0] = report.capabilities[1];
    expect((await submit(report)).status).toBe(400);
    const mismatch = fixture(); mismatch.capabilities[0].status = 'requestSucceeded';
    expect((await submit(mismatch)).status).toBe(400);
  });
  it('bounds payloads even when content length is misleading', async () => {
    const response = await SELF.fetch(request('/api/reports', 'POST', ' '.repeat(17000), {
      'Content-Length': '1', 'X-FanBar-Policy-Version': POLICY_VERSION, 'X-FanBar-Publish-Report': '0', Authorization: 'Bearer ' + token,
    }));
    expect(response.status).toBe(413);
  });
});
describe('publication and withdrawal', () => {
  it('makes retries idempotent and never returns credential hashes', async () => {
    const report = fixture(); expect((await submit(report)).status).toBe(201);
    const retry = await submit(report); expect(retry.status).toBe(200);
    const receipt = await retry.json<Record<string, unknown>>();
    expect(receipt.reportID).toBe(report.reportID);
    expect(Object.keys(receipt)).toEqual(['reportID', 'status', 'receivedAt', 'expiresAt', 'publishReport', 'policyVersion']);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reports').first('count')).toBe(1);
    expect((await submit(report, true)).status).toBe(409);
    expect((await submit(report, false, 'B'.repeat(43))).status).toBe(409);
  });
  it('keeps private reports private after review while publishing aggregate evidence', async () => {
    const report = fixture(); await submit(report);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID))).status).toBe(404);
    expect((await review(report.reportID)).status).toBe(200);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID))).status).toBe(404);
    const data = await matrix(); expect(data.groups).toHaveLength(1);
    expect(data.groups[0].community.find(row => row.status === 'requestSucceeded')?.count).toBe(1);
    expect(data.groups[0].developerVerifications).toEqual([]);
    expect(JSON.stringify(data)).not.toContain(report.reportID);
    expect(JSON.stringify(data)).not.toContain('deletion_token');
    expect(JSON.stringify(data)).not.toContain(report.device.processor);
  });
  it('publishes opted-in reports only after review', async () => {
    const report = fixture(); await submit(report, true);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID))).status).toBe(404);
    await review(report.reportID);
    const response = await SELF.fetch(request('/api/reports/' + report.reportID)); expect(response.status).toBe(200);
    expect((await response.json<{ report: Report }>()).report.reportID).toBe(report.reportID);
  });
  it('removes reports, audits and statistics only with the right credential', async () => {
    const report = fixture(); await submit(report, true); await review(report.reportID);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, {
      Authorization: 'Bearer ' + 'B'.repeat(43),
    }))).status).toBe(404);
    expect((await matrix()).groups).toHaveLength(1);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, { Authorization: 'Bearer ' + token }))).status).toBe(204);
    expect((await matrix()).groups).toHaveLength(0);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reviews').first('count')).toBe(0);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID))).status).toBe(404);
  });
  it('prevents late requests resurrecting a withdrawn report', async () => {
    const report = fixture();
    const deletion = await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, {
      Authorization: 'Bearer ' + token,
    }));
    expect(deletion.status).toBe(204);
    expect((await submit(report)).status).toBe(409);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reports').first('count')).toBe(0);
    const marker = await env.DB.prepare('SELECT * FROM withdrawals').first<Record<string, string>>();
    expect(JSON.stringify(marker)).not.toContain(report.reportID);
    expect(JSON.stringify(marker)).not.toContain(token);
  });
  it('does not let a withdrawal made with another credential block the owner', async () => {
    const report = fixture();
    const other = { Authorization: 'Bearer ' + 'B'.repeat(43) };
    expect((await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, other))).status).toBe(204);
    expect((await submit(report)).status).toBe(201);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, other))).status).toBe(404);
    expect((await SELF.fetch(request('/api/reports/' + report.reportID, 'DELETE', undefined, {
      Authorization: 'Bearer ' + token,
    }))).status).toBe(204);
    expect((await submit(report)).status).toBe(409);
  });
  it('keeps the audit of a published verification while expiring report audits', async () => {
    const headers = await adminHeaders({ 'X-FanBar-Admin': '1', Origin: 'http://localhost' });
    const created = await SELF.fetch(request('/api/admin/verifications', 'POST', {
      modelIdentifier: 'Mac14,13', macOSVersion: '15.0.0', appVersion: '1.0', helperVersion: '10',
      capability: 'manualControl', status: 'verifiedAvailable', notes: 'Independent controlled test',
      sourceURL: 'https://github.com/helson-lin/FanBar', verifiedOn: new Date().toISOString().slice(0, 10),
    }, headers));
    const { verificationID } = await created.json<{ verificationID: string }>();
    const report = fixture(); await submit(report); await review(report.reportID);
    const old = '2000-01-01T00:00:00.000Z';
    await env.DB.prepare('UPDATE reviews SET reviewed_at = ?').bind(old).run();
    await cleanup(env);
    const kept = await env.DB.prepare('SELECT object_type FROM reviews').all<{ object_type: string }>();
    expect(kept.results.map(row => row.object_type)).toEqual(['verification']);
    expect((await SELF.fetch(request('/api/admin/verifications/' + verificationID, 'DELETE', undefined, headers))).status).toBe(204);
    await env.DB.prepare('UPDATE reviews SET reviewed_at = ?').bind(old).run();
    await cleanup(env);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reviews').first('count')).toBe(0);
  });
  it('excludes expired reports before cleanup', async () => {
    const report = fixture(); await submit(report); await review(report.reportID);
    await env.DB.prepare('UPDATE reports SET expires_at = ?').bind('2000-01-01T00:00:00.000Z').run();
    expect((await matrix()).groups).toEqual([]); await cleanup(env);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reports').first('count')).toBe(0);
    expect(await env.DB.prepare('SELECT COUNT(*) AS count FROM reviews').first('count')).toBe(0);
  });
  it('preserves conflicting evidence instead of grouping by approval status', async () => {
    const first = fixture(); const second = fixture();
    second.capabilities[0] = { capability: 'cpuTemperature', status: 'notDetected', reasonCode: 'SENSOR_NOT_DETECTED' };
    await submit(first); await submit(second); await review(first.reportID); await review(second.reportID);
    expect((await matrix()).groups[0].community.some(row => row.status === 'notDetected')).toBe(true);
  });
});
describe('admin boundaries', () => {
  const code = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
  it('accepts only a valid Cloudflare Access token', async () => {
    const rejected = async (headers: Record<string, string>) => {
      const response = await SELF.fetch(request('/api/admin/reports', 'GET', undefined, headers));
      expect(response.status).toBe(403);
      expect(await code(response)).toBe('ADMIN_AUTHENTICATION_REQUIRED');
    };
    await rejected({});
    await rejected({ Authorization: 'Bearer ' + 'Z'.repeat(43) }); // There is no administrator key any more.
    await rejected({ 'Cf-Access-Jwt-Assertion': 'not-a-token' });
    await rejected({ 'Cf-Access-Jwt-Assertion': await accessToken({}, { audience: 'another-application' }) });
    await rejected({ 'Cf-Access-Jwt-Assertion': await accessToken({}, { issuer: 'https://other.cloudflareaccess.com' }) });
    await rejected({ 'Cf-Access-Jwt-Assertion': await accessToken({}, { expiresIn: Math.floor(Date.now() / 1000) - 60 }) });
    const forged = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify'],
    ) as CryptoKeyPair;
    await rejected({ 'Cf-Access-Jwt-Assertion': await accessToken({}, { key: forged.privateKey }) });
    expect((await SELF.fetch(request('/api/admin/reports', 'GET', undefined, await adminHeaders()))).status).toBe(200);
  });
  it('fails closed when Access is not configured, except for local development', async () => {
    const unconfigured = { ...env, ACCESS_TEAM_DOMAIN: '', ACCESS_AUD: '' };
    const production = await worker.fetch(request('/api/admin/session'), { ...unconfigured, ENVIRONMENT: 'production' });
    expect(production.status).toBe(403);
    expect(await code(production)).toBe('ADMIN_ACCESS_NOT_CONFIGURED');
    const remote = await worker.fetch(new Request('https://report.example.com/api/admin/session'), unconfigured);
    expect(await code(remote)).toBe('ADMIN_ACCESS_NOT_CONFIGURED');
    const local = await worker.fetch(request('/api/admin/session'), unconfigured);
    expect(await local.json()).toEqual({ actor: 'local-development', kind: 'localDevelopment', email: null, expiresAt: null });
  });
  it('describes the signed-in administrator and signs reviews with the Access email', async () => {
    const session = await (await SELF.fetch(request('/api/admin/session', 'GET', undefined, await adminHeaders()))).json<any>();
    expect(session).toMatchObject({ actor: 'maintainer@example.com', kind: 'access', email: 'maintainer@example.com' });
    expect(Date.parse(session.expiresAt)).toBeGreaterThan(Date.now());
    const report = fixture(); await submit(report); await review(report.reportID);
    expect(await env.DB.prepare('SELECT actor FROM reviews').first('actor')).toBe('maintainer@example.com');
    const noEmail = await SELF.fetch(request('/api/admin/session', 'GET', undefined, {
      'Cf-Access-Jwt-Assertion': await accessToken({ email: undefined }),
    }));
    expect((await noEmail.json<any>()).actor).toBe('7f1c2b54-0000-4000-8000-000000000001');
  });
  it('keeps the admin page closed without Access', async () => {
    const closed = await SELF.fetch(request('/admin/'));
    expect(closed.status).toBe(403);
    const body = await closed.text();
    expect(body).toContain('ADMIN_AUTHENTICATION_REQUIRED');
    expect(body).not.toMatch(/assets\/admin-/);
    const page = await SELF.fetch(request('/admin/', 'GET', undefined, await adminHeaders()));
    expect(page.status).toBe(200);
    expect(page.headers.get('Cache-Control')).toBe('no-store');
  });
  it('reads update statistics through the update service binding', async () => {
    const calls: number[] = [];
    const UPDATE_SERVICE = { stats: async (range: number) => { calls.push(range); return { range, days: [] }; } };
    const call = async (path: string, service: unknown = UPDATE_SERVICE) =>
      worker.fetch(request(path, 'GET', undefined, await adminHeaders()), { ...env, UPDATE_SERVICE: service } as unknown as Env);
    expect((await SELF.fetch(request('/api/admin/updates'))).status).toBe(403);
    expect(await (await call('/api/admin/updates?range=7')).json()).toEqual({ range: 7, days: [] });
    await call('/api/admin/updates');
    expect(calls).toEqual([7, 30]);
    expect((await call('/api/admin/updates?range=365')).status).toBe(400);
    const failing = await call('/api/admin/updates', { stats: async () => { throw new Error('down'); } });
    expect(failing.status).toBe(503);
    expect(await code(failing)).toBe('UPDATE_SERVICE_UNAVAILABLE');
  });
  it('rejects cross-origin admin mutations', async () => {
    const report = fixture(); await submit(report);
    expect((await review(report.reportID, 'approved', 'https://attacker.invalid')).status).toBe(403);
    expect((await matrix()).groups).toEqual([]);
  });
  it('does not leak internal columns in admin details', async () => {
    const report = fixture(); await submit(report);
    const response = await SELF.fetch(request('/api/admin/reports/' + report.reportID, 'GET', undefined, await adminHeaders()));
    expect(response.status).toBe(200); const text = await response.text();
    expect(text).not.toContain('payload_hash'); expect(text).not.toContain('deletion_token_hash'); expect(text).not.toContain(token);
  });
  it('keeps independent verification separate from community evidence', async () => {
    const response = await SELF.fetch(request('/api/admin/verifications', 'POST', {
      modelIdentifier: 'Mac14,13', macOSVersion: '15.0.0', appVersion: '1.0', helperVersion: '10',
      capability: 'manualControl', status: 'verifiedAvailable', notes: 'Independent controlled test',
      sourceURL: 'https://github.com/helson-lin/FanBar', verifiedOn: new Date().toISOString().slice(0, 10),
    }, await adminHeaders({ 'X-FanBar-Admin': '1', Origin: 'http://localhost' })));
    expect(response.status).toBe(201); const data = await matrix();
    expect(data.groups[0].community).toEqual([]); expect(data.groups[0].developerVerifications).toHaveLength(1);
  });
});

describe('admin insights', () => {
  const adminGet = async (path: string) => SELF.fetch(request(path, 'GET', undefined, await adminHeaders()));

  it('protects all insight endpoints and handles an empty database', async () => {
    for (const path of ['/api/admin/overview', '/api/admin/audit', '/api/admin/verifications']) {
      expect((await SELF.fetch(request(path))).status).toBe(403);
      expect((await adminGet(path)).status).toBe(200);
    }
    const overview = await (await adminGet('/api/admin/overview')).json<any>();
    expect(overview.queue).toEqual({ pending: 0, oldestPendingAt: null, inspected: 0 });
    expect(overview.daily).toHaveLength(14);
    expect(overview.week.received).toBe(0);
    expect(overview.attention.verificationCandidates).toEqual([]);
    expect((await adminGet('/api/admin/audit?type=invalid')).status).toBe(400);
  });

  it('annotates duplicates and new models without exposing raw payloads or hashes', async () => {
    const first = fixture(); const second = fixture();
    await submit(first); await submit(second);
    const response = await adminGet('/api/admin/reports');
    const list = await response.json<any>();
    expect(list.reports).toHaveLength(2);
    for (const row of list.reports) {
      expect(row.flags).toEqual(expect.arrayContaining(['duplicate', 'newModel']));
      expect(row.duplicateOf).toHaveLength(1);
      expect(row).not.toHaveProperty('payload');
      expect(row).not.toHaveProperty('deletion_token_hash');
    }
    const overview = await (await adminGet('/api/admin/overview')).json<any>();
    expect(overview.queue.pending).toBe(2);
    expect(overview.week.received).toBe(2);
    expect(overview.attention.duplicates).toHaveLength(2);
    expect(overview.attention.newModels).toHaveLength(2);
  });

  it('compares same-version evidence, excludes self and expired reports', async () => {
    const first = fixture(); await submit(first); await review(first.reportID);
    let detail = await (await adminGet('/api/admin/reports/' + first.reportID)).json<any>();
    expect(detail.comparison.otherApprovedReports).toBe(0);
    expect(detail.comparison.flags).not.toContain('conflict');
    const second = fixture();
    second.capabilities[0] = { capability: 'cpuTemperature', status: 'notDetected', reasonCode: 'SENSOR_NOT_DETECTED' };
    await submit(second);
    detail = await (await adminGet('/api/admin/reports/' + second.reportID)).json<any>();
    expect(detail.comparison.otherApprovedReports).toBe(1);
    expect(detail.comparison.conflicts).toEqual(['cpuTemperature']);
    expect(detail.comparison.capabilities[0].existing).toEqual([{ status: 'available', count: 1 }]);
    await env.DB.prepare('UPDATE reports SET expires_at = ? WHERE id = ?').bind('2000-01-01', first.reportID).run();
    detail = await (await adminGet('/api/admin/reports/' + second.reportID)).json<any>();
    expect(detail.comparison.flags).not.toContain('conflict');
    expect(detail.comparison.otherApprovedReports).toBe(0);
  });

  it('suggests independent tests without automatically verifying community requests', async () => {
    for (let index = 0; index < 5; index++) {
      const report = fixture(); await submit(report); await review(report.reportID);
    }
    const data = await (await adminGet('/api/admin/verifications')).json<any>();
    expect(data.verifications).toEqual([]);
    expect(data.candidateMinimum).toBe(5);
    expect(data.candidates).toHaveLength(1);
    expect(data.candidates[0]).toMatchObject({ capability: 'manualControl', reports: 5 });
    const audit = await (await adminGet('/api/admin/audit?type=report')).json<any>();
    expect(audit.entries).toHaveLength(5);
    expect(audit.entries[0]).toMatchObject({ objectType: 'report', status: 'approved', modelIdentifier: 'Mac14,13' });
    expect((await matrix()).groups[0].developerVerifications).toEqual([]);
    const verification = {
      modelIdentifier: 'Mac14,13', macOSVersion: '15.0.0', appVersion: '1.0', helperVersion: '10',
      capability: 'manualControl', status: 'verifiedAvailable', notes: 'Independent test',
      sourceURL: 'https://github.com/helson-lin/FanBar', verifiedOn: new Date().toISOString().slice(0, 10),
    };
    const headers = await adminHeaders({ 'X-FanBar-Admin': '1', Origin: 'http://localhost' });
    expect((await SELF.fetch(request('/api/admin/verifications', 'POST', {
      ...verification, verifiedOn: '2025-02-30',
    }, headers))).status).toBe(400);
    const published = await SELF.fetch(request('/api/admin/verifications', 'POST', verification, headers));
    expect(published.status).toBe(201);
    const { verificationID } = await published.json<{ verificationID: string }>();
    const after = await (await adminGet('/api/admin/verifications')).json<any>();
    expect(after.candidates).toEqual([]);
    expect(after.verifications[0]).toMatchObject({ id: verificationID, sourceURL: verification.sourceURL });
    expect((await adminGet('/api/admin/audit?offset=0.5')).status).toBe(200);
    expect((await adminGet('/api/admin/reports?offset=0.5')).status).toBe(200);
    const verificationAudit = await (await adminGet('/api/admin/audit?type=verification')).json<any>();
    expect(verificationAudit.entries[0]).toMatchObject({ objectID: verificationID, status: 'verifiedAvailable' });
    expect((await SELF.fetch(request('/api/admin/verifications/' + verificationID, 'DELETE', undefined, headers))).status).toBe(204);
    const removed = await (await adminGet('/api/admin/verifications')).json<any>();
    expect(removed.verifications).toEqual([]);
    expect(removed.candidates).toHaveLength(1);
  });
});


describe('public matrix pagination', () => {
  it('pages through every combination instead of dropping older ones', async () => {
    for (let index = 0; index < 21; index++) {
      const report = fixture();
      report.device = { ...report.device, appVersion: `1.${index}` };
      expect((await submit(report)).status).toBe(201);
      expect((await review(report.reportID)).status).toBe(200);
    }
    const first = await (await SELF.fetch(request('/api/compatibility'))).json<any>();
    expect(first.groups).toHaveLength(20);
    expect(first).toMatchObject({ truncated: true, nextOffset: 20 });
    const second = await (await SELF.fetch(request('/api/compatibility?offset=20'))).json<any>();
    expect(second.groups).toHaveLength(1);
    expect(second).toMatchObject({ truncated: false, nextOffset: null });
    const versions = new Set([...first.groups, ...second.groups].map((group: any) => group.appVersion));
    expect(versions.size).toBe(21);
    for (const offset of ['-1', '1.5', 'x', '100001']) {
      expect((await SELF.fetch(request('/api/compatibility?offset=' + offset))).status).toBe(400);
    }
  });
});

describe('user hands-on confirmations', () => {
  it('retains optional control confirmations without changing automatic statuses', async () => {
    const report = fixture();
    const data = { ...report, capabilities: report.capabilities.map(row => ({ ...row,
      ...(['manualControl', 'smartCooling'].includes(row.capability) ? { userConfirmedWorking: true } : {}),
    })) };
    const headers = { Authorization: 'Bearer ' + token, 'X-FanBar-Policy-Version': POLICY_VERSION, 'X-FanBar-Publish-Report': '1' };
    expect((await SELF.fetch(request('/api/reports', 'POST', data, headers))).status).toBe(201);
    expect((await SELF.fetch(request('/api/reports', 'POST', data, headers))).status).toBe(200);
    await review(report.reportID);
    const publicData = await (await SELF.fetch(request('/api/reports/' + report.reportID))).json<any>();
    expect(publicData.report.capabilities.find((row: any) => row.capability === 'manualControl')).toMatchObject({ status: 'requestSucceeded', userConfirmedWorking: true });
    expect(publicData.report.capabilities.find((row: any) => row.capability === 'smartCooling')).toMatchObject({ status: 'unverified', userConfirmedWorking: true });
    const distribution = await (await SELF.fetch(request('/api/compatibility'))).json<any>();
    expect(distribution.groups[0].community.find((row: any) => row.capability === 'manualControl').userConfirmedWorking).toBe(1);
    expect(distribution.groups[0].developerVerifications).toEqual([]);
  });
  it('rejects confirmations on results showing control could not have run', async () => {
    const contradictions = [
      { status: 'requestFailed', reasonCode: 'CONTROL_REQUEST_FAILED' },
      { status: 'requiresAuthorization', reasonCode: 'HELPER_AUTHORIZATION_REQUIRED' },
      { status: 'temporarilyUnavailable', reasonCode: 'HELPER_MISSING' },
    ] as const;
    for (const result of contradictions) {
      const report = fixture();
      report.capabilities[5] = { capability: 'manualControl', ...result, userConfirmedWorking: true };
      expect((await submit(report)).status).toBe(400);
      delete report.capabilities[5].userConfirmedWorking;
      expect((await submit(report)).status).toBe(201);
    }
  });
  it('rejects confirmations on sensors and values other than true', async () => {
    for (const [index, confirmation] of [[0, true], [5, false], [5, 'true']]) {
      const report = fixture();
      const capabilities = report.capabilities.map((row, at) => at === index ? { ...row, userConfirmedWorking: confirmation } : row);
      expect((await SELF.fetch(request('/api/reports', 'POST', { ...report, capabilities }, {
        Authorization: 'Bearer ' + token, 'X-FanBar-Policy-Version': POLICY_VERSION, 'X-FanBar-Publish-Report': '0',
      }))).status).toBe(400);
    }
  });
});


describe('machines without a built-in battery', () => {
  it('accepts an explicit non-applicable battery result and preserves it publicly', async () => {
    const report = fixture();
    report.capabilities[3] = { capability: 'batteryTemperature', status: 'notApplicable', reasonCode: 'NO_BUILT_IN_BATTERY' };
    expect((await submit(report, true)).status).toBe(201);
    await review(report.reportID);
    const data = await (await SELF.fetch(request('/api/reports/' + report.reportID))).json<{ report: Report }>();
    expect(data.report.capabilities[3]).toEqual(report.capabilities[3]);
    expect((await matrix()).groups[0].community.some(row => row.status === 'notApplicable')).toBe(true);
  });
  it('rejects using absence of a battery for other capabilities or claiming a reading', async () => {
    for (const index of [0, 4, 5]) {
      const report = fixture();
      report.capabilities[index] = { ...report.capabilities[index], status: 'notApplicable', reasonCode: 'NO_BUILT_IN_BATTERY' };
      expect((await submit(report)).status).toBe(400);
    }
    const report = fixture();
    report.capabilities[3] = { capability: 'batteryTemperature', status: 'available', reasonCode: 'NO_BUILT_IN_BATTERY' };
    expect((await submit(report)).status).toBe(400);
  });
});
describe('control failure details', () => {
  function failed(failure: NonNullable<Report['capabilities'][number]['failure']>): Report {
    const report = fixture();
    report.capabilities[5] = { capability: 'manualControl', status: 'requestFailed', reasonCode: 'CONTROL_REQUEST_FAILED', failure };
    return report;
  }
  it('keeps the legacy policy as the default response and serves the current one on request', async () => {
    const legacy = await (await SELF.fetch(request('/api/policy'))).json<{ version: string; fields: string[] }>();
    expect(legacy.version).toBe(LEGACY_POLICY_VERSION);
    expect(legacy.fields.some(field => field.includes('failure'))).toBe(false);
    const current = await (await SELF.fetch(request('/api/policy?version=' + POLICY_VERSION)))
      .json<{ version: string; fields: string[] }>();
    expect(current.version).toBe(POLICY_VERSION);
    expect(current.fields).toContain('capabilities[].failure.code');
    expect((await (await SELF.fetch(request('/api/policy?version=1999-01-01'))).json<{ version: string }>()).version)
      .toBe(LEGACY_POLICY_VERSION);
  });
  it('stores bounded failure evidence under the current policy', async () => {
    const report = failed({ code: 'UNLOCK_TIMEOUT', smcKey: 'F0Md', fanIndex: 1, durationMS: 10512, restoredAutomatic: true });
    expect((await submit(report, true)).status).toBe(201);
    await review(report.reportID);
    const data = await (await SELF.fetch(request('/api/reports/' + report.reportID))).json<{ report: Report }>();
    expect(data.report.capabilities[5].failure).toEqual(report.capabilities[5].failure);
    const row = await env.DB.prepare('SELECT policy_version FROM reports WHERE id = ?').bind(report.reportID).first('policy_version');
    expect(row).toBe(POLICY_VERSION);
  });
  it('still accepts legacy reports, but never with failure details', async () => {
    const legacy = fixture();
    expect((await submit(legacy, false, token, LEGACY_POLICY_VERSION)).status).toBe(201);
    expect(await env.DB.prepare('SELECT policy_version FROM reports WHERE id = ?').bind(legacy.reportID).first('policy_version'))
      .toBe(LEGACY_POLICY_VERSION);
    expect((await submit(failed({ code: 'HELPER_TIMEOUT' }), false, token, LEGACY_POLICY_VERSION)).status).toBe(400);
    expect((await submit(fixture(), false, token, '2026-01-01')).status).toBe(409);
  });
  it('rejects failure details on anything but a failed control and free-form evidence', async () => {
    const onSuccess = fixture();
    onSuccess.capabilities[5] = { ...onSuccess.capabilities[5], failure: { code: 'HELPER_TIMEOUT' } };
    expect((await submit(onSuccess)).status).toBe(400);
    const onSensor = fixture();
    onSensor.capabilities[0] = { ...onSensor.capabilities[0], failure: { code: 'HELPER_TIMEOUT' } };
    expect((await submit(onSensor)).status).toBe(400);
    for (const bad of [
      { code: 'HELPER_TIMEOUT', message: 'Timed out unlocking system mode for fan 1' },
      { code: 'SOMETHING_ELSE' },
      { code: 'SMC_OPERATION_FAILED', smcKey: '/Users/me' },
      { code: 'READBACK_NOT_MANUAL', readbackManual: Array(9).fill(false) },
      { code: 'UNLOCK_TIMEOUT', fanIndex: 8 },
    ]) {
      expect((await submit(failed(bad as never))).status).toBe(400);
    }
  });
});
