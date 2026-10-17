import { github, releases } from "./links";
import { siteUrl } from "./seo";

export const comparisonUrl = `${siteUrl}/compare/macs-fan-control`;
export const comparisonMarkdownUrl = `${siteUrl}/compare/macs-fan-control.md`;
export const comparisonZhUrl = `${siteUrl}/zh/compare/macs-fan-control`;
export const comparisonZhMarkdownUrl = `${siteUrl}/zh/compare/macs-fan-control.md`;
export const comparisonUpdated = "2026-10-11";

export const competitorSources = {
  overview: "https://www.crystalidea.com/macs-fan-control",
  download: "https://www.crystalidea.com/macs-fan-control/download",
  support: "https://www.crystalidea.com/macs-fan-control/support",
  releaseNotes: "https://www.crystalidea.com/macs-fan-control/release-notes",
  sensors: "https://www.crystalidea.com/macs-fan-control/temperature-sensors",
  buy: "https://www.crystalidea.com/macs-fan-control/buy",
} as const;

export interface ComparisonRow {
  criterion: string;
  fanbar: string;
  competitor: string;
  source: string;
  sourceLabel: string;
}

export const comparisonRows: ComparisonRow[] = [
  {
    criterion: "Price",
    fanbar: "Free; every feature is included under GPL-3.0.",
    competitor:
      "Free core app. Pro is a one-time paid upgrade for saved custom presets and priority support; Windows is a 14-day trial.",
    source: competitorSources.download,
    sourceLabel: "Download and licensing",
  },
  {
    criterion: "Source code",
    fanbar: "Public, including the privileged helper.",
    competitor: "Distributed as a compiled application; its official site does not publish an application source repository.",
    source: competitorSources.overview,
    sourceLabel: "Official product page",
  },
  {
    criterion: "Interface",
    fanbar: "Menu-bar popover built with native SwiftUI; no separate main window.",
    competitor: "Configurable menu-bar display plus a separate main window for its detailed fan and sensor tables.",
    source: competitorSources.overview,
    sourceLabel: "Feature overview",
  },
  {
    criterion: "Platforms",
    fanbar: "macOS 11+ on Apple Silicon and Intel Macs with readable AppleSMC fan data.",
    competitor:
      "Current macOS build supports macOS 10.13+; Windows is available for Intel Macs running Boot Camp.",
    source: competitorSources.download,
    sourceLabel: "Platform downloads",
  },
  {
    criterion: "Fan control",
    fanbar:
      "Automatic, fixed RPM, and four editable temperature-to-RPM presets: Silent, Balanced, Performance, and Extreme.",
    competitor:
      "Auto, constant RPM, or sensor-based control. Saving multiple named custom presets is a Pro feature.",
    source: competitorSources.overview,
    sourceLabel: "Fan control and presets",
  },
  {
    criterion: "Sensor detail",
    fanbar: "CPU, GPU, SSD, and battery temperatures, plus per-fan RPM and hardware limits.",
    competitor:
      "A broader per-sensor list, including supported third-party HDD/SSD temperatures through S.M.A.R.T.",
    source: competitorSources.sensors,
    sourceLabel: "Temperature sensors",
  },
  {
    criterion: "Safety fallback",
    fanbar:
      "Clamps targets to hardware-reported limits and attempts to restore automatic control on quit, disconnect, or service failure.",
    competitor: "Its official feature page says all fans are restored to Auto when the app quits.",
    source: competitorSources.overview,
    sourceLabel: "Automatic restore behavior",
  },
  {
    criterion: "Desktop widget",
    fanbar: "Yes, through WidgetKit on macOS 14+.",
    competitor: "No WidgetKit desktop widget is listed in the current feature set.",
    source: competitorSources.overview,
    sourceLabel: "Current feature set",
  },
  {
    criterion: "Languages",
    fanbar: "English, Simplified Chinese, Traditional Chinese, and Japanese.",
    competitor: "Translated into most major languages.",
    source: competitorSources.overview,
    sourceLabel: "Language coverage",
  },
  {
    criterion: "Install",
    fanbar: "Notarized DMGs through GitHub Releases, or a signed universal app through the official Homebrew tap.",
    competitor: "macOS DMG and Windows installer from CrystalIDEA.",
    source: competitorSources.download,
    sourceLabel: "Official downloads",
  },
  {
    criterion: "Track record",
    fanbar: "A newer open-source project launched in 2026.",
    competitor: "Public release history dates back to 2013, with more than a decade of hardware coverage.",
    source: competitorSources.releaseNotes,
    sourceLabel: "Release history",
  },
];

export const comparisonRowsZh: ComparisonRow[] = [
  {
    criterion: "价格",
    fanbar: "免费；GPL-3.0 许可下包含全部功能。",
    competitor: "核心应用免费。Pro 是一次性付费升级，提供保存自定义预设与优先支持；Windows 版提供 14 天试用。",
    source: competitorSources.download,
    sourceLabel: "下载与许可说明",
  },
  {
    criterion: "源代码",
    fanbar: "完整公开，包含特权 Helper。",
    competitor: "以编译后的应用分发；其官网没有公布应用源代码仓库。",
    source: competitorSources.overview,
    sourceLabel: "官方产品页",
  },
  {
    criterion: "界面",
    fanbar: "原生 SwiftUI 菜单栏面板，不需要单独管理主窗口。",
    competitor: "提供可配置的菜单栏显示，并通过独立主窗口展示详细风扇与传感器表格。",
    source: competitorSources.overview,
    sourceLabel: "功能概览",
  },
  {
    criterion: "平台",
    fanbar: "macOS 11 及以上，支持能读取 AppleSMC 风扇数据的 Apple Silicon 与 Intel Mac。",
    competitor: "当前 macOS 版支持 macOS 10.13 及以上；Windows 版适用于通过 Boot Camp 运行 Windows 的 Intel Mac。",
    source: competitorSources.download,
    sourceLabel: "平台下载",
  },
  {
    criterion: "风扇控制",
    fanbar: "自动、固定 RPM，以及静音、均衡、性能、极速四种可编辑温度 → 转速预设。",
    competitor: "自动、恒定 RPM 或基于传感器控制；保存多个命名自定义预设属于 Pro 功能。",
    source: competitorSources.overview,
    sourceLabel: "风扇控制与预设",
  },
  {
    criterion: "传感器细节",
    fanbar: "CPU、GPU、SSD 与电池温度，以及每个风扇的 RPM 和硬件范围。",
    competitor: "提供更广的逐传感器列表，并可通过 S.M.A.R.T. 读取受支持的第三方 HDD/SSD 温度。",
    source: competitorSources.sensors,
    sourceLabel: "温度传感器",
  },
  {
    criterion: "安全回退",
    fanbar: "将目标限制在硬件报告范围内，并在退出、断连或服务失败时尝试恢复自动控制。",
    competitor: "其官方功能页说明，应用退出时会把所有风扇恢复为自动控制。",
    source: competitorSources.overview,
    sourceLabel: "自动恢复行为",
  },
  {
    criterion: "桌面小组件",
    fanbar: "支持，macOS 14 及以上通过 WidgetKit 提供。",
    competitor: "当前官方功能列表没有列出 WidgetKit 桌面小组件。",
    source: competitorSources.overview,
    sourceLabel: "当前功能列表",
  },
  {
    criterion: "语言",
    fanbar: "英文、简体中文、繁体中文与日文。",
    competitor: "已翻译为多数主要语言。",
    source: competitorSources.overview,
    sourceLabel: "语言覆盖",
  },
  {
    criterion: "安装",
    fanbar: "通过 GitHub Releases 下载已公证 DMG，或通过官方 Homebrew tap 安装签名通用版。",
    competitor: "从 CrystalIDEA 下载 macOS DMG 或 Windows 安装程序。",
    source: competitorSources.download,
    sourceLabel: "官方下载",
  },
  {
    criterion: "项目历史",
    fanbar: "2026 年发布的较新开源项目。",
    competitor: "公开发布记录可追溯到 2013 年，覆盖十年以上的 Mac 硬件。",
    source: competitorSources.releaseNotes,
    sourceLabel: "发布历史",
  },
];

export const comparisonFaq = [
  {
    question: "What is the best free Mac fan control app?",
    answer:
      "Macs Fan Control and FanBar are both capable free options. Macs Fan Control has the longer track record and broader sensor detail. FanBar is fully free and open source, keeps its complete interface in the menu bar, and has no paid tier.",
  },
  {
    question: "Is it safe to control Mac fans manually?",
    answer:
      "Manual fan control is not risk-free. Use hardware-bounded settings, avoid forcing minimum RPM under sustained load, and prefer Automatic or temperature-based curves for daily use. Both apps return fans to automatic control when they quit; FanBar also attempts restoration after connection or helper failures.",
  },
  {
    question: "Can FanBar replace Macs Fan Control?",
    answer:
      "For users who need temperature monitoring, fixed RPM, editable curves, presets, and automatic fallback on macOS, FanBar covers the core workflow. Macs Fan Control remains the stronger fit when you need a broader per-sensor list or Windows support through Boot Camp.",
  },
  {
    question: "Why is FanBar free?",
    answer:
      "FanBar is an independent open-source project licensed under GPL-3.0. There is no paid tier, account, subscription, advertising, or feature-limited download.",
  },
];

export const comparisonFaqZh = [
  {
    question: "哪款免费 Mac 风扇控制应用更合适？",
    answer:
      "Macs Fan Control 与 FanBar 都提供有能力的免费版本。Macs Fan Control 历史更长、传感器细节更丰富；FanBar 完全免费开源，界面集中在菜单栏，也没有付费层级。",
  },
  {
    question: "手动控制 Mac 风扇安全吗？",
    answer:
      "手动控制并非完全没有风险。应使用受硬件范围限制的设置，避免在持续高负载下强制最低转速，并优先使用自动或温控曲线。两款应用退出时都会恢复自动控制；FanBar 还会在连接或 Helper 失败时尝试恢复。",
  },
  {
    question: "FanBar 可以替代 Macs Fan Control 吗？",
    answer:
      "如果你需要 macOS 上的温度监控、固定 RPM、可编辑曲线、预设与自动回退，FanBar 可以覆盖核心流程。如果你需要更广的逐传感器列表或 Boot Camp Windows 支持，Macs Fan Control 更合适。",
  },
  {
    question: "为什么 FanBar 免费？",
    answer:
      "FanBar 是采用 GPL-3.0 许可的独立开源项目，没有付费层级、账号、订阅、广告或功能受限的下载版本。",
  },
];

export function comparisonStructuredData() {
  const publisherId = `${siteUrl}/#publisher`;
  const articleId = `${comparisonUrl}#article`;

  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": publisherId,
        name: "FanBar",
        url: siteUrl,
        logo: {
          "@type": "ImageObject",
          url: `${siteUrl}/icon-512.png`,
          width: 512,
          height: 512,
        },
        sameAs: [github],
      },
      {
        "@type": "Article",
        "@id": articleId,
        headline: "FanBar vs Macs Fan Control: Which Mac Fan Control App Should You Choose?",
        description:
          "An evidence-backed comparison of FanBar and Macs Fan Control covering price, source code, sensors, fan modes, platforms, safety, and interface design.",
        datePublished: comparisonUpdated,
        dateModified: comparisonUpdated,
        inLanguage: "en",
        mainEntityOfPage: { "@id": `${comparisonUrl}#webpage` },
        author: { "@id": publisherId },
        publisher: { "@id": publisherId },
        citation: [...Object.values(competitorSources), github, releases],
      },
      {
        "@type": "WebPage",
        "@id": `${comparisonUrl}#webpage`,
        url: comparisonUrl,
        name: "FanBar vs Macs Fan Control",
        inLanguage: "en",
        isPartOf: { "@id": `${siteUrl}/#website` },
        mainEntity: { "@id": articleId },
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "FanBar", item: siteUrl },
          { "@type": "ListItem", position: 2, name: "FanBar vs Macs Fan Control", item: comparisonUrl },
        ],
      },
      {
        "@type": "FAQPage",
        "@id": `${comparisonUrl}#faq`,
        mainEntity: comparisonFaq.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
    ],
  };
}

export function comparisonZhStructuredData() {
  const publisherId = `${siteUrl}/#publisher`;
  const articleId = `${comparisonZhUrl}#article`;

  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Article",
        "@id": articleId,
        headline: "FanBar 与 Macs Fan Control 对比：应该选择哪一款？",
        description: "基于来源对比 FanBar 与 Macs Fan Control 的价格、源代码、传感器、控制模式、平台、安全与界面。",
        datePublished: comparisonUpdated,
        dateModified: comparisonUpdated,
        inLanguage: "zh-Hans",
        mainEntityOfPage: { "@id": `${comparisonZhUrl}#webpage` },
        author: { "@id": publisherId },
        publisher: { "@id": publisherId },
        citation: [...Object.values(competitorSources), github, releases],
      },
      {
        "@type": "WebPage",
        "@id": `${comparisonZhUrl}#webpage`,
        url: comparisonZhUrl,
        name: "FanBar 与 Macs Fan Control 对比",
        inLanguage: "zh-Hans",
        isPartOf: { "@id": `${siteUrl}/#website` },
        mainEntity: { "@id": articleId },
      },
      {
        "@type": "FAQPage",
        "@id": `${comparisonZhUrl}#faq`,
        inLanguage: "zh-Hans",
        mainEntity: comparisonFaqZh.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
    ],
  };
}
