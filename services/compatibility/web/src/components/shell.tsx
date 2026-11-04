import type { ReactNode } from 'react';
import { Select } from '@cloudflare/kumo/components/select';
import { cn } from '@cloudflare/kumo/utils';
import mark from '../fanbar-mark.png';
import { language, languageNames, localized, switchLanguage, t, type Language } from '../i18n';

export type NavLink = { href: string; label: string; external?: boolean };

/**
 * `nav` sits beside the brand (the admin's area switch); `account` closes the bar.
 * Public pages pass neither.
 */
export function SiteHeader({ subtitle, links, nav, account }: {
  subtitle: string; links: NavLink[]; nav?: ReactNode; account?: ReactNode;
}) {
  return (
    <header className="border-b border-kumo-hairline bg-kumo-base">
      <div className="mx-auto flex h-14 max-w-6xl items-center gap-4 px-6">
        <a href={localized('/')} className="flex items-center gap-2.5 text-[15px] font-semibold tracking-tight text-kumo-default no-underline">
          <img src={mark} alt="" className="size-6 rounded-md" />
          FanBar
          <span className="hidden font-normal text-kumo-subtle sm:inline">
            <span className="mr-2 text-kumo-inactive">/</span>
            {t(subtitle)}
          </span>
        </a>
        {nav}
        <nav className="ml-auto flex items-center gap-1 text-[13px]">
          {links.map(link => (
            <a
              key={link.href}
              href={link.external ? link.href : localized(link.href)}
              {...(link.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
              className={cn(
                'hidden rounded-md px-2.5 py-1.5 whitespace-nowrap text-kumo-subtle no-underline transition-colors hover:bg-kumo-tint hover:text-kumo-default',
                // With the admin's area switch beside the brand there is less room for secondary links.
                nav ? 'xl:inline' : 'md:inline',
              )}
            >
              {t(link.label)}
            </a>
          ))}
          <Select
            aria-label={({ en: 'Language', ja: '言語', 'zh-CN': '语言' } as const)[language]}
            size="sm"
            className="ml-2 w-28"
            value={language}
            onValueChange={value => value && value !== language && switchLanguage(value as Language)}
            items={languageNames}
          />
          {account}
        </nav>
      </div>
    </header>
  );
}

export function Page({ children, width = 'wide' }: { children: ReactNode; width?: 'wide' | 'prose' }) {
  return <main className={cn('mx-auto px-6 py-8', width === 'wide' ? 'max-w-6xl' : 'max-w-2xl')}>{children}</main>;
}

export function PageTitle({ title, lede, aside }: { title: string; lede?: string; aside?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="max-w-2xl">
        <h1 className="text-2xl font-semibold tracking-tight text-kumo-default">{t(title)}</h1>
        {lede && <p className="mt-1.5 text-sm leading-relaxed text-kumo-subtle">{t(lede)}</p>}
      </div>
      {aside}
    </div>
  );
}

/** Translated text with a single inline link, for paragraphs authored as text–link–text. */
export function TextLink({ href, label }: { href: string; label: string }) {
  const external = /^https?:/.test(href);
  return (
    <a
      href={external ? href : localized(href)}
      {...(external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
      className="text-kumo-link underline decoration-kumo-link/30 underline-offset-2 hover:decoration-kumo-link"
    >
      {t(label)}
    </a>
  );
}
