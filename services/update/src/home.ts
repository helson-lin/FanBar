/**
 * What a person sees opening https://update.getfanbar.com in a browser.
 * Static, no script and no tracking: the CSP allows inline styles only, so the
 * mark and the flow diagram are inline SVG and fonts are the system's.
 * English by default; `?lang=zh` shows the Chinese page.
 */

type Lang = 'en' | 'zh';

interface Copy {
  htmlLang: string;
  title: string;
  introHtml: string;
  flowTitle: string;
  countedNote: string;
  linksTitle: string;
  linksNote: string;
  flowLabel: string;
  flow: [string, string][];
  countedHeading: string;
  always: string;
  alwaysItems: string[];
  optIn: string;
  optInItems: string[];
  never: string;
  neverItems: string[];
  groups: string;
  endpointsHeading: string;
  endpointsNote: string;
  endpoints: [string, string, string][];
  statsLink: string;
  sourceLink: string;
  siteLink: string;
  switchLang: string;
  switchHref: string;
  footer: string;
}

const COPY: Record<Lang, Copy> = {
  en: {
    htmlLang: 'en',
    title: 'FanBar update service',
    flowLabel: 'How an update check travels',
    introHtml:
      '<p>This address is FanBar’s <b>update feed</b>. When FanBar checks for updates it asks here, and is sent straight on to the <b>appcast on GitHub</b>.</p><p>On the way, the check is <b>counted anonymously</b>, so the project knows which versions are in use. Nothing that identifies you is kept.</p>',
    flowTitle: 'How it works',
    countedNote: 'Kept per field, never combined.',
    linksTitle: 'Elsewhere',
    linksNote: 'The numbers, the code and the app.',
    flow: [
      ['FanBar', 'asks for /appcast.xml'],
      ['update.getfanbar.com', 'counts it, then redirects'],
      ['GitHub', 'serves the appcast'],
    ],
    countedHeading: 'What is counted',
    always: 'Always',
    alwaysItems: ['App version, per day'],
    optIn: 'Only if you opt in',
    optInItems: ['Mac model', 'macOS version', 'Chip', 'Country'],
    never: 'Never stored',
    neverItems: ['IP address', 'Device ID', 'Raw request'],
    groups: 'Groups smaller than 5 are never published.',
    endpointsHeading: 'Endpoints',
    endpointsNote: 'Three addresses. Everything else returns 404.',
    endpoints: [
      ['GET', '/appcast.xml', 'Redirects to the appcast on GitHub'],
      ['GET', '/api/stats', 'Aggregate counts as JSON'],
      ['GET', '/', 'This page'],
    ],
    statsLink: 'Aggregate statistics',
    sourceLink: 'Source code',
    siteLink: 'getfanbar.com',
    switchLang: '中文',
    switchHref: '/?lang=zh',
    footer: 'FanBar is free and open source.',
  },
  zh: {
    htmlLang: 'zh-Hans',
    title: 'FanBar 更新服务',
    flowLabel: '一次检查更新的路径',
    introHtml:
      '<p>这是 FanBar 的<b>更新源</b>。FanBar 检查更新时先请求这里，再直接跳转到 <b>GitHub 上的 appcast</b>。</p><p>经过这里时会做一次<b>匿名计数</b>，让项目知道有哪些版本在使用。不会保存任何能识别你的信息。</p>',
    flowTitle: '工作方式',
    countedNote: '每项单独计数，彼此不交叉。',
    linksTitle: '在别处',
    linksNote: '数据、源码和应用本身。',
    flow: [
      ['FanBar', '请求 /appcast.xml'],
      ['update.getfanbar.com', '计数后跳转'],
      ['GitHub', '返回 appcast'],
    ],
    countedHeading: '统计哪些内容',
    always: '始终统计',
    alwaysItems: ['应用版本（按天）'],
    optIn: '仅在开启统计后',
    optInItems: ['Mac 型号', 'macOS 版本', '芯片', '国家或地区'],
    never: '从不保存',
    neverItems: ['IP 地址', '设备 ID', '原始请求'],
    groups: '少于 5 的分组不会公开。',
    endpointsHeading: '接口',
    endpointsNote: '只有三个地址，其他路径都返回 404。',
    endpoints: [
      ['GET', '/appcast.xml', '跳转到 GitHub 上的 appcast'],
      ['GET', '/api/stats', 'JSON 格式的汇总统计'],
      ['GET', '/', '本页'],
    ],
    statsLink: '汇总统计',
    sourceLink: '源码',
    siteLink: 'getfanbar.com',
    switchLang: 'English',
    switchHref: '/?lang=en',
    footer: 'FanBar 免费开源。',
  },
};


const svg = (paths: string) =>
  `<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
const ICON = {
  chart: svg('<path d="M2.5 13.5h11M4.5 11V8M8 11V4.5M11.5 11V6.5"/>'),
  code: svg('<path d="m5.5 4.5-3.5 3.5 3.5 3.5M10.5 4.5 14 8l-3.5 3.5"/>'),
  globe: svg('<circle cx="8" cy="8" r="5.75"/><path d="M2.25 8h11.5M8 2.25c1.6 1.6 2.4 3.5 2.4 5.75S9.6 12.15 8 13.75C6.4 12.15 5.6 10.25 5.6 8S6.4 3.85 8 2.25z"/>'),
  lang: svg('<path d="M2.5 4h6M5.5 2.5V4M7.5 4c-.5 2.5-2.3 4.6-4.5 5.6M4.2 6.3c.8 1.4 2 2.5 3.3 3.1M8.5 13.5l2.5-6 2.5 6M9.3 11.5h3.4"/>'),
  arrow: svg('<path d="M6 4l4 4-4 4"/>'),
};

const STYLE = `
:root{color-scheme:light dark;
  --page:#FAFAFA;--col:#FAFAFA;--fg:#18181B;--fg-2:#52525B;--fg-3:#8E8E95;--line:#E3E3E3;--hatch:rgba(0,0,0,.045);
  --btn:#FFFFFF;--btn-hover:#F4F4F5;--chip:#FFFFFF;--ok:#22A05A;
  --sans:"Inter",-apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB","Noto Sans SC",sans-serif;
  --mono:ui-monospace,"SF Mono",Menlo,monospace}
@media (prefers-color-scheme:dark){:root{
  --page:#0F0F10;--col:#0F0F10;--fg:#ECECEE;--fg-2:#B4B4BA;--fg-3:#7C7C84;--line:#2A2A2D;--hatch:rgba(255,255,255,.045);
  --btn:#18181B;--btn-hover:#222226;--chip:#18181B;--ok:#3FCB7E}}
*{box-sizing:border-box}
html{background:var(--page)}
body{margin:0;min-height:100vh;color:var(--fg);font:16px/1.75 var(--sans);-webkit-font-smoothing:antialiased;
  background:repeating-linear-gradient(135deg,var(--hatch) 0 1px,transparent 1px 8px)}
a{color:inherit;text-decoration:none}
:focus-visible{outline:2px solid #4D7CFF;outline-offset:2px;border-radius:9px}
.col{max-width:620px;min-height:100vh;margin:0 auto;background:var(--col);border-left:1px dashed var(--line);border-right:1px dashed var(--line)}
.part{padding:28px 24px;border-top:1px dashed var(--line)}
.part:first-child{border-top:0;padding-top:72px}
.intro p{margin:0 0 12px;color:var(--fg-2)}
.intro p:last-child{margin:0}
.intro b{color:var(--fg);font-weight:600}
h2{margin:0 0 14px;font-size:1rem;font-weight:400;color:var(--fg-3)}
h2 b{color:var(--fg);font-weight:600;margin-right:8px}
.flow{display:flex;flex-wrap:wrap;align-items:center;gap:8px;font-size:.875rem}
.flow .node{display:inline-flex;flex-direction:column;padding:8px 12px;border:1px solid var(--line);border-radius:9px;background:var(--btn);line-height:1.35;box-shadow:0 1px 0 rgba(0,0,0,.03)}
.flow .node b{font:500 .8125rem var(--mono)}
.flow .node span{font-size:.75rem;color:var(--fg-3)}
.flow svg{width:14px;height:14px;color:var(--fg-3)}
.list{margin:0;display:grid;gap:12px}
.list div{display:grid;grid-template-columns:7.5rem 1fr;gap:12px;align-items:start}
.list dt{font-size:.875rem;font-weight:600;line-height:30px}
.list dd{margin:0;display:flex;flex-wrap:wrap;gap:6px}
.chip{display:inline-flex;align-items:center;height:30px;padding:0 11px;border:1px solid var(--line);border-radius:9px;background:var(--chip);font-size:.8125rem;color:var(--fg-2)}
.never .chip{color:var(--fg-3);text-decoration:line-through;background:transparent;border-style:dashed}
.note{margin:14px 0 0;font-size:.8125rem;color:var(--fg-3)}
.eps{margin:0;padding:0;list-style:none;font-size:.875rem}
.eps li{display:flex;gap:12px;padding:6px 0;align-items:baseline}
.eps code{font:.8125rem var(--mono);color:var(--fg);min-width:8.5rem}
.eps span{color:var(--fg-2)}
.eps em{font:normal 600 .6875rem var(--mono);color:var(--fg-3);min-width:2rem}
.btns{display:flex;flex-wrap:wrap;gap:8px}
.btn{display:inline-flex;align-items:center;gap:8px;height:38px;padding:0 14px;border:1px solid var(--line);border-radius:9px;background:var(--btn);font-size:.875rem;box-shadow:0 1px 0 rgba(0,0,0,.03);transition:background .15s}
.btn:hover{background:var(--btn-hover)}
.btn svg{width:16px;height:16px;color:var(--fg-2)}
.foot{display:flex;justify-content:space-between;gap:12px;font-size:.8125rem;color:var(--fg-3);padding-bottom:48px}
.foot a:hover{color:var(--fg)}
@media (max-width:560px){
  .part{padding:24px 20px}.part:first-child{padding-top:48px}
  .list div{grid-template-columns:1fr;gap:4px}.list dt{line-height:1.5}
  .eps li{flex-wrap:wrap;gap:2px 12px}.eps span{flex-basis:100%;padding-left:calc(2rem + 12px)}
}`;

const esc = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function render(lang: Lang) {
  const c = COPY[lang];
  const chips = (items: string[]) => items.map((item) => `<span class="chip">${esc(item)}</span>`).join('');
  const flow = c.flow
    .map(([name, what]) => `<span class="node"><b>${esc(name)}</b><span>${esc(what)}</span></span>`)
    .join(ICON.arrow);
  const endpoints = c.endpoints
    .map(([method, path, what]) => `<li><em>${method}</em><code>${esc(path)}</code><span>${esc(what)}</span></li>`)
    .join('');
  return `<!doctype html>
<html lang="${c.htmlLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${esc(c.title)}</title>
<style>${STYLE}</style>
</head>
<body>
<main class="col">
  <div class="part intro">${c.introHtml}</div>
  <div class="part">
    <h2><b>${esc(c.flowTitle)}</b>${esc(c.flowLabel)}</h2>
    <div class="flow" role="group" aria-label="${esc(c.flowLabel)}">${flow}</div>
  </div>
  <div class="part">
    <h2><b>${esc(c.countedHeading)}</b>${esc(c.countedNote)}</h2>
    <dl class="list">
      <div><dt>${esc(c.always)}</dt><dd>${chips(c.alwaysItems)}</dd></div>
      <div><dt>${esc(c.optIn)}</dt><dd>${chips(c.optInItems)}</dd></div>
      <div class="never"><dt>${esc(c.never)}</dt><dd>${chips(c.neverItems)}</dd></div>
    </dl>
    <p class="note">${esc(c.groups)}</p>
  </div>
  <div class="part">
    <h2><b>${esc(c.endpointsHeading)}</b>${esc(c.endpointsNote)}</h2>
    <ul class="eps">${endpoints}</ul>
  </div>
  <div class="part">
    <h2><b>${esc(c.linksTitle)}</b>${esc(c.linksNote)}</h2>
    <div class="btns">
      <a class="btn" href="/api/stats">${ICON.chart}${esc(c.statsLink)}</a>
      <a class="btn" href="https://github.com/helson-lin/FanBar/tree/main/services/update">${ICON.code}${esc(c.sourceLink)}</a>
      <a class="btn" href="https://getfanbar.com">${ICON.globe}${esc(c.siteLink)}</a>
    </div>
  </div>
  <div class="part foot"><span>${esc(c.footer)}</span><a href="${c.switchHref}" hreflang="${lang === 'en' ? 'zh-Hans' : 'en'}">${esc(c.switchLang)}</a></div>
</main>
</body>
</html>
`;
}

const PAGES: Record<Lang, string> = { en: render('en'), zh: render('zh') };

/** English unless the visitor picked Chinese with `?lang=zh`. */
export function pageLanguage(request: Request): Lang {
  return new URL(request.url).searchParams.get('lang') === 'zh' ? 'zh' : 'en';
}

export function home(request: Request) {
  const lang = pageLanguage(request);
  return new Response(PAGES[lang], {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Language': COPY[lang].htmlLang,
      'Cache-Control': 'public, max-age=86400',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'",
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
