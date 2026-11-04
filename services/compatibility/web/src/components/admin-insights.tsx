import { useCallback, useEffect, useState } from 'react';
import { Badge } from '@cloudflare/kumo/components/badge';
import { Button } from '@cloudflare/kumo/components/button';
import { Empty } from '@cloudflare/kumo/components/empty';
import { LayerCard } from '@cloudflare/kumo/components/layer-card';
import { Select } from '@cloudflare/kumo/components/select';
import { Table } from '@cloudflare/kumo/components/table';
import { cn } from '@cloudflare/kumo/utils';
import { ArrowSquareOutIcon, CheckCircleIcon, ListChecksIcon } from '@phosphor-icons/react';
import { DataTable } from './data-table';
import { StatusIcon, StatusLabel } from './status';
import { t } from '../i18n';
import type {
  AdminVerification, AuditEntry, AuditList, Overview, ReviewFlag, VerificationCandidate, VerificationList, VerificationStatus,
} from '../lib/api';
import { capabilityTitle, modelTitle, statusTitle, toneOf, type Tone } from '../lib/labels';

export type Request = <T>(path: string, options?: RequestInit) => Promise<T>;
type OnError = (error: unknown) => void;

const pageSize = 50;
const mutation = (method: string): RequestInit => ({ method, headers: { 'X-FanBar-Admin': '1', 'Content-Type': 'application/json' } });

/* ---------- Shared labels ---------- */
export function FlagBadges({ flags }: { flags: ReviewFlag[] }) {
  return (
    <>
      {flags.includes('conflict') && <Badge variant="outline" icon={<StatusIcon tone="mixed" className="size-3" />}>{t('结果冲突')}</Badge>}
      {flags.includes('duplicate') && <Badge variant="error" appearance="dot">{t('疑似重复')}</Badge>}
      {flags.includes('newModel') && <Badge variant="outline">{t('新机型')}</Badge>}
    </>
  );
}

/**
 * Reviews are signed with the Access email. Older entries carry the retired shared key,
 * which was a role rather than a person; local development has its own fixed name.
 */
function actorTitle(actor: string): string {
  if (actor === 'administrator-key') return t('管理密钥（旧记录）');
  if (actor === 'local-development') return t('本地开发');
  return actor;
}

const reasonTitles: Record<string, string> = {
  reviewed: '已检查字段与证据', duplicate: '疑似重复报告', invalid: '无效报告', needsInvestigation: '需进一步调查',
  independentTest: '独立实测', correction: '更正错误记录',
};

function auditAction(entry: AuditEntry): string {
  if (entry.objectType === 'report') {
    return t(({ approved: '纳入社区统计', rejected: '排除报告', pending: '恢复待审核' } as Record<string, string>)[entry.status] ?? entry.status);
  }
  if (entry.status === 'removed') return t('撤下记录');
  return [t('发布实测记录'), statusTitle(entry.status as VerificationStatus)].join(' · ');
}

function elapsed(iso: string, now = Date.now()): string {
  const hours = Math.floor((now - Date.parse(iso)) / 3600000);
  if (hours < 1) return t('不到 1 小时');
  if (hours < 48) return t('{count} 小时', { count: hours });
  return t('{count} 天', { count: Math.floor(hours / 24) });
}

const combination = (item: { macOSVersion: string; appVersion: string; helperVersion: string }) =>
  `macOS ${item.macOSVersion} · FanBar ${item.appVersion} · Helper ${item.helperVersion}`;

/* ---------- Overview ---------- */
export function OverviewTab({ request, onReady, onError, onOpenReport, onOpenVerification }: {
  request: Request; onReady: (overview: Overview) => void; onError: OnError;
  onOpenReport: (id: string) => void; onOpenVerification: () => void;
}) {
  const [data, setData] = useState<Overview | null>(null);
  const load = useCallback(async () => {
    try { const overview = await request<Overview>('/api/admin/overview'); setData(overview); onReady(overview); }
    catch (error) { onError(error); }
  }, [request, onReady, onError]);
  useEffect(() => { void load(); }, [load]);
  if (!data) return null;

  const { queue, week, attention } = data;
  const peak = Math.max(1, ...data.daily.map(day => day.count));
  type Item = { key: string; tone: Tone; title: string; detail: string; action: string; open: () => void };
  const items: Item[] = [
    ...attention.conflicts.map(item => ({
      key: 'c' + item.reportID, tone: 'mixed' as Tone,
      title: [modelTitle(item.modelIdentifier), 'macOS ' + item.macOSVersion, t('结果冲突')].join(' · '),
      detail: t('与已审核报告不一致：{items}', { items: (item.capabilities ?? []).map(capabilityTitle).join('、') }),
      action: t('去审核'), open: () => onOpenReport(item.reportID),
    })),
    ...attention.duplicates.map(item => ({
      key: 'd' + item.reportID, tone: 'unsupported' as Tone,
      title: [modelTitle(item.modelIdentifier), t('疑似重复')].join(' · '),
      detail: t('与 {count} 份内容相同的报告相隔不到 10 分钟提交', { count: item.duplicateOf?.length ?? 0 }),
      action: t('去审核'), open: () => onOpenReport(item.reportID),
    })),
    ...attention.newModels.map(item => ({
      key: 'n' + item.reportID, tone: 'unknown' as Tone,
      title: [modelTitle(item.modelIdentifier), t('新机型')].join(' · '),
      detail: t('该机型还没有已审核的报告或实测记录。') + ' ' + combination(item),
      action: t('去审核'), open: () => onOpenReport(item.reportID),
    })),
    ...attention.verificationCandidates.map(item => ({
      key: 'v' + item.modelIdentifier + item.macOSVersion + item.appVersion + item.helperVersion + item.capability,
      tone: 'pending' as Tone,
      title: [modelTitle(item.modelIdentifier), capabilityTitle(item.capability), t('待开发者实测')].join(' · '),
      detail: [combination(item), t('“请求成功” {count} 份', { count: item.reports })].join(' · '),
      action: t('安排实测'), open: onOpenVerification,
    })),
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric
          label={t('待审核')}
          value={String(queue.pending)}
          note={queue.oldestPendingAt ? t('最久已等待 {time}', { time: elapsed(queue.oldestPendingAt) }) : t('队列已清空')}
          warn={queue.oldestPendingAt !== null && Date.now() - Date.parse(queue.oldestPendingAt) > 3 * 86400000}
        />
        <Metric label={t('本周收到')} value={String(week.received)} note={t('上周 {count} 份', { count: week.receivedPrevious })} />
        <Metric label={t('本周纳入 / 排除')} value={`${week.approved} / ${week.rejected}`} note={t('只统计审核决定，不含撤回的报告')} />
        <Metric
          label={t('待开发者实测')}
          value={attention.verificationCandidates.length >= 10 ? '10+' : String(attention.verificationCandidates.length)}
          note={t('满足条件、尚未实测的组合')}
        />
      </div>

      <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <LayerCard className="p-0">
          <LayerCard.Secondary className="flex items-center justify-between">
            {t('需要关注')}
            {queue.pending > queue.inspected && (
              <span className="text-xs font-normal text-kumo-subtle">{t('基于最早的 {count} 份待审核报告', { count: queue.inspected })}</span>
            )}
          </LayerCard.Secondary>
          <LayerCard.Primary className="p-0">
            {items.length === 0
              ? <Empty size="sm" icon={<CheckCircleIcon size={32} className="text-kumo-inactive" />} title={t('暂无需要关注的事项。')} />
              : (
                <ul>
                  {items.map(item => (
                    <li key={item.key} className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 border-b border-kumo-hairline px-4 py-3 text-[13px] last:border-0">
                      <StatusIcon tone={item.tone} />
                      <span className="min-w-0">
                        <span className="block truncate text-kumo-default">{item.title}</span>
                        <span className="block truncate text-xs text-kumo-subtle">{item.detail}</span>
                      </span>
                      <Button size="sm" onClick={item.open}>{item.action}</Button>
                    </li>
                  ))}
                </ul>
              )}
          </LayerCard.Primary>
        </LayerCard>

        <div className="flex flex-col gap-4">
          <LayerCard className="p-0">
            <LayerCard.Secondary className="flex items-center justify-between">
              {t('每日新报告')}
              <span className="text-xs font-normal text-kumo-subtle tabular">{t('reportCount', { count: data.daily.reduce((sum, day) => sum + day.count, 0) })}</span>
            </LayerCard.Secondary>
            <LayerCard.Primary>
              <div className="flex h-20 items-end gap-1.5" role="img" aria-label={t('过去 14 天每日新报告')}>
                {data.daily.map((day, index) => (
                  <i
                    key={day.date}
                    title={[day.date, t('reportCount', { count: day.count })].join(' · ')}
                    className={cn('min-h-0.5 flex-1 rounded-t-sm', index === data.daily.length - 1 ? 'bg-kumo-brand' : 'bg-kumo-fill')}
                    style={{ height: `${(day.count / peak) * 100}%` }}
                  />
                ))}
              </div>
              <div className="mt-1.5 flex justify-between text-[11px] text-kumo-subtle tabular">
                <span>{data.daily[0]?.date.slice(5)}</span><span>{t('今天')}</span>
              </div>
            </LayerCard.Primary>
          </LayerCard>

          <LayerCard className="p-0">
            <LayerCard.Secondary>{t('最近操作')}</LayerCard.Secondary>
            <LayerCard.Primary>
              {data.recent.length === 0
                ? <p className="text-[13px] text-kumo-subtle">{t('暂无审核记录。')}</p>
                : (
                  <ul className="flex flex-col gap-2 text-[13px]">
                    {data.recent.map(entry => (
                      <li key={entry.id} className="grid grid-cols-[72px_minmax(0,1fr)] gap-2">
                        <time className="text-kumo-subtle tabular">{elapsed(entry.reviewedAt)}</time>
                        <span className="truncate">
                          {actorTitle(entry.actor)} · {auditAction(entry)}
                          {entry.modelIdentifier && <span className="text-kumo-subtle"> · {modelTitle(entry.modelIdentifier)}</span>}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
            </LayerCard.Primary>
          </LayerCard>
        </div>
      </div>
    </div>
  );
}

function Metric({ label, value, note, warn }: { label: string; value: string; note: string; warn?: boolean }) {
  return (
    <LayerCard>
      <LayerCard.Primary className="flex flex-col gap-0.5">
        <span className="text-xs text-kumo-subtle">{label}</span>
        <span className="text-2xl font-semibold tracking-tight text-kumo-default tabular">{value}</span>
        <span className={cn('text-xs', warn ? 'text-kumo-warning' : 'text-kumo-subtle')}>{note}</span>
      </LayerCard.Primary>
    </LayerCard>
  );
}

/* ---------- Verification candidates and published records ---------- */
export function VerificationLists({ request, onError, onNotice, onPrefill, refresh }: {
  request: Request; onError: OnError; onNotice: (text: string) => void;
  onPrefill: (candidate: VerificationCandidate) => void; refresh: number;
}) {
  const [data, setData] = useState<VerificationList | null>(null);
  const [confirming, setConfirming] = useState<string | null>(null);
  const load = useCallback(async () => {
    try { setData(await request<VerificationList>('/api/admin/verifications')); }
    catch (error) { onError(error); }
  }, [request, onError]);
  useEffect(() => { void load(); }, [load, refresh]);

  const remove = async (item: AdminVerification) => {
    if (confirming !== item.id) { setConfirming(item.id); return; }
    try {
      await request('/api/admin/verifications/' + item.id, mutation('DELETE'));
      onNotice(t('实测记录已撤下。'));
      setConfirming(null);
      await load();
    } catch (error) { onError(error); }
  };

  if (!data) return null;
  return (
    <div className="flex flex-col gap-4">
      <LayerCard className="p-0">
        <LayerCard.Secondary className="flex items-center justify-between gap-3">
          {t('待开发者实测')}
          <span className="text-xs font-normal text-kumo-subtle">
            {t('累计 ≥{count} 份已审核的“请求成功”报告、尚无实测记录的控制能力', { count: data.candidateMinimum })}
          </span>
        </LayerCard.Secondary>
        <LayerCard.Primary className="overflow-x-auto p-0">
          {data.candidates.length === 0
            ? <p className="p-4 text-[13px] text-kumo-subtle">{t('暂无需要安排实测的组合。')}</p>
            : (
              <DataTable>
                <Table.Header>
                  <Table.Row>
                    <Table.Head>{t('机型')}</Table.Head>
                    <Table.Head>{t('版本组合')}</Table.Head>
                    <Table.Head>{t('能力')}</Table.Head>
                    <Table.Head>{t('社区报告')}</Table.Head>
                    <Table.Head>{t('最近报告')}</Table.Head>
                    <Table.Head />
                  </Table.Row>
                </Table.Header>
                <Table.Body>
                  {data.candidates.map(item => (
                    <Table.Row key={item.modelIdentifier + item.macOSVersion + item.appVersion + item.helperVersion + item.capability}>
                      <Table.Cell>{modelTitle(item.modelIdentifier)}<span className="block font-mono text-xs text-kumo-subtle">{item.modelIdentifier}</span></Table.Cell>
                      <Table.Cell className="text-xs text-kumo-subtle">{combination(item)}</Table.Cell>
                      <Table.Cell><StatusLabel tone="pending" label={capabilityTitle(item.capability)} /></Table.Cell>
                      <Table.Cell className="tabular">{t('reportCount', { count: item.reports })}</Table.Cell>
                      <Table.Cell className="text-kumo-subtle tabular">{item.lastReportAt.slice(0, 10)}</Table.Cell>
                      <Table.Cell className="text-right"><Button size="sm" onClick={() => onPrefill(item)}>{t('填写实测')}</Button></Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </DataTable>
            )}
        </LayerCard.Primary>
      </LayerCard>

      <LayerCard className="p-0">
        <LayerCard.Secondary className="flex items-center justify-between gap-3">
          {t('已发布的实测记录')}
          <span className="text-xs font-normal text-kumo-subtle">{t('撤下不会删除用户报告。')}</span>
        </LayerCard.Secondary>
        <LayerCard.Primary className="overflow-x-auto p-0">
          {data.verifications.length === 0
            ? <p className="p-4 text-[13px] text-kumo-subtle">{t('还没有发布实测记录。')}</p>
            : (
              <DataTable>
                <Table.Header>
                  <Table.Row>
                    <Table.Head>{t('机型')}</Table.Head>
                    <Table.Head>{t('版本组合')}</Table.Head>
                    <Table.Head>{t('能力')}</Table.Head>
                    <Table.Head>{t('测试结果')}</Table.Head>
                    <Table.Head>{t('验证日期')}</Table.Head>
                    <Table.Head />
                  </Table.Row>
                </Table.Header>
                <Table.Body>
                  {data.verifications.map(item => (
                    <Table.Row key={item.id}>
                      <Table.Cell>{modelTitle(item.modelIdentifier)}<span className="block font-mono text-xs text-kumo-subtle">{item.id}</span></Table.Cell>
                      <Table.Cell className="text-xs text-kumo-subtle">{combination(item)}</Table.Cell>
                      <Table.Cell>{capabilityTitle(item.capability)}</Table.Cell>
                      <Table.Cell>
                        <StatusLabel tone={toneOf(item.status)} label={statusTitle(item.status)} />
                        <a href={item.sourceURL} target="_blank" rel="noopener noreferrer" className="mt-0.5 flex items-center gap-1 text-xs text-kumo-link no-underline hover:underline">
                          {t('依据 · ')}<ArrowSquareOutIcon size={11} />
                        </a>
                      </Table.Cell>
                      <Table.Cell className="text-kumo-subtle tabular">{item.verifiedOn}</Table.Cell>
                      <Table.Cell className="text-right">
                        <Button size="sm" variant={confirming === item.id ? 'destructive' : 'secondary-destructive'} onClick={() => void remove(item)}>
                          {confirming === item.id ? t('确认撤下') : t('撤下记录')}
                        </Button>
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </DataTable>
            )}
        </LayerCard.Primary>
      </LayerCard>
    </div>
  );
}

/* ---------- Audit log ---------- */
export function AuditTab({ request, onError }: { request: Request; onError: OnError }) {
  const [type, setType] = useState('all');
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<AuditList | null>(null);
  const load = useCallback(async (at: number) => {
    try {
      setData(await request<AuditList>('/api/admin/audit?' + new URLSearchParams({ type, offset: String(at) })));
      setOffset(at);
    } catch (error) { onError(error); }
  }, [request, onError, type]);
  useEffect(() => { void load(0); }, [load]);

  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary className="flex flex-wrap items-center justify-between gap-3">
        <span className="flex items-center gap-2 text-xs font-normal text-kumo-subtle">
          <ListChecksIcon size={14} />
          {t('记录每个审核和实测决定。审核记录保留 90 天；用户撤回报告时，相关审核记录一并删除。')}
        </span>
        <Select
          aria-label={t('记录类型')}
          size="sm"
          className="w-36"
          value={type}
          onValueChange={value => value && setType(value as string)}
          items={{ all: t('全部'), report: t('报告审核'), verification: t('开发者验证') }}
        />
      </LayerCard.Secondary>
      <LayerCard.Primary className="overflow-x-auto p-0">
        {data && data.entries.length === 0
          ? <p className="p-4 text-[13px] text-kumo-subtle">{t('暂无审核记录。')}</p>
          : (
            <DataTable>
              <Table.Header>
                <Table.Row>
                  <Table.Head>{t('时间')}</Table.Head>
                  <Table.Head>{t('操作者')}</Table.Head>
                  <Table.Head>{t('操作')}</Table.Head>
                  <Table.Head>{t('对象')}</Table.Head>
                  <Table.Head>{t('审核理由')}</Table.Head>
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {data?.entries.map(entry => (
                  <Table.Row key={entry.id}>
                    <Table.Cell className="whitespace-nowrap text-kumo-subtle tabular">{new Date(entry.reviewedAt).toLocaleString()}</Table.Cell>
                    <Table.Cell className="max-w-48 truncate">{actorTitle(entry.actor)}</Table.Cell>
                    <Table.Cell>{auditAction(entry)}</Table.Cell>
                    <Table.Cell>
                      {entry.modelIdentifier ? modelTitle(entry.modelIdentifier) : <span className="text-kumo-subtle">{t('已删除或已过期')}</span>}
                      <span className="block font-mono text-xs text-kumo-subtle">{entry.objectID}</span>
                    </Table.Cell>
                    <Table.Cell className="text-kumo-subtle">{reasonTitles[entry.reason] ? t(reasonTitles[entry.reason]) : entry.reason}</Table.Cell>
                  </Table.Row>
                ))}
              </Table.Body>
            </DataTable>
          )}
        <div className="flex items-center gap-2 border-t border-kumo-hairline px-4 py-2.5">
          <Button size="sm" disabled={offset === 0} onClick={() => void load(Math.max(0, offset - pageSize))}>{t('上一页')}</Button>
          <Button size="sm" disabled={!data?.hasMore} onClick={() => void load(offset + pageSize)}>{t('下一页')}</Button>
          <span className="text-xs text-kumo-subtle">{t('pageNumber', { page: offset / pageSize + 1 })}</span>
        </div>
      </LayerCard.Primary>
    </LayerCard>
  );
}
