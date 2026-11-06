import { canonical, HttpError, json, reportToken, sameHash, sha256, withdrawalKey } from './http.ts';
import { ACCEPTED_POLICY_VERSIONS, POLICY_VERSION, RETENTION_DAYS } from './policy.ts';
import { reportSchema, validEvidence } from './schema.ts';

export interface ReportRow {
  model_identifier: string; os_version: string; app_version: string; helper_version: string;
  id: string; payload: string; payload_hash: string; deletion_token_hash: string;
  publish_report: number; policy_version: string; status: string; created_at: string; expires_at: string;
}
export async function findReport(env: Env, id: string): Promise<ReportRow | null> {
  return env.DB.prepare('SELECT * FROM reports WHERE id = ? AND expires_at > ?')
    .bind(id.toLowerCase(), new Date().toISOString()).first<ReportRow>();
}
export async function submitReport(request: Request, env: Env, body: unknown): Promise<Response> {
  const policyVersion = request.headers.get('X-FanBar-Policy-Version') ?? '';
  if (!ACCEPTED_POLICY_VERSIONS.includes(policyVersion)) throw new HttpError(409, 'POLICY_CHANGED');
  const visibility = request.headers.get('X-FanBar-Publish-Report');
  if (visibility !== '0' && visibility !== '1') throw new HttpError(400, 'PUBLICATION_CHOICE_REQUIRED');
  const parsed = reportSchema.safeParse(body);
  if (!parsed.success || !validEvidence(parsed.data)) throw new HttpError(400, 'INVALID_REPORT');
  // Failure details were not part of the rules a legacy-version submitter agreed to.
  if (policyVersion !== POLICY_VERSION && parsed.data.capabilities.some(row => row.failure)) {
    throw new HttpError(400, 'INVALID_REPORT');
  }
  const payload = parsed.data;
  payload.reportID = payload.reportID.toLowerCase();
  const id = payload.reportID;
  const text = canonical(payload);
  const hash = await sha256(canonical({ report: payload, publishReport: visibility === '1', policyVersion }));
  const tokenHash = await sha256(reportToken(request));
  const now = new Date();
  const expiry = new Date(now.getTime() + RETENTION_DAYS * 86400000).toISOString();
  const device = payload.device;
  const idHash = await withdrawalKey(id, tokenHash);
  const result = await env.DB.prepare(`INSERT INTO reports
    (id, payload, payload_hash, deletion_token_hash, model_identifier, os_version, app_version, helper_version,
     publish_report, policy_version, created_at, expires_at)
    SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    WHERE NOT EXISTS (SELECT 1 FROM withdrawals WHERE report_id_hash = ? AND expires_at > ?)
    ON CONFLICT(id) DO NOTHING`)
    .bind(id, text, hash, tokenHash, device.modelIdentifier, device.macOSVersion, device.appVersion,
      device.helperVersion, visibility === '1' ? 1 : 0, policyVersion, now.toISOString(), expiry, idHash, now.toISOString()).run();
  const row = await findReport(env, id);
  if (!row) throw new HttpError(409, 'REPORT_WITHDRAWN');
  if (!sameHash(row.deletion_token_hash, tokenHash) || !sameHash(row.payload_hash, hash)) {
    throw new HttpError(409, 'REPORT_ID_CONFLICT');
  }
  return json(receipt(row), result.meta.changes === 1 ? 201 : 200);
}
export function receipt(row: ReportRow) {
  return { reportID: row.id, status: row.status, receivedAt: row.created_at,
    expiresAt: row.expires_at, publishReport: row.publish_report === 1, policyVersion: row.policy_version };
}
export async function ownerReceipt(request: Request, env: Env, id: string): Promise<Response> {
  const row = await findReport(env, id);
  const tokenHash = await sha256(reportToken(request));
  if (!row || !sameHash(row.deletion_token_hash, tokenHash)) throw new HttpError(404, 'REPORT_NOT_FOUND');
  return json(receipt(row));
}
export async function deleteReport(request: Request, env: Env, id: string): Promise<Response> {
  const normalized = id.toLowerCase();
  const tokenHash = await sha256(reportToken(request));
  const idHash = await withdrawalKey(normalized, tokenHash);
  const row = await findReport(env, normalized);
  if (row && !sameHash(row.deletion_token_hash, tokenHash)) throw new HttpError(404, 'REPORT_NOT_FOUND');
  // With no row yet, still record the marker: the owner may be withdrawing an upload
  // whose response was lost and whose request has not arrived. It binds only this credential.
  const expiresAt = new Date(Date.now() + RETENTION_DAYS * 86400000).toISOString();
  // Insert the marker and remove payload in one transaction; even a late POST cannot resurrect it.
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO withdrawals (report_id_hash, deletion_token_hash, expires_at)
      VALUES (?, ?, ?) ON CONFLICT(report_id_hash) DO NOTHING`).bind(idHash, tokenHash, expiresAt),
    env.DB.prepare("DELETE FROM reviews WHERE object_type = 'report' AND object_id = ?").bind(normalized),
    env.DB.prepare('DELETE FROM reports WHERE id = ? AND deletion_token_hash = ?').bind(normalized, tokenHash),
  ]);
  return new Response(null, { status: 204 });
}

export async function publicReport(env: Env, id: string): Promise<Response> {
  const row = await findReport(env, id);
  if (!row || row.status !== 'approved' || row.publish_report !== 1) throw new HttpError(404, 'REPORT_NOT_FOUND');
  return json({ report: JSON.parse(row.payload), receivedOn: row.created_at.slice(0, 10), source: 'communityReport' });
}
export async function cleanup(env: Env): Promise<void> {
  const now = new Date().toISOString();
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 86400000).toISOString();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM diagnostics WHERE expires_at <= ?').bind(now),
    env.DB.prepare('DELETE FROM diagnostic_withdrawals WHERE expires_at <= ?').bind(now),
    // Report audits follow report retention. A verification's audit is kept while the
    // verification itself is still published, since those records persist until removed.
    env.DB.prepare(`DELETE FROM reviews WHERE (object_type = 'report' AND (reviewed_at < ? OR object_id IN
      (SELECT id FROM reports WHERE expires_at <= ?)))
      OR (object_type = 'verification' AND reviewed_at < ? AND object_id NOT IN (SELECT id FROM verifications))`)
      .bind(cutoff, now, cutoff),
    env.DB.prepare('DELETE FROM reports WHERE expires_at <= ?').bind(now),
    env.DB.prepare('DELETE FROM withdrawals WHERE expires_at <= ?').bind(now),
  ]);
}
