import { env } from 'cloudflare:workers';
import { SELF } from 'cloudflare:test';
import { beforeEach, expect, it } from 'vitest';
import { DIAGNOSTIC_DAILY_LIMIT, DIAGNOSTIC_POLICY, DIAGNOSTIC_STORED_LIMIT } from '../src/diagnostics.ts';
import { cleanup } from '../src/reports.ts';
import { adminHeaders } from './access.ts';
const credential = 'D'.repeat(43);
function fixture() {
  return { schemaVersion: 1, diagnosticID: crypto.randomUUID(), capturedAt: new Date().toISOString(),
    device: { modelIdentifier: 'Mac16,10', processor: 'Apple M4', macOSVersion: '27.0.0', appVersion: '0.5.1', helperVersion: '26' },
    helperState: 'enabled', fanCount: 1,
    thermal: { sampledAt: new Date().toISOString(), cpuCelsius: 42, hasBuiltInBattery: false },
    probes: [{ sensor: 'cpu', key: 'Tp09', result: 'readFailed', code: -1 }],
  };
}
function request(path: string, method = 'GET', body?: unknown, token = credential, policy = DIAGNOSTIC_POLICY) {
  return SELF.fetch(new Request('http://localhost' + path, { method, headers: {
    'Content-Type': 'application/json', 'CF-Connecting-IP': crypto.randomUUID(),
    Authorization: 'Bearer ' + token, 'X-FanBar-Policy-Version': policy,
  }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }));
}
async function adminRequest(path: string) {
  return SELF.fetch(new Request('http://localhost' + path, { headers: await adminHeaders({ 'CF-Connecting-IP': crypto.randomUUID() }) }));
}
beforeEach(async () => { await env.DB.batch([
  env.DB.prepare('DELETE FROM diagnostics'), env.DB.prepare('DELETE FROM diagnostic_withdrawals'),
]); });
it('keeps diagnostics private, idempotent and available only to admins', async () => {
  const body = fixture();
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(200);
  expect((await request('/api/diagnostics/' + body.diagnosticID)).status).toBe(404);
  expect((await request('/api/admin/diagnostics')).status).toBe(403);
  const admin = await adminRequest('/api/admin/diagnostics?id=' + body.diagnosticID);
  expect(admin.status).toBe(200);
  expect(await admin.json()).toMatchObject({ diagnostic: body });
  const list = await adminRequest('/api/admin/diagnostics');
  const text = await list.text();
  expect(text).toContain(body.diagnosticID);
  expect(text).not.toContain('token');
  expect(text).not.toContain('payload');
});
it('rejects private extra fields, obsolete policy, excessive probes and bytes', async () => {
  const body = fixture();
  expect((await request('/api/diagnostics', 'POST', { ...body, userName: 'private' })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', { ...body, probes: [{ ...body.probes[0], filePath: '/private' }] })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', body, credential, 'old')).status).toBe(409);
  expect((await request('/api/diagnostics', 'POST', { ...body, probes: Array(321).fill(body.probes[0]) })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', { ...body, extra: 'x'.repeat(262144) })).status).toBe(413);
});
it('withdraws idempotently and blocks late arrivals', async () => {
  const body = fixture();
  await request('/api/diagnostics', 'POST', body);
  expect((await request('/api/diagnostics/' + body.diagnosticID, 'DELETE', undefined, 'X'.repeat(43))).status).toBe(404);
  expect((await request('/api/diagnostics/' + body.diagnosticID, 'DELETE')).status).toBe(204);
  expect((await request('/api/diagnostics/' + body.diagnosticID, 'DELETE')).status).toBe(204);
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(409);
  const late = fixture();
  await request('/api/diagnostics/' + late.diagnosticID, 'DELETE');
  expect((await request('/api/diagnostics', 'POST', late)).status).toBe(409);
});
it('does not let a withdrawal made with another credential block the owner', async () => {
  const body = fixture();
  expect((await request('/api/diagnostics/' + body.diagnosticID, 'DELETE', undefined, 'X'.repeat(43))).status).toBe(204);
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  expect((await request('/api/diagnostics/' + body.diagnosticID, 'DELETE')).status).toBe(204);
});
it('rejects conflicting payloads or credentials and cleans up expired data', async () => {
  const body = fixture();
  await request('/api/diagnostics', 'POST', body);
  expect((await request('/api/diagnostics', 'POST', { ...body, fanCount: 2 })).status).toBe(409);
  expect((await request('/api/diagnostics', 'POST', body, 'X'.repeat(43))).status).toBe(409);
  await env.DB.prepare("UPDATE diagnostics SET expires_at = '2000-01-01T00:00:00Z'").run();
  expect((await adminRequest('/api/admin/diagnostics?id=' + body.diagnosticID)).status).toBe(404);
  await cleanup(env);
  expect(await env.DB.prepare('SELECT id FROM diagnostics').first()).toBeNull();
});

it('retains raw sensor evidence, discovery limits, fallback failures and recent samples', async () => {
  const body = { ...fixture(),
    probes: [{ sensor: 'unclassified', key: 'Tm99', source: 'smc', stage: 'readBytes',
      result: 'unsupportedFormat', dataType: '75313620', dataSize: 2, rawBytes: '1234', recognized: false },
      { sensor: 'battery', source: 'batteryPack', stage: 'serviceMatch', result: 'serviceMissing' }],
    discovery: { reportedKeyCount: 5000, scannedKeyCount: 4096, truncated: true },
    recentSamples: [{ sampledAt: new Date().toISOString(), errorCode: 5, stage: 'connect' }],
  };
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  const response = await adminRequest('/api/admin/diagnostics?id=' + body.diagnosticID);
  expect(await response.json()).toMatchObject({ diagnostic: body });
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), probes: [{ ...body.probes[0], rawBytes: 'secret-user-name' }] })).status).toBe(400);
});

it('accepts bounded runtime evidence but rejects raw errors, paths and crash identities', async () => {
  const body = { ...fixture(),
    runtimeEvents: [{ timestamp: new Date().toISOString(), sessionID: crypto.randomUUID(), requestID: crypto.randomUUID(),
      component: 'xpc', action: 'timeout', outcome: 'failed', code: 4099, durationMS: 3000 }],
    runtimeContext: { appBuild: '27', osBuild: '26A425', architecture: 'arm64', bundleLocation: 'translocated', helperPresent: true },
    helperLogAvailable: false, crashLogAvailable: true,
    crashes: [{ recordedAt: new Date().toISOString(), process: 'FanBar', exception: 'EXC_CRASH', signal: 'SIGABRT',
      terminationNamespace: 'DYLD', terminationCode: 1, frames: [{ image: 'dyld', offset: 1234 }] }],
  };
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  const detail = await adminRequest('/api/admin/diagnostics?id=' + body.diagnosticID);
  expect(await detail.json()).toMatchObject({ diagnostic: body });
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), runtimeEvents: [{ ...body.runtimeEvents[0], message: '/Users/private' }] })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), crashes: [{ ...body.crashes[0], incidentID: 'private' }] })).status).toBe(400);
});

async function seedDiagnostics(count: number, createdAt: string) {
  const expires = new Date(Date.now() + 86400000).toISOString();
  const rows = Array.from({ length: count }, () => env.DB.prepare(`INSERT INTO diagnostics
    (id, payload, payload_hash, deletion_token_hash, model_identifier, created_at, expires_at)
    VALUES (?, '{}', 'h', 't', 'Mac16,10', ?, ?)`).bind(crypto.randomUUID(), createdAt, expires));
  for (let index = 0; index < rows.length; index += 500) await env.DB.batch(rows.slice(index, index + 500));
}
it('stops anonymous uploads at the daily ceiling but keeps retries idempotent', async () => {
  const stored = fixture();
  expect((await request('/api/diagnostics', 'POST', stored)).status).toBe(201);
  await seedDiagnostics(DIAGNOSTIC_DAILY_LIMIT, new Date().toISOString());
  const rejected = await request('/api/diagnostics', 'POST', fixture());
  expect(rejected.status).toBe(503);
  expect(rejected.headers.get('Retry-After')).toBe('3600');
  expect(await rejected.json()).toEqual({ error: { code: 'DIAGNOSTIC_CAPACITY_REACHED' } });
  expect((await request('/api/diagnostics', 'POST', stored)).status).toBe(200);
});
it('stops anonymous uploads at the stored ceiling', async () => {
  await seedDiagnostics(DIAGNOSTIC_STORED_LIMIT, '2000-01-01T00:00:00.000Z');
  expect((await request('/api/diagnostics', 'POST', fixture())).status).toBe(503);
});
it('limits diagnostic uploads per network address more strictly than reports', async () => {
  const address = crypto.randomUUID();
  const statuses: number[] = [];
  for (let attempt = 0; attempt < 3; attempt += 1) {
    statuses.push((await SELF.fetch(new Request('http://localhost/api/diagnostics', { method: 'POST', headers: {
      'Content-Type': 'application/json', 'CF-Connecting-IP': address,
      Authorization: 'Bearer ' + credential, 'X-FanBar-Policy-Version': DIAGNOSTIC_POLICY,
    }, body: JSON.stringify(fixture()) }))).status);
  }
  expect(statuses).toEqual([201, 201, 429]);
});

it('accepts the running helper build and separates scan from probe truncation', async () => {
  const body = { ...fixture(),
    runningHelper: { status: 'reported', build: '26' },
    discovery: { reportedKeyCount: 1369, scannedKeyCount: 1369, truncated: false, probesTruncated: true },
  };
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  const detail = await adminRequest('/api/admin/diagnostics?id=' + body.diagnosticID);
  expect(await detail.json()).toMatchObject({ diagnostic: body });
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), runningHelper: { status: 'noReply' } })).status).toBe(201);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), runningHelper: { status: 'connectionFailed', code: 4097 } })).status).toBe(201);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), runningHelper: { status: 'reported', build: '/Users/me' } })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), runningHelper: { status: 'running' } })).status).toBe(400);
});

it('accepts HID sensor probes by label but rejects arbitrary names', async () => {
  const hid = { sensor: 'cpu', name: 'pACC MTR Temp Sensor0', result: 'available', value: 41.5, source: 'hid', stage: 'readEvent', recognized: true };
  const body = { ...fixture(), probes: [...Array(300).fill(fixture().probes[0]), hid] };
  expect((await request('/api/diagnostics', 'POST', body)).status).toBe(201);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), probes: [{ ...hid, name: '/Users/me' }] })).status).toBe(400);
  expect((await request('/api/diagnostics', 'POST', { ...fixture(), probes: [{ ...hid, name: 'x'.repeat(49) }] })).status).toBe(400);
});
