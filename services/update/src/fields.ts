import modelNames from '../../../contracts/mac-model-names.json';

/** UTC ISO-8601 week, e.g. 2026-W47. Client and server must agree on this. */
export function isoWeek(date: Date): string {
  const day = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const weekday = day.getUTCDay() || 7;
  day.setUTCDate(day.getUTCDate() + 4 - weekday); // Thursday decides the ISO year.
  const yearStart = Date.UTC(day.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((day.getTime() - yearStart) / 86_400_000 + 1) / 7);
  return `${day.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

const KNOWN_MODELS = new Set(Object.keys(modelNames));
// Unknown identifiers of this shape are new Macs and count as `other`.
const MAC_MODEL_SHAPE = /^(Mac|MacBook|MacBookAir|MacBookPro|MacPro|Macmini|iMac|iMacPro|VirtualMac)\d+,\d+$/;
const ISO_WEEK =/^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/;

export function cohort(value: string | null, firstWeek: string, currentWeek: string) {
  if (value === 'legacy') return value;
  if (!value || !ISO_WEEK.test(value)) return undefined;
  return value >= firstWeek && value <= currentWeek ? value : undefined;
}

export function model(value: string | null) {
  if (!value || !MAC_MODEL_SHAPE.test(value)) return undefined;
  return KNOWN_MODELS.has(value) ? value : 'other';
}

export function osMajor(value: string | null) {
  if (!value || !/^\d{2}$/.test(value)) return undefined;
  const major = Number(value);
  return major >= 11 && major <= 40 ? value : undefined;
}

export function arch(value: string | null) {
  return value === 'arm64' || value === 'x86_64' ? value : undefined;
}

export function country(value: unknown) {
  return typeof value === 'string' && /^[A-Z]{2}$/.test(value) ? value : undefined;
}
