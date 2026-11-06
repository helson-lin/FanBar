export class ApiError extends Error {
  constructor(readonly code: string, readonly status: number) { super(code); }
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  // No API endpoint redirects. A redirect means Cloudflare Access is sending an expired
  // session to its login page, which fetch cannot follow across origins.
  const response = await fetch(path, { cache: 'no-store', redirect: 'manual', ...options });
  if (response.type === 'opaqueredirect') throw new ApiError('ADMIN_AUTHENTICATION_REQUIRED', 403);
  if (response.status === 204) return null as T;
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new ApiError(body?.error?.code ?? 'REQUEST_FAILED', response.status);
  return body as T;
}

/* ---------- Public API shapes (see src/matrix.ts and src/admin.ts) ---------- */
export type Capability = 'cpuTemperature' | 'gpuTemperature' | 'ssdTemperature' | 'batteryTemperature'
  | 'fanReadings' | 'manualControl' | 'smartCooling';
export type CommunityStatus = 'available' | 'notApplicable' | 'notDetected' | 'temporarilyUnavailable' | 'requiresAuthorization'
  | 'unverified' | 'requestSucceeded' | 'requestFailed';
export type VerificationStatus = 'verifiedAvailable' | 'verifiedUnsupported';

export interface Verification {
  id: string; capability: Capability; status: VerificationStatus;
  notes: string; source_url: string; verified_on: string;
}
export interface MatrixGroup {
  modelIdentifier: string; macOSVersion: string; appVersion: string; helperVersion: string; updatedOn: string;
  community: { capability: Capability; status: CommunityStatus; count: number; userConfirmedWorking?: number }[];
  developerVerifications: Verification[];
}
export interface Matrix { schemaVersion: 1; generatedAt: string; truncated: boolean; nextOffset: number | null; groups: MatrixGroup[] }

/** Fixed failure code plus bounded numeric evidence for a failed control request. */
export interface ControlFailure {
  code: string; smcKey?: string; resultCode?: number; fanIndex?: number; durationMS?: number;
  readbackManual?: boolean[]; restoredAutomatic?: boolean;
}
/** Compact, untranslated token line; every part is a code or a number. */
export function failureSummary(failure: ControlFailure): string {
  return [
    failure.code,
    failure.smcKey !== undefined && `key ${failure.smcKey}`,
    failure.resultCode !== undefined && `result ${failure.resultCode}`,
    failure.fanIndex !== undefined && `fan ${failure.fanIndex + 1}`,
    failure.durationMS !== undefined && `${failure.durationMS} ms`,
    failure.readbackManual && `readback ${failure.readbackManual.map(manual => manual ? 'manual' : 'auto').join('/')}`,
    failure.restoredAutomatic !== undefined && (failure.restoredAutomatic ? 'restored' : 'NOT restored'),
  ].filter(Boolean).join(' · ');
}

export interface Report {
  schemaVersion: 1; reportID: string;
  device: { modelIdentifier: string; processor: string; macOSVersion: string; appVersion: string; helperVersion: string };
  fanCount?: number;
  capabilities: { capability: Capability; status: CommunityStatus; reasonCode: string; userConfirmedWorking?: true; failure?: ControlFailure }[];
  selectedTemperatureSource: string;
}

/** GET /api/reports/:id — only reports the submitter chose to publish and that passed review. */
export interface PublicReport { report: Report; receivedOn: string; source: 'communityReport' }

export type ReviewStatus = 'pending' | 'approved' | 'rejected';
export type ReviewReason = 'reviewed' | 'duplicate' | 'invalid' | 'needsInvestigation';
export type ReviewFlag = 'conflict' | 'duplicate' | 'newModel';
export interface ReviewAnnotation { flags: ReviewFlag[]; duplicateOf: string[]; conflicts: Capability[] }
export interface AdminRow extends ReviewAnnotation {
  id: string; model_identifier: string; os_version: string; app_version: string; helper_version: string;
  publish_report: number; status: ReviewStatus; created_at: string; expires_at: string;
}
export interface AdminList { reports: AdminRow[]; hasMore: boolean; offset: number }
export interface AdminDetail {
  report: Report; status: ReviewStatus; publishReport: boolean; receivedAt: string; expiresAt: string;
  comparison: ReviewAnnotation & {
    otherApprovedReports: number;
    capabilities: { capability: Capability; status: CommunityStatus;
      existing: { status: CommunityStatus; count: number }[]; agrees: boolean | null;
      verification: { id: string; capability: Capability; status: VerificationStatus; verified_on: string } | null;
    }[];
  };
  reviews: { actor: string; status: ReviewStatus; reason: ReviewReason; reviewed_at: string }[];
}

/* ---------- Administrator session (src/auth.ts) ---------- */
export interface AdminSession {
  actor: string; kind: 'access' | 'localDevelopment'; email: string | null; expiresAt: string | null;
}

/* ---------- Update statistics (services/update/src/admin.ts, via /api/admin/updates) ---------- */
export type UpdateRange = 7 | 30 | 90;
export type UpdateDimension = 'cohorts' | 'models' | 'os' | 'arch' | 'countries';
export interface UpdateStats {
  generatedAt: string; range: UpdateRange; publicMinimumGroupSize: number;
  days: string[];
  daily: { day: string; version: string; n: number }[];
  weeks: string[];
  weekly: Record<UpdateDimension, { week: string; value: string; n: number }[]>;
  currentWeek: { week: string; checks: number; optedIn: number };
  releases: string[];
  dailyTaskDay: string | null;
}

/* ---------- Administrator insights (src/insights.ts) ---------- */
export interface AttentionItem {
  reportID: string; modelIdentifier: string; macOSVersion: string; appVersion: string; helperVersion: string; receivedAt: string;
  duplicateOf?: string[]; capabilities?: Capability[];
}
export interface VerificationCandidate {
  modelIdentifier: string; macOSVersion: string; appVersion: string; helperVersion: string;
  capability: Capability; reports: number; lastReportAt: string;
}
export interface AuditEntry {
  id: number; objectType: 'report' | 'verification'; objectID: string; actor: string;
  status: string; reason: string; reviewedAt: string; modelIdentifier: string | null;
}
export interface AuditList { entries: AuditEntry[]; hasMore: boolean; offset: number }
export interface Overview {
  generatedAt: string;
  queue: { pending: number; oldestPendingAt: string | null; inspected: number };
  week: { received: number; receivedPrevious: number; approved: number; rejected: number };
  daily: { date: string; count: number }[];
  attention: {
    conflicts: AttentionItem[]; duplicates: AttentionItem[]; newModels: AttentionItem[];
    verificationCandidates: VerificationCandidate[];
  };
  recent: AuditEntry[];
}
export interface AdminVerification {
  id: string; modelIdentifier: string; macOSVersion: string; appVersion: string; helperVersion: string;
  capability: Capability; status: VerificationStatus; notes: string; sourceURL: string; verifiedOn: string;
}
export interface VerificationList { verifications: AdminVerification[]; candidates: VerificationCandidate[]; candidateMinimum: number }
