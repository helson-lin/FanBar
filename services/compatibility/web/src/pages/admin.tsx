import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Badge } from '@cloudflare/kumo/components/badge';
import { Banner } from '@cloudflare/kumo/components/banner';
import { Button } from '@cloudflare/kumo/components/button';
import { Collapsible } from '@cloudflare/kumo/components/collapsible';
import { Empty } from '@cloudflare/kumo/components/empty';
import { Input, InputArea } from '@cloudflare/kumo/components/input';
import { LayerCard } from '@cloudflare/kumo/components/layer-card';
import { Select } from '@cloudflare/kumo/components/select';
import { Table } from '@cloudflare/kumo/components/table';
import { Tabs } from '@cloudflare/kumo/components/tabs';
import { cn } from '@cloudflare/kumo/utils';
import { ArrowClockwiseIcon, TrayIcon, WarningCircleIcon } from '@phosphor-icons/react';
import { AuditTab, FlagBadges, OverviewTab, VerificationLists } from '../components/admin-insights';
import { AccountMenu, AreaNav, ExpiredGate, LocalDevelopmentBanner, UnconfiguredGate, type Area } from '../components/admin-shell';
import { UpdateStatsArea } from '../components/update-stats';
import { DataTable } from '../components/data-table';
import { Page, PageTitle, SiteHeader } from '../components/shell';
import { StatusLabel } from '../components/status';
import { t } from '../i18n';
import {
  ApiError, api, failureSummary, type AdminDetail, type AdminList, type AdminSession, type Overview, type Capability, type ReviewReason, type ReviewStatus, type VerificationCandidate,
  type VerificationStatus,
} from '../lib/api';
import { capabilityOrder, capabilityTitle, errorMessage, modelTitle, statusTitle, toneOf } from '../lib/labels';
import { mount } from '../lib/mount';

const pageSize = 50;
const reviewTitle: Record<ReviewStatus, string> = { pending: '待审核', approved: '已纳入统计', rejected: '已排除' };
const reasonTitle: Record<ReviewReason, string> = {
  reviewed: '已检查字段与证据', duplicate: '疑似重复报告', invalid: '无效报告', needsInvestigation: '需进一步调查',
};
const translateAll = <K extends string>(record: Record<K, string>) =>
  Object.fromEntries(Object.entries(record).map(([key, value]) => [key, t(value as string)])) as Record<K, string>;

type Notice = { tone: 'info' | 'error'; text: string } | null;

type Gate = 'loading' | 'ready' | 'expired' | 'unconfigured';
const areaFromHash = (): Area => (location.hash === '#updates' ? 'updates' : 'compat');

function AdminPage() {
  // Cloudflare Access holds the session in its cookie; the page only asks who is signed in.
  const [session, setSession] = useState<AdminSession | null>(null);
  const [gate, setGate] = useState<Gate>('loading');
  const [area, setArea] = useState<Area>(areaFromHash);
  const [pending, setPending] = useState<number | null>(null);
  const [tab, setTab] = useState('overview');
  // A report opened from the overview; the review tab selects it.
  const [focus, setFocus] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice>(null);

  const request = useCallback(<T,>(path: string, options: RequestInit = {}) => api<T>(path, options), []);

  const fail = useCallback((error: unknown) => {
    if (error instanceof ApiError && error.code === 'ADMIN_AUTHENTICATION_REQUIRED') { setGate('expired'); return; }
    if (error instanceof ApiError && error.code === 'ADMIN_ACCESS_NOT_CONFIGURED') { setGate('unconfigured'); return; }
    setNotice({ tone: 'error', text: errorMessage(error) });
  }, []);

  const refreshPending = useCallback(async () => {
    try { setPending((await api<Overview>('/api/admin/overview')).queue.pending); }
    catch { /* The count is a hint; the tabs report their own errors. */ }
  }, []);

  useEffect(() => {
    void (async () => {
      try {
        setSession(await api<AdminSession>('/api/admin/session'));
        setGate('ready');
        void refreshPending();
      } catch (error) {
        fail(error);
        if (!(error instanceof ApiError && error.code.startsWith('ADMIN_'))) setGate('ready');
      }
    })();
  }, [fail, refreshPending]);

  useEffect(() => {
    const follow = () => setArea(areaFromHash());
    addEventListener('hashchange', follow);
    return () => removeEventListener('hashchange', follow);
  }, []);
  const switchArea = (next: Area) => {
    setArea(next);
    setNotice(null);
    history.replaceState(null, '', next === 'updates' ? '#updates' : location.pathname + location.search);
  };

  const signedIn = gate === 'ready' && session !== null;
  return (
    <>
      <SiteHeader
        subtitle="管理后台"
        nav={signedIn ? <AreaNav area={area} pending={pending} onChange={switchArea} /> : undefined}
        links={[
          { href: '/', label: '公开兼容性页 ↗' },
          { href: 'https://update.getfanbar.com/', label: 'update.getfanbar.com ↗', external: true },
        ]}
        account={<AccountMenu session={gate === 'ready' ? session : null} />}
      />
      <Page>
        {gate === 'expired' && <ExpiredGate />}
        {gate === 'unconfigured' && <UnconfiguredGate />}
        {gate === 'ready' && !session && notice && <NoticeLine notice={notice} />}

        {signedIn && (
          <>
            {session.kind === 'localDevelopment' && <LocalDevelopmentBanner />}
            {area === 'updates' && <UpdateStatsArea request={request} onError={fail} />}
            {area === 'compat' && (
              <>
                <PageTitle
                  title="把报告变成可信的兼容性记录。"
                  lede="审核通过只纳入社区统计。开发者验证需要独立实测与公开依据，不能由用户请求成功自动推导。"
                  aside={<Badge variant="secondary">{t('原始报告默认私有')}</Badge>}
                />
                <Tabs
                  variant="underline"
                  className="mb-5"
                  value={tab}
                  onValueChange={setTab}
                  tabs={[
                    { value: 'overview', label: t('概览') }, { value: 'review', label: t('审核报告') }, { value: 'verify', label: t('开发者验证') },
                    { value: 'audit', label: t('审核记录') }, { value: 'diagnostics', label: t('诊断日志') },
                  ]}
                />
                {notice && <NoticeLine notice={notice} />}
                {tab === 'overview' && (
                  <OverviewTab
                    request={request}
                    onReady={overview => setPending(overview.queue.pending)}
                    onError={fail}
                    onOpenReport={id => { setFocus(id); setTab('review'); }}
                    onOpenVerification={() => setTab('verify')}
                  />
                )}
                {tab === 'review' && <ReviewTab request={request} focus={focus} onReady={refreshPending} onError={fail} onNotice={setNotice} />}
                {tab === 'verify' && <VerifyTab request={request} onError={fail} onNotice={setNotice} />}
                {tab === 'audit' && <AuditTab request={request} onError={fail} />}
                {tab === 'diagnostics' && <DiagnosticsTab request={request} onError={fail} />}
              </>
            )}
          </>
        )}
      </Page>
    </>
  );
}

type Request = <T>(path: string, options?: RequestInit) => Promise<T>;
const mutation = (method: string, body?: unknown): RequestInit => ({
  method,
  headers: { 'X-FanBar-Admin': '1', 'Content-Type': 'application/json' },
  ...(body ? { body: JSON.stringify(body) } : {}),
});

function NoticeLine({ notice }: { notice: NonNullable<Notice> }) {
  if (notice.tone === 'error') {
    return <Banner className="mb-4" variant="error" icon={<WarningCircleIcon weight="fill" />} description={notice.text} />;
  }
  return <p className="mb-4 text-xs text-kumo-subtle" role="status">{notice.text}</p>;
}

type DiagnosticDetail = {
  diagnostic: {
    device?: { helperVersion: string };
    runningHelper?: { status: 'reported' | 'noReply' | 'connectionFailed' | 'notQueried'; build?: string; code?: number };
    connectionErrorCode?: number;
    helperState?: string; helperStateSource?: string;
    runtimeEvents?: { timestamp: string; sessionID: string; requestID?: string; component: string; action: string;
      outcome: string; code?: number; value?: number; durationMS?: number; fanIndex?: number; manual?: boolean }[];
    helperLogAvailable?: boolean; crashLogAvailable?: boolean;
    crashes?: { recordedAt: string; process: string; exception: string; signal: string; terminationNamespace: string; terminationCode?: number }[];
    runtimeContext?: { appBuild: string; osBuild: string; architecture: string; bundleLocation: string; helperPresent: boolean };
    recentSamples?: unknown[];
    discovery?: { reportedKeyCount?: number; scannedKeyCount: number; truncated: boolean; probesTruncated?: boolean; errorCode?: number };
    probes: { sensor: string; key?: string; source?: string; stage?: string; result: string; value?: number;
      code?: number; dataType?: string; dataSize?: number; rawBytes?: string; recognized?: boolean; name?: string }[];
  };
};

function DiagnosticEvidence({ detail }: { detail: DiagnosticDetail }) {
  const data = detail.diagnostic;
  const hints: string[] = [];
  if (data.runtimeEvents?.some(event => event.action === 'previousExitUnknown')) { hints.push(t('上次未记录正常退出；需结合崩溃摘要判断，也可能是强制退出或关机。')); }
  if (data.runtimeEvents?.some(event => event.outcome === 'requiresApproval')) { hints.push(t('曾处于等待系统授权状态，请对照后续状态变化。')); }
  if (data.runtimeEvents?.some(event => event.action === 'timeout')) { hints.push(t('存在控制服务超时，请按请求编号对照连接与控制事件。')); }
  if (data.helperLogAvailable === false) { hints.push(t('未能读取 Helper 事件，不能据此认定 Helper 没有运行。')); }
  if (data.crashLogAvailable === false) { hints.push(t('无法访问崩溃日志目录，空列表不代表没有崩溃。')); }
  if (data.connectionErrorCode !== undefined) { hints.push(t('SMC 连接失败，请先排查设备访问或连接恢复。')); }
  if (data.probes.some(row => row.recognized === false && row.result === 'available')) { hints.push(t('发现应用尚未识别的有效温度键，需要补充机型传感器映射。')); }
  if (data.probes.some(row => row.result === 'unsupportedFormat')) { hints.push(t('存在无法解码的数据格式，请结合类型、长度和原始字节检查解码器。')); }
  if (data.probes.some(row => row.result === 'outOfRange')) { hints.push(t('部分读数被有效范围过滤，请检查原始值与单位。')); }
  if (data.discovery?.truncated) { hints.push(t('传感器枚举未完成，当前结果不能代表全部硬件键。')); }
  if (data.discovery?.probesTruncated) { hints.push(t('键名清单完整，但部分未识别键没有附带读数探测。')); }
  const helper = data.runningHelper;
  if (helper?.status === 'reported' && data.device && helper.build !== data.device.helperVersion) {
    hints.push(t('运行中的 Helper（build {running}）与应用内置版本（build {bundled}）不一致：旧守护进程仍在运行，需要重新注册或重启。',
      { running: helper.build ?? '?', bundled: data.device.helperVersion }));
  }
  if (helper?.status === 'noReply') { hints.push(t('运行中的 Helper 未响应版本查询：可能是早于版本查询的旧 Helper，或已无响应。')); }
  if (helper?.status === 'connectionFailed') { hints.push(t('Helper 已启用但无法建立连接，请对照 XPC 事件与错误码。')); }
  return <div className="flex flex-col gap-4">
    <h2 className="text-base font-semibold">{t('诊断线索')}</h2>
    {data.helperState && <p className="text-xs text-kumo-subtle">Helper: {data.helperState} · {data.helperStateSource ?? 'runtime'}{helper && ` · running ${helper.status}${helper.build ? ' build ' + helper.build : ''}`}</p>}
    {data.runtimeContext && <p className="text-xs text-kumo-subtle">Build {data.runtimeContext.appBuild} · macOS {data.runtimeContext.osBuild} · {data.runtimeContext.architecture} · {data.runtimeContext.bundleLocation} · Helper {String(data.runtimeContext.helperPresent)}</p>}
    {hints.map(hint => <p key={hint} className="text-sm text-kumo-subtle">{hint}</p>)}
    <p className="text-xs text-kumo-subtle">{t('最近采样数')}：{data.recentSamples?.length ?? 0} · {t('探测条目')}：{data.probes.length}</p>
    {data.discovery && <p className="text-xs text-kumo-subtle">{t('扫描键数')}：{data.discovery.scannedKeyCount} / {data.discovery.reportedKeyCount ?? '—'} · {t('错误码')}：{data.discovery.errorCode ?? '—'}</p>}
    <div className="overflow-auto"><table className="w-full text-left text-xs">
      <thead><tr>{['来源 / 键', '阶段 / 结果', '读数 / 错误码', '类型 / 长度 / 原始字节'].map(label => <th key={label} className="p-3">{t(label)}</th>)}</tr></thead>
      <tbody>{data.probes.map((row, index) => <tr key={index} className="border-t border-kumo-line">
        <td className="p-3">{row.sensor} · {row.source ?? 'smc'} · {row.key ?? row.name ?? '—'}</td>
        <td className="p-3">{row.stage ?? '—'} · {row.result}</td>
        <td className="p-3">{row.value ?? '—'} / {row.code === undefined ? '—' : `${row.code} (0x${(row.code >>> 0).toString(16)})`}</td>
        <td className="p-3 font-mono">{row.dataType ?? '—'} / {row.dataSize ?? '—'} / {row.rawBytes ?? '—'}</td>
      </tr>)}</tbody>
    </table></div>
    {!!data.crashes?.length && <section className="flex flex-col gap-3">
      <h3 className="text-sm font-semibold">{t('崩溃摘要')}</h3>
      {data.crashes.map((crash, index) => <p key={index} className="text-xs">{new Date(crash.recordedAt).toLocaleString()} · {crash.process} · {crash.exception} · {crash.signal} · {crash.terminationNamespace} / {crash.terminationCode ?? '—'}</p>)}
    </section>}
    {!!data.runtimeEvents?.length && <section className="flex flex-col gap-3">
      <h3 className="text-sm font-semibold">{t('运行事件时间线')}</h3>
      <div className="max-h-96 overflow-auto"><table className="w-full text-left text-xs">
        <thead><tr>{['时间', '组件 / 操作', '结果 / 错误码', '参数 / 耗时', '请求编号'].map(label => <th key={label} className="p-3">{t(label)}</th>)}</tr></thead>
        <tbody>{[...data.runtimeEvents].sort((a, b) => a.timestamp.localeCompare(b.timestamp)).map((event, index) => <tr key={index} className="border-t border-kumo-line">
          <td className="whitespace-nowrap p-3">{new Date(event.timestamp).toLocaleTimeString()}</td>
          <td className="p-3">{event.component} / {event.action}</td>
          <td className="p-3">{event.outcome} / {event.code ?? '—'}</td>
          <td className="p-3">{event.value ?? '—'} / {event.durationMS?.toFixed(1) ?? '—'} ms {event.fanIndex !== undefined && `fan=${event.fanIndex} manual=${event.manual}`}</td>
          <td className="p-3 font-mono">{event.requestID ?? '—'}</td>
        </tr>)}</tbody>
      </table></div>
    </section>}
    <details><summary className="cursor-pointer text-sm">{t('完整诊断数据')}</summary>
      <pre className="mt-3 overflow-auto rounded-xl bg-kumo-control p-4 text-xs">{JSON.stringify(detail, null, 2)}</pre>
    </details>
  </div>;
}

function DiagnosticsTab({ request, onError }: { request: Request; onError: (error: unknown) => void }) {
  const [rows, setRows] = useState<{ id: string; model_identifier: string; created_at: string }[]>([]);
  const [id, setID] = useState('');
  const [detail, setDetail] = useState<DiagnosticDetail | null>(null);
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    setBusy(true);
    try { setRows((await request<{ diagnostics: typeof rows }>('/api/admin/diagnostics')).diagnostics); }
    catch (error) { onError(error); }
    finally { setBusy(false); }
  }, [request, onError]);
  useEffect(() => { void load(); }, [load]);
  const open = async (value: string) => {
    setBusy(true); setDetail(null);
    try { setDetail(await request<DiagnosticDetail>('/api/admin/diagnostics?id=' + encodeURIComponent(value.trim()))); }
    catch (error) { onError(error); }
    finally { setBusy(false); }
  };
  return <section className="flex flex-col gap-5">
    <p className="text-sm text-kumo-subtle">{t('日志仅管理员可见，保留 90 天，不参与兼容性统计。')}</p>
    <form className="flex items-end gap-3" onSubmit={event => { event.preventDefault(); void open(id); }}>
      <Input label={t('诊断编号')} value={id} onChange={event => setID(event.target.value)} className="grow" />
      <Button type="submit" disabled={busy || !id.trim()}>{t('查看详情')}</Button>
      <Button type="button" disabled={busy} onClick={() => void load()}>{t('刷新')}</Button>
    </form>
    {detail !== null && <DiagnosticEvidence detail={detail} />}
    <p className="text-xs text-kumo-subtle">{t('最近 50 份诊断日志；更早的记录可通过诊断编号查询。')}</p>
    <ul className="divide-y divide-kumo-line">
      {rows.map(row => <li key={row.id} className="flex items-center justify-between gap-4 py-4">
        <div className="min-w-0"><p>{modelTitle(row.model_identifier)}</p>
          <p className="break-all font-mono text-xs text-kumo-subtle">{row.id}</p>
          <p className="text-xs text-kumo-subtle">{new Date(row.created_at).toLocaleString()}</p></div>
        <Button disabled={busy} onClick={() => { setID(row.id); void open(row.id); }}>{t('查看详情')}</Button>
      </li>)}
    </ul>
  </section>;
}

/* ---------- Review ---------- */
function ReviewTab({ request, focus, onReady, onError, onNotice }: {
  request: Request; focus: string | null; onReady: () => void; onError: (error: unknown) => void; onNotice: (notice: Notice) => void;
}) {
  const [status, setStatus] = useState<ReviewStatus | 'all'>('pending');
  const [model, setModel] = useState('');
  const [version, setVersion] = useState('');
  const [offset, setOffset] = useState(0);
  const [list, setList] = useState<AdminList | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminDetail | null>(null);
  const [loading, setLoading] = useState(false);

  // Filters take effect when "查询" is pressed; a new object re-runs the query even if unchanged.
  const [applied, setApplied] = useState({ status, model: '', version: '' });

  const load = useCallback(async (at: number) => {
    setLoading(true);
    onNotice({ tone: 'info', text: t('正在读取报告…') });
    const query = new URLSearchParams({ status: applied.status, model: applied.model, appVersion: applied.version, offset: String(at) });
    try {
      setList(await request<AdminList>('/api/admin/reports?' + query));
      setOffset(at);
      onReady();
      onNotice({ tone: 'info', text: t('读取完成。凭证和内部哈希不会返回到管理页面。') });
    } catch (error) { onError(error); }
    finally { setLoading(false); }
  }, [request, applied, onReady, onError, onNotice]);

  const show = useCallback(async (id: string) => {
    setSelected(id);
    try { setDetail(await request<AdminDetail>('/api/admin/reports/' + id)); }
    catch (error) { onError(error); }
  }, [request, onError]);

  useEffect(() => { void load(0); }, [load]);
  useEffect(() => { if (focus) void show(focus); }, [focus, show]);

  return (
    <div className="flex flex-col gap-4">
      <LayerCard>
        <LayerCard.Primary>
          <form
            onSubmit={event => { event.preventDefault(); setApplied({ status, model: model.trim(), version: version.trim() }); }}
            className="flex flex-row flex-wrap items-end gap-3"
          >
          <Select
            label={t('审核状态')}
            hideLabel={false}
            className="w-40"
            value={status}
            onValueChange={value => value && setStatus(value as ReviewStatus | 'all')}
            items={{ ...translateAll(reviewTitle), all: t('全部') }}
          />
          <div className="min-w-48 flex-1">
            <Input aria-label={t('按机型标识筛选')} placeholder={t('按机型标识筛选')} maxLength={64} value={model} onChange={event => setModel(event.target.value)} className="w-full font-mono" />
          </div>
          <div className="w-40">
            <Input aria-label={t('FanBar 版本')} placeholder={t('FanBar 版本')} maxLength={40} value={version} onChange={event => setVersion(event.target.value)} className="w-full" />
          </div>
          <Button type="submit" icon={ArrowClockwiseIcon} loading={loading}>{t('查询')}</Button>
          </form>
        </LayerCard.Primary>
      </LayerCard>

      <div className="grid items-start gap-4 lg:grid-cols-[300px_minmax(0,1fr)]">
        <LayerCard className="p-0">
          <LayerCard.Primary className="p-0">
            {list?.reports.length === 0 && <p className="p-4 text-[13px] text-kumo-subtle">{t('当前筛选没有报告。')}</p>}
            {list?.reports.map(row => (
              <button
                key={row.id}
                type="button"
                onClick={() => void show(row.id)}
                aria-pressed={row.id === selected}
                className={cn(
                  'block w-full border-b border-kumo-hairline px-4 py-3 text-left text-[13px] last:border-0 hover:bg-kumo-tint',
                  row.id === selected && 'bg-kumo-info-tint shadow-[inset_2px_0_var(--color-kumo-brand)]',
                )}
              >
                <span className="flex items-center justify-between gap-2">
                  <b className="font-semibold">{modelTitle(row.model_identifier)}</b>
                  {applied.status === 'all' && <Badge variant="secondary">{t(reviewTitle[row.status])}</Badge>}
                </span>
                <span className="block font-mono text-xs text-kumo-subtle">{row.model_identifier}</span>
                <span className="block text-xs text-kumo-subtle">macOS {row.os_version} · FanBar {row.app_version}</span>
                <span className="block text-xs text-kumo-subtle tabular">
                  {row.created_at.slice(0, 10)} · {t(row.publish_report ? '用户选择公开' : '原始报告私有')}
                </span>
                {row.flags.length > 0 && <span className="mt-1.5 flex flex-wrap gap-1"><FlagBadges flags={row.flags} /></span>}
              </button>
            ))}
            <div className="flex items-center gap-2 border-t border-kumo-hairline px-4 py-2.5">
              <Button size="sm" disabled={offset === 0 || loading} onClick={() => void load(Math.max(0, offset - pageSize))}>{t('上一页')}</Button>
              <Button size="sm" disabled={!list?.hasMore || loading} onClick={() => void load(offset + pageSize)}>{t('下一页')}</Button>
              <span className="text-xs text-kumo-subtle">{t('pageNumber', { page: offset / pageSize + 1 })}</span>
            </div>
          </LayerCard.Primary>
        </LayerCard>

        {detail && selected
          ? <ReportDetail id={selected} detail={detail} request={request} onError={onError} onOpen={id => void show(id)} onChanged={() => { void show(selected); void load(offset); }} />
          : (
            <LayerCard>
              <LayerCard.Primary>
                <Empty size="sm" icon={<TrayIcon size={32} className="text-kumo-inactive" />} title={t('选择一份报告')} description={t('查看具体字段，再决定是否纳入社区统计。')} />
              </LayerCard.Primary>
            </LayerCard>
          )}
      </div>
    </div>
  );
}

function ReportDetail({ id, detail, request, onError, onOpen, onChanged }: {
  id: string; detail: AdminDetail; request: Request; onError: (error: unknown) => void; onOpen: (id: string) => void; onChanged: () => void;
}) {
  const [reason, setReason] = useState<ReviewReason>('reviewed');
  const [busy, setBusy] = useState<ReviewStatus | null>(null);
  const { report } = detail;
  const byCapability = new Map(report.capabilities.map(row => [row.capability, row]));
  const { comparison } = detail;
  const compared = new Map(comparison.capabilities.map(row => [row.capability, row]));

  const review = async (status: ReviewStatus) => {
    setBusy(status);
    try {
      await request('/api/admin/reports/' + id + '/review', mutation('PUT', { status, reason }));
      onChanged();
    } catch (error) { onError(error); }
    finally { setBusy(null); }
  };

  return (
    <LayerCard className="p-0">
      <LayerCard.Secondary className="flex flex-col items-stretch gap-1">
        <div className="flex items-center justify-between gap-3">
          <span className="text-base font-semibold text-kumo-default">{modelTitle(report.device.modelIdentifier)}</span>
              <span className="font-mono text-xs text-kumo-subtle">{report.device.modelIdentifier}</span>
          <Badge variant={detail.status === 'approved' ? 'success' : detail.status === 'rejected' ? 'error' : 'secondary'} appearance={detail.status === 'pending' ? 'filled' : 'dot'}>
            {t(reviewTitle[detail.status])}
          </Badge>
        </div>
        <span className="text-xs font-normal text-kumo-subtle">
          {report.device.processor} · macOS {report.device.macOSVersion} · FanBar {report.device.appVersion} · Helper {report.device.helperVersion}
        </span>
        <span className="text-xs font-normal text-kumo-subtle">
          {t(detail.publishReport ? '用户选择公开：审核通过后可通过报告编号查阅。' : '原始报告私有：审核通过只贡献汇总统计。')}
        </span>
        <span className="text-xs font-normal text-kumo-subtle">{t('报告编号：')}<span className="font-mono">{id}</span></span>
        {comparison.flags.length > 0 && <span className="mt-1 flex flex-wrap gap-1"><FlagBadges flags={comparison.flags} /></span>}
      </LayerCard.Secondary>
      <LayerCard.Primary className="flex flex-col gap-0 p-0">
        <DataTable>
          <Table.Header>
            <Table.Row>
              <Table.Head>{t('能力')}</Table.Head>
              <Table.Head>{t('本报告')}</Table.Head>
              <Table.Head>{t('同版本已审核报告')}</Table.Head>
              <Table.Head>{t('对比')}</Table.Head>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {capabilityOrder.map(capability => {
              const row = byCapability.get(capability);
              const other = compared.get(capability);
              return (
                <Table.Row key={capability} className={cn(other?.agrees === false && '!bg-fanbar-mixed-tint')}>
                  <Table.Cell>{capabilityTitle(capability)}</Table.Cell>
                  <Table.Cell>{row && <span className="flex flex-col gap-1">
                    <StatusLabel tone={row.userConfirmedWorking ? 'ok' : toneOf(row.status)} label={row.userConfirmedWorking ? t('本机实测可用（用户确认）') : statusTitle(row.status)} />
                    {row.userConfirmedWorking && <span className="text-xs text-kumo-subtle">{t('自动检测：{status}', { status: statusTitle(row.status) })}</span>}
                    <span className="font-mono text-[11px] text-kumo-subtle">{row.reasonCode}</span>
                    {row.failure && <span className="font-mono text-[11px] text-kumo-subtle">{failureSummary(row.failure)}</span>}
                  </span>}</Table.Cell>
                  <Table.Cell>
                    {other && other.existing.length > 0
                      ? <span className="flex flex-col gap-0.5">{other.existing.map(item => (
                        <span key={item.status} className="flex items-center gap-2">
                          <StatusLabel tone={toneOf(item.status)} label={statusTitle(item.status)} className="font-normal" />
                          <span className="text-xs text-kumo-subtle tabular">{t('reportCount', { count: item.count })}</span>
                        </span>
                      ))}</span>
                      : <span className="text-kumo-subtle">—</span>}
                    {other?.verification && (
                      <span className="mt-1 block text-xs text-kumo-subtle">
                        {t('开发者验证')} · {statusTitle(other.verification.status)} · {other.verification.verified_on}
                      </span>
                    )}
                  </Table.Cell>
                  <Table.Cell className="text-xs">
                    {other?.agrees === false
                      ? <StatusLabel tone="mixed" label={t('不一致')} />
                      : other?.agrees ? <span className="text-kumo-subtle">{t('一致')}</span> : <span className="text-kumo-subtle">—</span>}
                  </Table.Cell>
                </Table.Row>
              );
            })}
          </Table.Body>
        </DataTable>

        {(comparison.flags.includes('conflict') || comparison.duplicateOf.length > 0 || comparison.otherApprovedReports === 0) && (
          <div className="flex flex-col gap-2 border-t border-kumo-hairline p-4 text-[13px]">
            {comparison.otherApprovedReports === 0 && <p className="text-kumo-subtle">{t('同一版本组合还没有其他已审核报告，无法对比。')}</p>}
            {comparison.flags.includes('conflict') && (
              <p className="rounded-md border border-kumo-hairline bg-fanbar-mixed-tint p-3 text-kumo-default">
                {t('结果冲突本身不是排除理由。字段正常就应纳入，公开页会如实显示“结果不一致”。')}
              </p>
            )}
            {comparison.duplicateOf.length > 0 && (
              <div className="flex flex-wrap items-center gap-2 text-kumo-subtle">
                {t('与以下报告内容相同，且相隔不到 10 分钟提交：')}
                {comparison.duplicateOf.map(other => (
                  <Button key={other} size="xs" variant="ghost" className="font-mono" onClick={() => onOpen(other)}>{other.slice(0, 8)}</Button>
                ))}
              </div>
            )}
          </div>
        )}

        <div className="border-t border-kumo-hairline px-4 py-3">
          <Collapsible.Root>
            <Collapsible.DefaultTrigger>{t('原始字段')}</Collapsible.DefaultTrigger>
            <Collapsible.DefaultPanel>
              <pre className="mt-2 overflow-auto rounded-md bg-kumo-recessed p-3 font-mono text-xs leading-relaxed text-kumo-default">{JSON.stringify(report, null, 2)}</pre>
            </Collapsible.DefaultPanel>
          </Collapsible.Root>
        </div>

        <div className="flex flex-wrap items-end gap-2 border-t border-kumo-hairline p-4">
          <Select
            label={t('审核理由')}
            hideLabel={false}
            className="w-48"
            value={reason}
            onValueChange={value => value && setReason(value as ReviewReason)}
            items={translateAll(reasonTitle)}
          />
          <Button variant="primary" loading={busy === 'approved'} disabled={busy !== null} onClick={() => void review('approved')}>{t('纳入社区统计')}</Button>
          <Button variant="secondary-destructive" loading={busy === 'rejected'} disabled={busy !== null} onClick={() => void review('rejected')}>{t('排除报告')}</Button>
          <Button variant="ghost" loading={busy === 'pending'} disabled={busy !== null} onClick={() => void review('pending')}>{t('恢复待审核')}</Button>
        </div>

        {detail.reviews.length > 0 && (
          <div className="border-t border-kumo-hairline p-4">
            <p className="mb-2 text-xs font-semibold text-kumo-subtle">{t('最近审核记录')}</p>
            <ul className="flex flex-col gap-1 text-xs text-kumo-subtle tabular">
              {detail.reviews.map(item => (
                <li key={item.reviewed_at + item.status}>
                  {item.reviewed_at.slice(0, 10)} · {t(reviewTitle[item.status])} · {t(reasonTitle[item.reason])}
                </li>
              ))}
            </ul>
          </div>
        )}
      </LayerCard.Primary>
    </LayerCard>
  );
}

/* ---------- Developer verification ---------- */
const emptyVerification = { modelIdentifier: '', macOSVersion: '', appVersion: '', helperVersion: '', verifiedOn: '', sourceURL: '', notes: '' };

function VerifyTab({ request, onError, onNotice }: { request: Request; onError: (error: unknown) => void; onNotice: (notice: Notice) => void }) {
  const [form, setForm] = useState(emptyVerification);
  const [capability, setCapability] = useState<Capability>('cpuTemperature');
  const [result, setResult] = useState<VerificationStatus>('verifiedAvailable');
  const [busy, setBusy] = useState(false);
  const [refresh, setRefresh] = useState(0);

  const prefill = (candidate: VerificationCandidate) => {
    setForm({ ...emptyVerification, modelIdentifier: candidate.modelIdentifier, macOSVersion: candidate.macOSVersion,
      appVersion: candidate.appVersion, helperVersion: candidate.helperVersion });
    setCapability(candidate.capability);
    document.getElementById('verification-form')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const field = (name: keyof typeof emptyVerification) => ({
    value: form[name],
    onChange: (event: { target: { value: string } }) => setForm(current => ({ ...current, [name]: event.target.value })),
  });

  const publish = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    try {
      await request('/api/admin/verifications', mutation('POST', { ...form, capability, status: result }));
      onNotice({ tone: 'info', text: t('已发布独立实测记录。') });
      setForm(emptyVerification);
      setRefresh(value => value + 1);
    } catch (error) { onError(error); }
    finally { setBusy(false); }
  };

  return (
    <div className="flex flex-col gap-4">
      <VerificationLists
        request={request}
        onError={onError}
        onNotice={text => onNotice({ tone: 'info', text })}
        onPrefill={prefill}
        refresh={refresh}
      />
      <LayerCard className="scroll-mt-4 p-0" id="verification-form">
        <LayerCard.Secondary>
          {t('发布独立实测记录')}
          <p className="text-xs font-normal text-kumo-subtle">{t('完成对应功能的实际测试后填写。此记录长期公开，附带来源；填写“手动调速可用”需要实际控制证据。')}</p>
        </LayerCard.Secondary>
        <LayerCard.Primary>
          <form onSubmit={publish} className="grid gap-4 sm:grid-cols-2">
          <Input label={t('机型标识')} required maxLength={64} className="w-full font-mono" {...field('modelIdentifier')} />
          <Input label={t('macOS 版本')} required maxLength={40} className="w-full" {...field('macOSVersion')} />
          <Input label={t('FanBar 版本')} required maxLength={40} className="w-full" {...field('appVersion')} />
          <Input label={t('Helper 版本')} required maxLength={40} className="w-full" {...field('helperVersion')} />
          <Select
            label={t('实测能力')}
            hideLabel={false}
            className="w-full"
            value={capability}
            onValueChange={value => value && setCapability(value as Capability)}
            items={Object.fromEntries(capabilityOrder.map(item => [item, capabilityTitle(item)]))}
          />
          <Select
            label={t('测试结果')}
            hideLabel={false}
            className="w-full"
            value={result}
            onValueChange={value => value && setResult(value as VerificationStatus)}
            items={{ verifiedAvailable: statusTitle('verifiedAvailable'), verifiedUnsupported: statusTitle('verifiedUnsupported') }}
          />
          <Input label={t('验证日期')} type="date" required className="w-full" {...field('verifiedOn')} />
          <Input label={t('公开依据 URL')} type="url" required placeholder="https://…" className="w-full" {...field('sourceURL')} />
          <div className="sm:col-span-2">
            <InputArea label={t('验证说明')} required maxLength={500} rows={3} className="w-full" {...field('notes')} />
          </div>
          <div className="sm:col-span-2">
            <Button type="submit" variant="primary" loading={busy}>{t('发布实测记录')}</Button>
          </div>
        </form>
        </LayerCard.Primary>
      </LayerCard>

    </div>
  );
}

mount('管理后台 · FanBar', <AdminPage />);
