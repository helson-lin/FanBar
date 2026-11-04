import { Banner } from '@cloudflare/kumo/components/banner';
import { Button } from '@cloudflare/kumo/components/button';
import { LayerCard } from '@cloudflare/kumo/components/layer-card';
import { Popover } from '@cloudflare/kumo/components/popover';
import { cn } from '@cloudflare/kumo/utils';
import { ArrowSquareOutIcon, GearSixIcon, LockSimpleIcon, SignOutIcon, WarningCircleIcon } from '@phosphor-icons/react';
import { language, t } from '../i18n';
import type { AdminSession } from '../lib/api';

export type Area = 'compat' | 'updates';

/** Primary switch between the two halves of the admin. Hidden until a session exists. */
export function AreaNav({ area, pending, onChange }: { area: Area; pending: number | null; onChange: (area: Area) => void }) {
  const item = (value: Area, label: string, count?: number | null) => (
    <button
      type="button"
      onClick={() => onChange(value)}
      aria-current={area === value ? 'page' : undefined}
      className={cn(
        'flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-[13px] whitespace-nowrap transition-colors',
        area === value ? 'bg-kumo-tint font-medium text-kumo-default' : 'text-kumo-subtle hover:bg-kumo-tint hover:text-kumo-default',
      )}
    >
      {t(label)}
      {!!count && <span className="rounded-full bg-kumo-brand px-1.5 text-[11px] leading-[18px] font-semibold text-white tabular">{count}</span>}
    </button>
  );
  return (
    <div className="flex items-center gap-1 border-l border-kumo-hairline pl-4">
      {item('compat', '兼容性报告', pending)}
      {item('updates', '更新统计')}
    </div>
  );
}

const dateTime = (iso: string) => new Date(iso).toLocaleString(language, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });

/** Who is signed in, until when, and how they sign out. */
export function AccountMenu({ session }: { session: AdminSession | null }) {
  const local = session?.kind === 'localDevelopment';
  const label = session ? (local ? 'local-development' : session.email ?? session.actor) : t('未登录');
  const initial = session ? label.charAt(0).toUpperCase() : '?';
  return (
    <Popover>
      <Popover.Trigger
        render={(
          <button
            type="button"
            className="ml-2 flex max-w-56 items-center gap-2 rounded-full border border-kumo-hairline py-0.5 pr-3 pl-0.5 text-[13px] text-kumo-default hover:bg-kumo-tint"
          />
        )}
      >
        <span
          className={cn(
            'grid size-6 shrink-0 place-items-center rounded-full text-[11px] font-semibold',
            local ? 'bg-kumo-warning-tint text-kumo-warning' : session ? 'bg-kumo-brand text-white' : 'bg-kumo-fill text-kumo-subtle',
          )}
        >
          {initial}
        </span>
        <span className="hidden truncate sm:inline">{label}</span>
      </Popover.Trigger>
      <Popover.Content side="bottom" align="end" className="w-72 p-0">
        <div className="flex flex-col gap-1 p-4">
          <span className="text-xs text-kumo-subtle">
            {t(local ? '本地开发，未经过 Access' : session ? '已通过 Cloudflare Access 登录' : '没有有效的 Access 会话')}
          </span>
          <b className="truncate text-sm font-semibold">{label}</b>
          {session && !local && (
            <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-xs">
              <dt className="text-kumo-subtle">{t('会话到期')}</dt>
              <dd className="tabular">{session.expiresAt ? dateTime(session.expiresAt) : '—'}</dd>
              <dt className="text-kumo-subtle">{t('审核记录署名')}</dt>
              <dd className="truncate">{session.actor}</dd>
            </dl>
          )}
        </div>
        {session && !local && (
          <a
            href="/cdn-cgi/access/logout"
            className="flex items-center justify-between border-t border-kumo-hairline px-4 py-2.5 text-[13px] text-kumo-danger no-underline hover:bg-kumo-tint"
          >
            {t('退出登录')}
            <SignOutIcon size={14} />
          </a>
        )}
      </Popover.Content>
    </Popover>
  );
}

export function LocalDevelopmentBanner() {
  return (
    <Banner
      className="mb-5"
      variant="alert"
      icon={<WarningCircleIcon weight="fill" />}
      title={t('本地开发模式')}
      description={t('未经过 Cloudflare Access，所有操作署名为 local-development。只在 localhost 且 ENVIRONMENT=development 时生效。')}
    />
  );
}

function Gate({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <LayerCard className="mx-auto mt-10 max-w-lg">
      <LayerCard.Primary className="flex flex-col items-center gap-3 px-8 py-10 text-center">
        <span className="grid size-11 place-items-center rounded-xl bg-kumo-tint text-kumo-subtle">{icon}</span>
        <h2 className="text-lg font-semibold">{t(title)}</h2>
        {children}
      </LayerCard.Primary>
    </LayerCard>
  );
}

/** The Access session ran out while the page was open. A reload goes back through Access. */
export function ExpiredGate() {
  return (
    <Gate icon={<LockSimpleIcon size={22} />} title="登录已过期">
      <p className="max-w-sm text-sm leading-relaxed text-kumo-subtle">
        {t('Cloudflare Access 会话已到期，后台数据不再显示。重新登录后会回到当前页面。')}
      </p>
      <Button variant="primary" className="mt-2" onClick={() => location.reload()}>{t('重新登录')}</Button>
    </Gate>
  );
}

/** Production without Access settings: every admin endpoint refuses, with no fallback key. */
export function UnconfiguredGate() {
  return (
    <>
      <Banner
        variant="error"
        icon={<WarningCircleIcon weight="fill" />}
        title={t('后台尚未配置 Cloudflare Access')}
        description={t('所有管理接口都返回 403。不会退回到密钥登录。')}
      />
      <Gate icon={<GearSixIcon size={22} />} title="需要维护者完成配置">
        <ol className="list-decimal pl-5 text-left text-sm leading-relaxed text-kumo-subtle">
          <li>{t('在 Zero Trust 新建自托管应用，路径为 /admin* 和 /api/admin/*')}</li>
          <li>{t('策略只允许维护者邮箱')}</li>
          <li>{t('在 Worker 设置 ACCESS_TEAM_DOMAIN 和 ACCESS_AUD 后重新部署')}</li>
        </ol>
        <a
          href="https://github.com/helson-lin/FanBar/blob/main/services/compatibility/README.md#%E7%AE%A1%E7%90%86%E5%91%98%E8%AE%BF%E9%97%AE"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-2 inline-flex items-center gap-1.5 text-sm text-kumo-link"
        >
          {t('查看部署说明')} <ArrowSquareOutIcon size={14} />
        </a>
      </Gate>
    </>
  );
}
