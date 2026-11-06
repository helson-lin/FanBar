import { z } from 'zod';

export const capabilities = [
  'cpuTemperature', 'gpuTemperature', 'ssdTemperature', 'batteryTemperature',
  'fanReadings', 'manualControl', 'smartCooling',
] as const;
export const statuses = [
  'available', 'notApplicable', 'notDetected', 'temporarilyUnavailable', 'requiresAuthorization',
  'unverified', 'requestSucceeded', 'requestFailed',
] as const;
export const reasons = [
  'SENSOR_READ_SUCCEEDED', 'SENSOR_NOT_DETECTED', 'NO_BUILT_IN_BATTERY', 'FAN_READ_SUCCEEDED', 'NO_FANS_REPORTED',
  'FAN_READ_FAILED', 'SMC_CONNECTION_FAILED', 'HELPER_MISSING', 'HELPER_AUTHORIZATION_REQUIRED',
  'NO_CURRENT_FAN_EVIDENCE', 'NO_CURVE_SENSOR_EVIDENCE', 'CONTROL_NOT_ATTEMPTED',
  'CONTROL_REQUEST_SUCCEEDED', 'CONTROL_REQUEST_FAILED',
] as const;
const shortText = (maximum: number) => z.string().min(1).max(maximum).regex(/^[^\x00-\x1f\x7f]+$/);
export const version = shortText(40).regex(/^[A-Za-z0-9._+-]+$/);
export const modelIdentifier = shortText(64).regex(/^[A-Za-z][A-Za-z0-9]*[0-9]+,[0-9]+$|^unknown$/);
/** Why a control request failed. Reports cannot be followed up, so the code has to say it. */
export const failureCodes = [
  'SMC_CONNECTION_FAILED', 'SMC_OPERATION_FAILED', 'SMC_INVALID_VALUE', 'UNLOCK_TIMEOUT', 'MODE_KEY_MISSING',
  'INVALID_REQUEST', 'HELPER_TIMEOUT', 'HELPER_CONNECTION_FAILED', 'READBACK_NOT_MANUAL', 'HELPER_ERROR_UNCLASSIFIED',
] as const;
export const failureSchema = z.strictObject({
  code: z.enum(failureCodes),
  smcKey: z.string().regex(/^[A-Za-z0-9! ]{4}$/).optional(),
  resultCode: z.number().int().min(-2147483648).max(2147483647).optional(),
  fanIndex: z.number().int().min(0).max(7).optional(),
  durationMS: z.number().int().min(0).max(600000).optional(),
  readbackManual: z.array(z.boolean()).min(1).max(8).optional(),
  restoredAutomatic: z.boolean().optional(),
});
export const capabilitySchema = z.strictObject({
  capability: z.enum(capabilities), status: z.enum(statuses), reasonCode: z.enum(reasons),
  userConfirmedWorking: z.literal(true).optional(),
  failure: failureSchema.optional(),
});
export const reportSchema = z.strictObject({
  schemaVersion: z.literal(1),
  reportID: z.uuid(),
  device: z.strictObject({
    modelIdentifier, processor: shortText(120), macOSVersion: version,
    appVersion: version, helperVersion: version,
  }),
  fanCount: z.number().int().min(0).max(8).optional(),
  capabilities: z.array(capabilitySchema).length(7),
  selectedTemperatureSource: z.enum(['maxChip', 'cpu', 'gpu', 'ssd']),
});
export type Report = z.infer<typeof reportSchema>;
export type Capability = typeof capabilities[number];
export type Status = typeof statuses[number];

const reasonStatuses: Record<typeof reasons[number], Status> = {
  NO_BUILT_IN_BATTERY: 'notApplicable',
  SENSOR_READ_SUCCEEDED: 'available', SENSOR_NOT_DETECTED: 'notDetected',
  FAN_READ_SUCCEEDED: 'available', NO_FANS_REPORTED: 'notDetected',
  FAN_READ_FAILED: 'temporarilyUnavailable', SMC_CONNECTION_FAILED: 'temporarilyUnavailable',
  HELPER_MISSING: 'temporarilyUnavailable', HELPER_AUTHORIZATION_REQUIRED: 'requiresAuthorization',
  NO_CURRENT_FAN_EVIDENCE: 'unverified', NO_CURVE_SENSOR_EVIDENCE: 'unverified',
  CONTROL_NOT_ATTEMPTED: 'unverified', CONTROL_REQUEST_SUCCEEDED: 'requestSucceeded',
  CONTROL_REQUEST_FAILED: 'requestFailed',
};
/**
 * A hands-on confirmation may accompany an untested control (used on an earlier
 * version, for example), but never a result showing control could not have run here.
 */
export const confirmableStatuses: readonly Status[] = ['requestSucceeded', 'unverified'];
export function validEvidence(report: Report): boolean {
  if (new Set(report.capabilities.map(row => row.capability)).size !== 7) return false;
  return report.capabilities.every(row => {
    if (row.reasonCode === 'NO_BUILT_IN_BATTERY') return row.capability === 'batteryTemperature' && row.status === 'notApplicable' && !row.userConfirmedWorking;
    if (row.userConfirmedWorking && (!['manualControl', 'smartCooling'].includes(row.capability)
      || !confirmableStatuses.includes(row.status))) return false;
    if (reasonStatuses[row.reasonCode] !== row.status) return false;
    if (row.failure && row.reasonCode !== 'CONTROL_REQUEST_FAILED') return false;
    const isSensor = row.capability.endsWith('Temperature');
    if (isSensor) return ['SENSOR_READ_SUCCEEDED', 'SENSOR_NOT_DETECTED', 'SMC_CONNECTION_FAILED'].includes(row.reasonCode);
    if (row.capability === 'fanReadings') {
      if (row.reasonCode === 'FAN_READ_SUCCEEDED') return report.fanCount !== undefined && report.fanCount > 0;
      if (row.reasonCode === 'NO_FANS_REPORTED') return report.fanCount === 0;
      return report.fanCount === undefined && ['FAN_READ_FAILED', 'SMC_CONNECTION_FAILED'].includes(row.reasonCode);
    }
    return !['SENSOR_READ_SUCCEEDED', 'SENSOR_NOT_DETECTED', 'FAN_READ_SUCCEEDED',
      'NO_FANS_REPORTED', 'FAN_READ_FAILED', 'SMC_CONNECTION_FAILED'].includes(row.reasonCode)
      && (row.reasonCode !== 'NO_CURVE_SENSOR_EVIDENCE' || row.capability === 'smartCooling');
  });
}
export const reviewSchema = z.strictObject({
  status: z.enum(['pending', 'approved', 'rejected']),
  reason: z.enum(['reviewed', 'duplicate', 'invalid', 'needsInvestigation']),
});
export const verificationSchema = z.strictObject({
  modelIdentifier, macOSVersion: version, appVersion: version, helperVersion: version,
  capability: z.enum(capabilities), status: z.enum(['verifiedAvailable', 'verifiedUnsupported']),
  notes: shortText(500), sourceURL: z.url().regex(/^https:\/\//),
  verifiedOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});
