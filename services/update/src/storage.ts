/** Each opted-in dimension has its own weekly table; dimensions are never stored together. */
export const WEEKLY_TABLES = {
  cohorts: 'cohort_weekly',
  models: 'model_weekly',
  os: 'os_weekly',
  arch: 'arch_weekly',
  countries: 'country_weekly',
} as const;

export type WeeklyDimension = keyof typeof WEEKLY_TABLES;

export const DAY_MS = 86_400_000;

export const utcDay = (date: Date) => date.toISOString().slice(0, 10);
