import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge } from '@cloudflare/kumo/components/badge';
import { Banner } from '@cloudflare/kumo/components/banner';
import { Button } from '@cloudflare/kumo/components/button';
import { Empty } from '@cloudflare/kumo/components/empty';
import { LayerCard } from '@cloudflare/kumo/components/layer-card';
import { Select } from '@cloudflare/kumo/components/select';
import { Table } from '@cloudflare/kumo/components/table';
import { cn } from '@cloudflare/kumo/utils';
import { ArrowClockwiseIcon, ArrowSquareOutIcon, ChartBarIcon, WarningCircleIcon } from '@phosphor-icons/react';
import { DataTable } from './data-table';
import { PageTitle } from './shell';
import { language, t } from '../i18n';
import { ApiError, type UpdateDimension, type UpdateRange, type UpdateStats } from '../lib/api';
import { errorMessage, modelTitle } from '../lib/labels';

type Request = <T>(path: string, options?: RequestInit) => Promise<T>;

const UPDATE_ORIGIN = 'https://update.getfanbar.com';
const OTHER = 'other';
/** Versions get indigo shades, darkest for the newest; status colours are reserved for status. */
const SHADES = ['bg-fanbar-v1', 'bg-fanbar-v2', 'bg-fanbar-v3', 'bg-fanbar-v4'];
const OTHER_SHADE = 'bg-fanbar-v-other';

const number = (value: number) => value.toLocaleString(language);
const sum = (values: number[]) => values.reduce((total, value) => total + value, 0);
const shortDay = (day: string) => new Date(day + 'T00:00:00Z').toLocaleDateString(language, { month: 'numeric', day: 'numeric', timeZone: 'UTC' });

function Delta({ current, previous }: { current: number; previous: number }) {
  if (!previous) return <span className="text-kumo-subtle">{current ? t('新') : '—'}</span>;
  const change = (current / previous - 1) * 100;
  return (
    <span className={cn('tabular', change >= 0 ? 'text-kumo-success' : 'text-kumo-danger')}>
      {change >= 0 ? '+' : ''}{change.toFixed(Math.abs(change) < 10 ? 1 : 0)}%
    </span>
  );
}

function Metric({ label, value, note }: { label: string; value: string; note: React.ReactNode }) {
  return (
    <LayerCard>
      <LayerCard.Primary className="flex flex-col gap-1">
        <span className="text-xs text-kumo-subtle">{label}</span>
        <span className="text-2xl font-semibold tracking-tight tabular">{value}</span>
        <span className="text-xs text-kumo-subtle">{note}</span>
      </LayerCard.Primary>
    </LayerCard>
  );
}

export function UpdateStatsArea({ request, onError }: { request: Request; onError: (error: unknown) => void }) {
  const [range, setRange] = useState<UpdateRange>(30);
  const [data, setData] = useState<UpdateStats | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setData(await request<UpdateStats>('/api/admin/updates?range=' + range));
      setFailure(null);
    } catch (error) {
      // Session problems belong to the page; an unavailable update service only affects this area.
      if (error instanceof ApiError && error.code.startsWith('ADMIN_')) onError(error);
      else setFailure(errorMessage(error));
    } finally { setLoading(false); }
  }, [request, range, onError]);
  useEffect(() => { void load(); }, [load]);

  return (
    <section>
      <PageTitle
        title="更新统计"
        lede="来自 update.getfanbar.com 的更新检查计数。这里显示完整数据，包括公开页隐藏的少于 5 的分组。"
        aside={(
          <div className="flex items-center gap-2">
            <Badge variant="outline">{t('仅管理员可见')}</Badge>
            <Select
              aria-label={t('时间范围')}
              size="sm"
              className="w-32"
              value={String(range)}
              onValueChange={value => value && setRange(Number(value) as UpdateRange)}
              items={Object.fromEntries([7, 30, 90].map(days => [days, t('最近 {count} 天', { count: days })]))}
            />
            <Button size="sm" icon={ArrowClockwiseIcon} loading={loading} onClick={() => void load()}>{t('刷新')}</Button>
          </div>
        )}
      />
      {failure && (
        <Banner className="mb-4" variant="error" icon={<WarningCircleIcon weight="fill" />} description={failure} />
      )}
      {data && <UpdateStatsView data={data} />}
    </section>
  );
}

function UpdateStatsView({ data }: { data: UpdateStats }) {
  const { days, daily, range } = data;
  const today = days[days.length - 1];
  const totalOn = useMemo(() => {
    const totals = new Map<string, number>();
    for (const row of daily) totals.set(row.day, (totals.get(row.day) ?? 0) + row.n);
    return (day: string) => totals.get(day) ?? 0;
  }, [daily]);
  // daily covers max(2 × range, 14) days ending today, so earlier periods can be compared.
  const window = (length: number, offset = 0) => {
    const end = Date.parse(today + 'T00:00:00Z') - offset * length * 86_400_000;
    return Array.from({ length }, (_, i) => new Date(end - (length - 1 - i) * 86_400_000).toISOString().slice(0, 10));
  };
  const total = (list: string[]) => sum(list.map(totalOn));
  const share = data.currentWeek.checks ? data.currentWeek.optedIn / data.currentWeek.checks : 0;

  if (daily.length === 0) {
    return (
      <LayerCard>
        <LayerCard.Primary>
          <Empty size="sm" icon={<ChartBarIcon size={32} className="text-kumo-inactive" />} title={t('还没有更新检查')} description={t('第一次检查之后，这里会按天显示计数。')} />
        </LayerCard.Primary>
      </LayerCard>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label={t('今天（UTC）')} value={number(totalOn(today))} note={t('截至 {time} UTC', { time: data.generatedAt.slice(11, 16) })} />
        <Metric
          label={t('最近 {count} 天', { count: 7 })}
          value={number(total(window(7)))}
          note={<><Delta current={total(window(7))} previous={total(window(7, 1))} /> {t('较前 {count} 天', { count: 7 })}</>}
        />
        {range !== 7 && (
          <Metric
            label={t('最近 {count} 天', { count: range })}
            value={number(total(window(range)))}
            note={<><Delta current={total(window(range))} previous={total(window(range, 1))} /> {t('较前 {count} 天', { count: range })}</>}
          />
        )}
        <Metric
          label={t('开启统计')}
          value={`${Math.round(share * 100)}%`}
          note={t('本周 {optedIn} / {checks} 次检查带设备信息', { optedIn: number(data.currentWeek.optedIn), checks: number(data.currentWeek.checks) })}
        />
      </div>
      <DailyChart data={data} />
      <div className="grid items-start gap-4 lg:grid-cols-2">
        <VersionTable data={data} last={window(7)} previous={window(7, 1)} />
        <ServiceStatus data={data} />
      </div>
      <Dimensions data={data} />
    </div>
  );
}

/* ---------- Daily chart ---------- */
function DailyChart({ data }: { data: UpdateStats }) {
  const [hover, setHover] = useState<number | null>(null);
  const inRange = new Set(data.days);
  const rows = data.daily.filter(row => inRange.has(row.day));
  // The four busiest released versions get their own shade, newest darkest; the rest stack as one.
  const byVersion = new Map<string, number>();
  for (const row of rows) if (row.version !== OTHER) byVersion.set(row.version, (byVersion.get(row.version) ?? 0) + row.n);
  const named = [...byVersion.entries()].sort((a, b) => b[1] - a[1]).slice(0, SHADES.length).map(([version]) => version);
  const series = data.releases.filter(version => named.includes(version)).concat(named.filter(version => !data.releases.includes(version)));
  const keys = [...series, OTHER];
  const shade = (key: string) => (key === OTHER ? OTHER_SHADE : SHADES[series.indexOf(key)]);
  const label = (key: string) => (key === OTHER ? t('其他') : key);

  const columns = data.days.map(day => {
    const values = new Map<string, number>();
    for (const row of rows) {
      if (row.day !== day) continue;
      const key = series.includes(row.version) ? row.version : OTHER;
      values.set(key, (values.get(key) ?? 0) + row.n);
    }
    return { day, values, total: sum([...values.values()]) };
  });
  const peak = Math.max(1, ...columns.map(column => column.total));
  const step = 10 ** Math.floor(Math.log10(peak));
  const top = Math.ceil(peak / step) * step;
  const focused = hover === null ? null : columns[hover];

  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary className="flex flex-wrap items-center justify-between gap-3">
        {t('每日更新检查')}
        <span className="flex flex-wrap items-center gap-3 text-xs font-normal text-kumo-subtle">
          {keys.map(key => (
            <span key={key} className="flex items-center gap-1.5">
              <i className={cn('size-2 rounded-sm', shade(key))} />
              <span className={cn(key !== OTHER && 'font-mono')}>{label(key)}</span>
            </span>
          ))}
        </span>
      </LayerCard.Secondary>
      <LayerCard.Primary>
        <div className="relative pr-10" onMouseLeave={() => setHover(null)}>
          <div className="pointer-events-none absolute inset-0 flex flex-col justify-between">
            {[top, top / 2, 0].map(value => (
              <div key={value} className="flex items-center gap-2">
                <span className="flex-1 border-t border-dashed border-kumo-line" />
                <span className="w-8 text-[10px] leading-none text-kumo-subtle tabular">{value ? number(value) : ''}</span>
              </div>
            ))}
          </div>
          <div className={cn('relative flex h-48 items-end', data.days.length > 30 ? 'gap-px' : 'gap-[3px]')}>
            {columns.map((column, index) => (
              <div
                key={column.day}
                onMouseEnter={() => setHover(index)}
                className={cn('flex h-full flex-1 flex-col-reverse', hover === index && 'bg-kumo-tint')}
              >
                {keys.map(key => {
                  const value = column.values.get(key) ?? 0;
                  return value ? <i key={key} className={cn('block', shade(key))} style={{ height: `${(value / top) * 100}%` }} /> : null;
                })}
              </div>
            ))}
          </div>
          {focused && (
            <div
              className={cn(
                'pointer-events-none absolute top-2 z-10 min-w-40 rounded-lg border border-kumo-hairline bg-kumo-overlay p-3 text-xs shadow-lg',
                hover! < columns.length / 2 ? 'right-2' : 'left-2',
              )}
            >
              <b className="mb-1.5 block font-semibold tabular">{focused.day} · {number(focused.total)}</b>
              {keys.map(key => (
                <span key={key} className="flex items-center justify-between gap-4">
                  <span className="flex items-center gap-1.5"><i className={cn('size-2 rounded-sm', shade(key))} />{label(key)}</span>
                  <span className="tabular">{number(focused.values.get(key) ?? 0)}</span>
                </span>
              ))}
            </div>
          )}
        </div>
        <div className="mt-2 flex justify-between pr-10 text-[11px] text-kumo-subtle tabular">
          <span>{shortDay(data.days[0])}</span>
          <span>{t('今天')}</span>
        </div>
      </LayerCard.Primary>
    </LayerCard>
  );
}

/* ---------- Versions ---------- */
function VersionTable({ data, last, previous }: { data: UpdateStats; last: string[]; previous: string[] }) {
  const count = (days: string[]) => {
    const inside = new Set(days);
    const totals = new Map<string, number>();
    for (const row of data.daily) if (inside.has(row.day)) totals.set(row.version, (totals.get(row.version) ?? 0) + row.n);
    return totals;
  };
  const now = count(last);
  const before = count(previous);
  const total = sum([...now.values()]);
  const latest = data.releases[0];
  const versions = [...now.keys()].sort((a, b) => (a === OTHER ? 1 : b === OTHER ? -1 : now.get(b)! - now.get(a)!));
  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary className="flex items-center justify-between">
        {t('版本分布')}
        <span className="text-xs font-normal text-kumo-subtle">{t('最近 {count} 天', { count: 7 })}</span>
      </LayerCard.Secondary>
      <LayerCard.Primary className="p-0">
        <DataTable>
          <Table.Header>
            <Table.Row>
              <Table.Head>{t('版本')}</Table.Head>
              <Table.Head className="text-right">{t('检查')}</Table.Head>
              <Table.Head className="w-[38%]">{t('占比')}</Table.Head>
              <Table.Head className="text-right whitespace-nowrap">{t('较前 {count} 天', { count: 7 })}</Table.Head>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {versions.map(version => {
              const value = now.get(version)!;
              const percent = total ? (value / total) * 100 : 0;
              return (
                <Table.Row key={version}>
                  <Table.Cell>
                    {version === OTHER
                      ? <span className="text-kumo-subtle">other <Tag>{t('不在发布列表')}</Tag></span>
                      : <span className="font-mono">{version}{version === latest && <span className="ml-2 rounded border border-kumo-brand px-1 font-sans text-[11px] text-kumo-link">{t('最新')}</span>}</span>}
                  </Table.Cell>
                  <Table.Cell className="text-right tabular">{number(value)}</Table.Cell>
                  <Table.Cell>
                    <span className="flex items-center gap-2">
                      <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-kumo-fill">
                        <i className={cn('block h-full rounded-full', version === OTHER ? OTHER_SHADE : 'bg-fanbar-v1')} style={{ width: `${percent}%` }} />
                      </span>
                      <span className="w-11 text-right text-xs text-kumo-subtle tabular">{percent.toFixed(1)}%</span>
                    </span>
                  </Table.Cell>
                  <Table.Cell className="text-right"><Delta current={value} previous={before.get(version) ?? 0} /></Table.Cell>
                </Table.Row>
              );
            })}
          </Table.Body>
        </DataTable>
      </LayerCard.Primary>
    </LayerCard>
  );
}

function Tag({ children }: { children: React.ReactNode }) {
  return <span className="ml-1.5 shrink-0 rounded border border-dashed border-kumo-line px-1 text-[10.5px] whitespace-nowrap text-kumo-subtle">{children}</span>;
}

/* ---------- Service status ---------- */
function ServiceStatus({ data }: { data: UpdateStats }) {
  const today = data.days[data.days.length - 1];
  const ranToday = data.dailyTaskDay === today;
  const monday = new Date(Date.parse(today + 'T00:00:00Z') - ((new Date(today + 'T00:00:00Z').getUTCDay() || 7) - 1) * 86_400_000).toISOString().slice(0, 10);
  const otherThisWeek = sum(data.daily.filter(row => row.version === OTHER && row.day >= monday).map(row => row.n));
  const shown = data.releases.slice(0, 5);
  const row = (key: string, value: React.ReactNode) => (
    <div className="grid grid-cols-[7rem_1fr] gap-3 border-b border-kumo-hairline px-4 py-3 text-[13px] last:border-0">
      <span className="text-kumo-subtle">{t(key)}</span>
      <span>{value}</span>
    </div>
  );
  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary>{t('服务状态')}</LayerCard.Secondary>
      <LayerCard.Primary className="p-0">
        {row('每日任务', (
          <span className="flex items-center gap-1.5">
            <i className={cn('size-2 rounded-full', ranToday ? 'bg-kumo-success' : 'bg-kumo-warning')} />
            {ranToday ? t('今天已运行') : data.dailyTaskDay ? t('上次运行于 {day}', { day: data.dailyTaskDay }) : t('尚未运行')}
            <span className="text-kumo-subtle">· {t('由当天第一次检查触发')}</span>
          </span>
        ))}
        {row('已发布版本', (
          <span className="flex flex-wrap items-center gap-1.5">
            {shown.map((version, index) => (
              <span key={version} className={cn('rounded border px-1.5 font-mono text-xs', index === 0 ? 'border-kumo-brand text-kumo-link' : 'border-kumo-line')}>
                {version}{index === 0 && ' ' + t('最新')}
              </span>
            ))}
            {data.releases.length > shown.length && <span className="text-xs text-kumo-subtle">+{data.releases.length - shown.length}</span>}
            {data.releases.length === 0 && <span className="text-kumo-subtle">{t('发布列表为空')}</span>}
          </span>
        ))}
        {row('计为 other', (
          <span>{t('本周 {count} 次', { count: number(otherThisWeek) })} <span className="text-kumo-subtle">· {t('版本号不在发布列表（测试版或伪造请求）')}</span></span>
        ))}
        {row('公开统计', (
          <span>
            {t('边缘缓存 1 小时 · 隐藏少于 {count} 的分组', { count: data.publicMinimumGroupSize })} ·{' '}
            <a href={UPDATE_ORIGIN + '/api/stats'} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-kumo-link">
              /api/stats <ArrowSquareOutIcon size={12} />
            </a>
          </span>
        ))}
        {row('计数限流', <span>{t('每个地址每分钟 10 次')} <span className="text-kumo-subtle">· {t('超出只跳过计数，仍然跳转')}</span></span>)}
      </LayerCard.Primary>
    </LayerCard>
  );
}

/* ---------- Opted-in dimensions ---------- */
const DIMENSIONS: { key: UpdateDimension; title: string }[] = [
  { key: 'models', title: 'Mac 型号' }, { key: 'os', title: 'macOS' }, { key: 'arch', title: '芯片' },
  { key: 'countries', title: '国家 / 地区' }, { key: 'cohorts', title: '开始统计的周' },
];

const regions = (() => { try { return new Intl.DisplayNames([language], { type: 'region' }); } catch { return null; } })();
function dimensionLabel(dimension: UpdateDimension, value: string): string {
  if (dimension === 'models') return value === OTHER ? t('未收录的新机型') : modelTitle(value);
  if (dimension === 'os') return `macOS ${value}`;
  if (dimension === 'arch') return value === 'arm64' ? t('Apple 芯片 · arm64') : 'Intel · x86_64';
  if (dimension === 'countries') return regions?.of(value) ?? value;
  return value === 'legacy' ? t('早期版本（无记录）') : value;
}

function Dimensions({ data }: { data: UpdateStats }) {
  const [week, setWeek] = useState(data.weeks[0]);
  const minimum = data.publicMinimumGroupSize;
  // Every opted-in check carries a cohort, so cohort totals are opted-in checks per week.
  const trend = [...data.weeks].reverse().map(item => ({
    week: item, n: sum(data.weekly.cohorts.filter(row => row.week === item).map(row => row.n)),
  }));
  const trendPeak = Math.max(1, ...trend.map(item => item.n));
  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary className="flex flex-wrap items-center justify-between gap-3">
        {t('开启统计的设备')}
        <span className="flex items-center gap-3 text-xs font-normal text-kumo-subtle">
          <span className="hidden md:inline">{t('只来自开启统计的用户；各维度分开计数，不能交叉')}</span>
          <Select
            aria-label={t('统计周')}
            size="sm"
            className="w-40"
            value={week}
            onValueChange={value => value && setWeek(value)}
            items={Object.fromEntries(data.weeks.map((item, index) => [item, index === 0 ? t('{week}（本周）', { week: item }) : item]))}
          />
        </span>
      </LayerCard.Secondary>
      <LayerCard.Primary className="grid gap-px bg-kumo-hairline p-0 sm:grid-cols-2 lg:grid-cols-3">
        {DIMENSIONS.map(({ key, title }) => {
          const rows = data.weekly[key].filter(row => row.week === week);
          const peak = Math.max(1, ...rows.map(row => row.n));
          return (
            <div key={key} className="bg-kumo-base p-4">
              <h4 className="mb-3 flex items-center justify-between text-xs font-semibold">
                {t(title)}
                <span className="font-normal text-kumo-subtle tabular">{number(sum(rows.map(row => row.n)))}</span>
              </h4>
              {rows.length === 0
                ? <p className="text-xs text-kumo-subtle">{t('这一周没有数据')}</p>
                : (
                  <ol className="flex max-h-56 flex-col gap-1.5 overflow-auto">
                    {rows.map(row => {
                      const hidden = row.n < minimum;
                      const name = dimensionLabel(key, row.value);
                      return (
                        <li key={row.value} className="grid grid-cols-[minmax(0,1fr)_4rem_2.5rem] items-center gap-2 text-xs">
                          <span className={cn('flex min-w-0 items-center', hidden && 'text-kumo-subtle')} title={name}>
                            <span className="truncate">{name}</span>
                            {hidden && <Tag>{t('未公开')}</Tag>}
                          </span>
                          <span className="h-1.5 overflow-hidden rounded-full bg-kumo-fill">
                            <i className={cn('block h-full rounded-full', hidden ? OTHER_SHADE : 'bg-fanbar-v1')} style={{ width: `${(row.n / peak) * 100}%` }} />
                          </span>
                          <span className="text-right tabular">{number(row.n)}</span>
                        </li>
                      );
                    })}
                  </ol>
                )}
            </div>
          );
        })}
        <div className="bg-kumo-base p-4">
          <h4 className="mb-3 flex items-center justify-between text-xs font-semibold">
            {t('开启统计的检查')}
            <span className="font-normal text-kumo-subtle">{t('近 {count} 周', { count: trend.length })}</span>
          </h4>
          <div className="flex h-28 items-end gap-1.5">
            {trend.map(item => (
              <button
                key={item.week}
                type="button"
                title={`${item.week} · ${number(item.n)}`}
                onClick={() => setWeek(item.week)}
                className="flex h-full flex-1 flex-col justify-end gap-1 text-center"
              >
                <i className={cn('block rounded-t-sm', item.week === week ? 'bg-fanbar-v1' : 'bg-fanbar-v3')} style={{ height: `${(item.n / trendPeak) * 80}%` }} />
                <span className="font-mono text-[10px] text-kumo-subtle">{item.week.slice(5)}</span>
              </button>
            ))}
          </div>
        </div>
      </LayerCard.Primary>
    </LayerCard>
  );
}
