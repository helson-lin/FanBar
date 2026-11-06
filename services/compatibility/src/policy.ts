export const POLICY_VERSION = '2026-10-21';
/**
 * Versions still accepted, each under its own field allow-list. Clients up to 0.7.0
 * fetch /api/policy without asking for a version and require exactly 2026-10-13,
 * so that remains the default response until those releases stop being supported.
 */
export const LEGACY_POLICY_VERSION = '2026-10-13';
export const ACCEPTED_POLICY_VERSIONS: readonly string[] = [POLICY_VERSION, LEGACY_POLICY_VERSION];
export const RETENTION_DAYS = 90;
export const MAXIMUM_REPORT_BYTES = 16384;
// Diagnostics live here too so scripts/schema.ts can load every client-validated value without the Worker runtime.
export const DIAGNOSTIC_POLICY_VERSION = 'diagnostics-2026-10-19-v5';
export const DIAGNOSTIC_RETENTION_DAYS = 90;
export const DIAGNOSTIC_MAXIMUM_BYTES = 262144;
const failureFields = ['capabilities[].failure.code', 'capabilities[].failure.smcKey', 'capabilities[].failure.resultCode',
  'capabilities[].failure.fanIndex', 'capabilities[].failure.durationMS', 'capabilities[].failure.readbackManual',
  'capabilities[].failure.restoredAutomatic'];
/** Rules for `version`; an unknown or absent version gets the legacy default (see above). */
export function policy(origin: string, version: string | null = null) {
  const current = version === POLICY_VERSION;
  return {
    version: current ? POLICY_VERSION : LEGACY_POLICY_VERSION, serviceOrigin: origin, retentionDays: RETENTION_DAYS,
    maximumReportBytes: MAXIMUM_REPORT_BYTES, backupMaximumDays: 30,
    operator: 'FanBar project maintainers',
    sourceURL: 'https://github.com/helson-lin/FanBar/tree/main/services/compatibility',
    fields: ['schemaVersion', 'reportID', 'device.modelIdentifier', 'device.processor',
      'device.macOSVersion', 'device.appVersion', 'device.helperVersion', 'fanCount',
      'capabilities[].capability', 'capabilities[].status', 'capabilities[].reasonCode', 'capabilities[].userConfirmedWorking',
      ...(current ? failureFields : []), 'selectedTemperatureSource'],
    excluded: ['serialNumber', 'hardwareUUID', 'userName', 'hostName', 'filePaths', 'processes', 'temperatureHistory', 'diagnosticLogs'],
    rules: [
      'Extra fields and inconsistent evidence are rejected.',
      ...(current ? ['A failed control request carries only a fixed failure code and bounded numeric evidence, never error text.'] : []),
      'Reports are private unless the user explicitly opts to publish a reviewed report.',
      'Reviewed reports contribute to public compatibility counts, including private reports.',
      'Counts are reports, not unique devices. Retries of one report do not count again.',
      'Community reports never automatically become developer-verified compatibility.',
      'Accepted control requests do not prove physical fan RPM.',
      'Daily keyed network-address values are used only for short-lived rate limiting; no raw IP is stored in D1.',
      'Cloudflare processes network metadata to deliver and protect the service.',
      'Report credentials stay out of public data and URLs. D1 stores only their SHA-256 hashes.',
      'Reports and their contributions expire after 90 days, with scheduled daily cleanup.',
      'D1 historical restore points may retain deleted data for up to 30 days; online deletion does not erase them immediately.',
      'Owners can delete a report and remove its contribution using their report credential.',
      'Hashed report/credential withdrawal markers remain private for 90 days to prevent late request resurrection; no payload is retained.',
      'Independent developer test records persist until corrected or removed.',
    ],
  };
}
