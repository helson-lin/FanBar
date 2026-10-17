import type { HighlightKey, ScreenshotKey } from "./links";

export type Locale = "en" | "zh";

export const locales: Locale[] = ["en", "zh"];
export const defaultLocale: Locale = "en";

export interface Dictionary {
  meta: {
    title: string;
    description: string;
    ogDescription: string;
    keywords: string[];
  };
  nav: {
    highlights: string;
    screenshots: string;
    howItWorks: string;
    faq: string;
    compare: string;
    compatibility: string;
    download: string;
    languageSwitch: string;
  };
  hero: {
    badge: string;
    titleLead: string;
    titleHighlight: string;
    subtitle: string;
    primaryCta: string;
    secondaryCta: string;
    compatibilityCta: string;
    caption: string;
  };
  stats: { value: string; label: string }[];
  highlights: {
    badge: string;
    heading: string;
    items: Record<HighlightKey, { title: string; description: string }>;
  };
  trust: {
    badge: string;
    heading: string;
    body: string;
    points: string[];
  };
  screenshots: {
    badge: string;
    heading: string;
    items: Record<
      ScreenshotKey,
      { alt: string; title: string; description: string }
    >;
  };
  howItWorks: {
    badge: string;
    heading: string;
    steps: { step: string; title: string; description: string }[];
  };
  faq: {
    badge: string;
    heading: string;
    body: string;
    items: { question: string; answer: string }[];
  };
  finalCta: {
    badge: string;
    heading: string;
    body: string;
    primaryCta: string;
    secondaryCta: string;
    caption: string;
  };
  footer: {
    copyright: string;
    github: string;
    releases: string;
    languageSwitch: string;
  };
}

const en: Dictionary = {
  meta: {
    title: "FanBar — Free, Open-Source Mac Fan Control",
    description:
      "FanBar is a free, open-source Mac fan control app for the menu bar. Monitor temperatures and fan speeds, set a fixed RPM, or create temperature-based fan curves.",
    ogDescription:
      "Free, open-source Mac fan control from the menu bar, with live temperatures, fixed RPM, and editable temperature-based fan curves.",
    keywords: [
      "FanBar",
      "macOS fan control",
      "Mac fan speed app",
      "menu bar temperature monitor",
      "AppleSMC fan control",
      "open source macOS utility",
      "Mac cooling software",
      "FanBar Mac mini M6 support",
      "Mac mini M6 fan control",
      "Mac mini M6 temperature monitor",
      "FanBar macOS 27 support",
      "macOS 27 fan speed control",
      "macOS 27 menu bar temperature monitor",
    ],
  },
  nav: {
    highlights: "Highlights",
    screenshots: "Screenshots",
    howItWorks: "How it works",
    faq: "FAQ",
    compare: "Compare",
    compatibility: "Compatibility",
    download: "Download",
    languageSwitch: "简体中文",
  },
  hero: {
    badge: "Free · Open source · Native macOS",
    titleLead: "Free, open-source",
    titleHighlight: "Mac fan control.",
    subtitle:
      "FanBar is a free, open-source Mac fan control app for the menu bar. Monitor temperatures and fan speeds, set a fixed RPM, or create temperature-based fan curves. It supports macOS 11 and later on compatible Apple Silicon and Intel Macs.",
    primaryCta: "Download for macOS",
    secondaryCta: "View on GitHub",
    compatibilityCta: "View compatibility evidence",
    caption: "MACOS 11+ · APPLE SILICON & INTEL · DMG & HOMEBREW",
  },
  stats: [
    { value: "11+", label: "macOS Big Sur and later" },
    { value: "6", label: "Cooling modes, Automatic to Extreme" },
    { value: "10 min", label: "Rolling temperature history" },
    { value: "4", label: "Languages — EN, 简中, 繁中 & 日本語" },
  ],
  highlights: {
    badge: "Highlights",
    heading:
      "Everything you need to understand and tame your Mac's fans.",
    items: {
      status: {
        title: "At-a-glance status",
        description:
          "Show the menu-bar icon, CPU temperature, average fan RPM, or both.",
      },
      widget: {
        title: "Desktop widget",
        description:
          "On macOS 14+, pin FanBar to the desktop for RPM, speed, and control mode.",
      },
      live: {
        title: "Live visualization",
        description:
          "A rolling ten-minute chart, plus airflow that follows real RPM.",
      },
      modes: {
        title: "Multiple cooling modes",
        description:
          "Automatic, a fixed target RPM, or a Silent, Balanced, Performance, or Extreme preset.",
      },
      curves: {
        title: "Smart temperature curves",
        description:
          "Each preset has its own editable curve, mapping temperature to fan output.",
      },
      source: {
        title: "Selectable temperature source",
        description:
          "Drive the curve from CPU, GPU, or SSD; unavailable sensors fall back safely.",
      },
      alerts: {
        title: "High-temperature alerts",
        description:
          "Optional notifications at 90°C — one alert per episode, re-armed after cooling.",
      },
      safe: {
        title: "Safe by default",
        description:
          "Targets stay clamped to hardware range; failure restores automatic control.",
      },
      language: {
        title: "Four interface languages",
        description:
          "Use English, 简体中文, 繁體中文, or 日本語 — and switch instantly.",
      },
    },
  },
  trust: {
    badge: "Built for trust",
    heading: "Manual control only after you approve it.",
    body: "FanBar keeps everyday use safe and quiet under macOS's own automatic management. Manual fan control opens only after a signed, privileged helper is explicitly authorized — first-run guidance explains exactly why it's needed.",
    points: [
      "FanBar.app → privileged XPC → signed helper (root) → AppleSMC",
      "The helper only reads fans and sets a bounded target — never arbitrary SMC writes",
      "Presets can auto-restore Automatic after 15 min, 30 min, or an hour",
      "Every release ships notarized by Apple; the source, helper included, is public",
    ],
  },
  screenshots: {
    badge: "Interface",
    heading: "A calm, native interface — not a dashboard.",
    items: {
      popover: {
        alt: "FanBar menu-bar popover",
        title: "Menu-bar popover",
        description: "Live temperature, RPM, and mode switching.",
      },
      cooling: {
        alt: "FanBar cooling settings",
        title: "Cooling curves",
        description: "Each preset's temperature → RPM curve, yours to edit.",
      },
      menubar: {
        alt: "FanBar menu bar display settings",
        title: "Menu bar display",
        description:
          "Preview what the status item shows before you commit.",
      },
    },
  },
  howItWorks: {
    badge: "How it works",
    heading: "From install to manual control in three steps.",
    steps: [
      {
        step: "01",
        title: "Launch & read",
        description:
          "Open FanBar and see current temperature and fan speed right in the menu bar.",
      },
      {
        step: "02",
        title: "Enable fan control",
        description:
          "Choose Enable fan control and follow the macOS authorization prompt.",
      },
      {
        step: "03",
        title: "Choose a preset",
        description:
          "Pick a preset or fixed RPM — or return to Automatic any time.",
      },
    ],
  },
  faq: {
    badge: "FAQ",
    heading: "Answers, in plain language.",
    body: "Platform support, permissions, licensing, and what manual fan control actually does — short answers, no marketing.",
    items: [
      {
        question: "What is FanBar?",
        answer:
          "FanBar is a free, open-source macOS menu-bar app that shows live CPU, GPU, SSD, and battery temperatures and lets you set fan speed manually. It runs on macOS 11 Big Sur and later, on Apple Silicon and Intel Macs that expose fan data through AppleSMC. Everyday cooling stays under macOS's automatic control; manual modes are optional and reversible.",
      },
      {
        question: "Is FanBar free, and do I need an account?",
        answer:
          "Yes — FanBar is free and open source under the GPL-3.0 license, with no account, subscription, or ads. Notarized builds are published on GitHub Releases, and the full source, privileged helper included, is public.",
      },
      {
        question: "Which Macs and macOS versions are supported?",
        answer:
          "macOS 11 Big Sur or later, on Apple Silicon and Intel Macs that expose readable AppleSMC fan data. The desktop widget requires macOS 14 or later. The control service registers through SMAppService on macOS 13 and later, and through launchd on macOS 11–12.",
      },
      {
        question: "Does FanBar need root access or install a privileged helper?",
        answer:
          "Only for manual fan control, and only after you approve it. FanBar.app talks to a signed FanBarHelper over privileged XPC: the helper runs as root but exposes no arbitrary SMC writes — it reads fan state, sets a bounded target, and restores automatic control. If you never enable fan control, the helper stays idle.",
      },
      {
        question: "Which temperatures and fan speeds can FanBar read?",
        answer:
          "CPU and GPU temperature on every supported Mac, plus SSD and battery temperatures where those sensors exist. It reads each fan's current RPM and hardware minimum and maximum, and the menu bar can show the icon, CPU temperature, average RPM, or a combination. Optional notifications fire when CPU or GPU reaches 90°C.",
      },
      {
        question: "What cooling modes does FanBar offer?",
        answer:
          "Six: Automatic (macOS control), a fixed target RPM, and the Silent, Balanced, Performance, and Extreme preset curves. Each preset has its own editable temperature-to-RPM curve and can be pinned to the menu-bar panel; presets can auto-restore Automatic after 15 minutes, 30 minutes, or one hour.",
      },
      {
        question: "What happens if manual fan control fails or the app quits?",
        answer:
          "Targets are clamped to each fan's reported hardware range, and FanBar restores macOS automatic control when a preset expires, the app quits or loses its connection, or the control service fails. Manual settings never keep running silently in the background.",
      },
      {
        question: "Which languages does FanBar support?",
        answer:
          "English, Simplified Chinese, Traditional Chinese, and Japanese. Choose System or a specific language in Settings → Language, and the menu-bar popover, settings, onboarding, and status messages switch instantly without a restart.",
      },
    ],
  },
  finalCta: {
    badge: "Download",
    heading: "Give your fans a calmer job.",
    body: "Notarized builds for Apple Silicon, Intel, and Universal Macs. Free, open source, and honest about the trade-offs of manual control.",
    primaryCta: "Download the .dmg",
    secondaryCta: "View on GitHub",
    caption: "MACOS 11+ · APPLE SILICON & INTEL · GPL-3.0 LICENSE",
  },
  footer: {
    copyright: "FanBar · GPL-3.0 License",
    github: "GitHub",
    releases: "Releases",
    languageSwitch: "简体中文",
  },
};

const zh: Dictionary = {
  meta: {
    title: "FanBar — 让 Mac 保持凉爽，噪音却降到最低",
    description:
      "FanBar 在菜单栏实时读取 CPU、GPU、SSD 和电池温度，只有在 macOS 的自动曲线不够用时，才需要你手动介入风扇控制。",
    ogDescription: "原生 macOS 菜单栏工具：查看温度，并在需要时管理风扇散热。",
    keywords: [
      "FanBar",
      "Mac 风扇控制",
      "Mac 温度监控",
      "菜单栏温度工具",
      "AppleSMC",
      "macOS 散热",
      "开源 Mac 软件",
      "FanBar Mac mini M6 支持",
      "Mac mini M6 风扇控制",
      "Mac mini M6 温度监控",
      "FanBar macOS 27 支持",
      "macOS 27 风扇转速控制",
      "macOS 27 菜单栏温度监控",
    ],
  },
  nav: {
    highlights: "亮点",
    screenshots: "截图",
    howItWorks: "使用方式",
    faq: "常见问题",
    compare: "产品对比",
    compatibility: "兼容性",
    download: "下载",
    languageSwitch: "English",
  },
  hero: {
    badge: "原生 macOS 菜单栏",
    titleLead: "让 Mac 保持凉爽，",
    titleHighlight: "噪音却降到最低。",
    subtitle:
      "FanBar 在菜单栏实时读取 CPU、GPU、SSD 和电池温度——只有当 macOS 的自动曲线不够用时，才需要你手动介入风扇控制。",
    primaryCta: "下载 macOS 版",
    secondaryCta: "查看 GitHub 源码",
    compatibilityCta: "查看兼容性证据",
    caption: "免费开源 · MACOS 11 及以上 · APPLE SILICON 与 INTEL",
  },
  stats: [
    { value: "11+", label: "macOS Big Sur 及以上版本" },
    { value: "6", label: "散热模式，从自动到极速" },
    { value: "10 min", label: "十分钟温度趋势记录" },
    { value: "4", label: "支持英文、简中、繁中与日文" },
  ],
  highlights: {
    badge: "亮点",
    heading: "理解并驾驭 Mac 风扇，所需的一切都在这里。",
    items: {
      status: {
        title: "一眼掌握状态",
        description: "菜单栏可显示图标、CPU 温度、平均风扇 RPM，或三者组合。",
      },
      widget: {
        title: "桌面组件",
        description:
          "macOS 14 及以上，可将 FanBar 添加到桌面，查看 RPM、转速与控制模式。",
      },
      live: {
        title: "实时可视化",
        description: "近十分钟趋势曲线，气流动画随真实 RPM 变化。",
      },
      modes: {
        title: "多种散热模式",
        description: "自动、固定目标转速，或静音、均衡、性能、极速预设。",
      },
      curves: {
        title: "智能温控曲线",
        description: "每个预设都有独立可编辑曲线，将温度映射为转速。",
      },
      source: {
        title: "温度来源可选",
        description:
          "可选择 CPU、GPU 或 SSD 驱动曲线；传感器不可用时安全回退。",
      },
      alerts: {
        title: "高温通知",
        description:
          "达到 90°C 时可选通知提醒——每次持续高温只提醒一次，降温后重新启用。",
      },
      safe: {
        title: "默认安全",
        description: "转速始终限制在硬件范围内；发生异常时自动恢复系统控制。",
      },
      language: {
        title: "四种界面语言",
        description: "支持英文、简体中文、繁體中文与日本語——即时切换。",
      },
    },
  },
  trust: {
    badge: "值得信赖",
    heading: "只有你批准后，才会开放手动控制。",
    body: "FanBar 日常保持在 macOS 自身的自动管理之下，安全又安静。只有在你明确授权签名的特权服务后，才会开放手动风扇控制——首次使用时会说明原因。",
    points: [
      "FanBar.app → 特权 XPC → 签名 Helper（root）→ AppleSMC",
      "Helper 只能读取风扇数据、设置有限范围内的目标值——从不提供任意 SMC 写入",
      "预设可在 15 分钟、30 分钟或 1 小时后自动恢复「自动」模式",
      "每个版本都经过 Apple 公证；完整源码（含 Helper）公开在 GitHub",
    ],
  },
  screenshots: {
    badge: "界面",
    heading: "克制、原生的界面——不是仪表盘。",
    items: {
      popover: {
        alt: "FanBar 菜单栏面板",
        title: "菜单栏面板",
        description: "实时温度、转速与模式切换。",
      },
      cooling: {
        alt: "FanBar 散热设置",
        title: "温控曲线",
        description: "每个预设的温度 → 转速曲线，可自由编辑。",
      },
      menubar: {
        alt: "FanBar 菜单栏显示设置",
        title: "菜单栏显示",
        description: "提交前预览状态栏的显示效果。",
      },
    },
  },
  howItWorks: {
    badge: "使用方式",
    heading: "从安装到手动控制，只需三步。",
    steps: [
      {
        step: "01",
        title: "启动并查看",
        description: "打开 FanBar，菜单栏即可看到当前温度与转速。",
      },
      {
        step: "02",
        title: "启用风扇控制",
        description: "选择「启用风扇控制」，并完成 macOS 授权提示。",
      },
      {
        step: "03",
        title: "选择预设",
        description: "选一个预设或固定转速——随时可切回「自动」。",
      },
    ],
  },
  faq: {
    badge: "常见问题",
    heading: "用直白的话回答常见问题。",
    body: "支持范围、权限、许可，以及手动风扇控制到底做了什么——简短、具体，不绕弯子。",
    items: [
      {
        question: "FanBar 是什么？",
        answer:
          "FanBar 是一款免费开源的 macOS 菜单栏应用，可实时显示 CPU、GPU、SSD 与电池温度，并在需要时手动设置风扇转速。它支持 macOS 11 Big Sur 及以上、能通过 AppleSMC 读取风扇数据的 Apple Silicon 与 Intel Mac。日常散热仍由 macOS 自动管理，手动模式随时可以退回。",
      },
      {
        question: "FanBar 免费吗？需要注册账号吗？",
        answer:
          "免费且开源，采用 GPL-3.0 许可，无需账号、订阅，也没有广告。已公证的安装包发布在 GitHub Releases，完整源码（包含特权 Helper）公开可查。",
      },
      {
        question: "支持哪些 Mac 和 macOS 版本？",
        answer:
          "macOS 11 Big Sur 及以上，Apple Silicon 与 Intel Mac 均可，前提是硬件能通过 AppleSMC 提供可读的风扇数据。桌面组件需要 macOS 14 及以上；控制服务在 macOS 13 及以上通过 SMAppService 注册，macOS 11–12 则使用 launchd。",
      },
      {
        question: "FanBar 需要 root 权限或安装特权服务吗？",
        answer:
          "只有在手动控制风扇时才需要，而且必须由你授权。FanBar.app 通过特权 XPC 与签名过的 FanBarHelper 通信：Helper 以 root 运行，但不提供任意 SMC 写入——只能读取风扇状态、设置有限范围内的目标值，以及恢复自动控制。如果你不启用风扇控制，Helper 始终处于闲置状态。",
      },
      {
        question: "FanBar 能读取哪些温度和转速？",
        answer:
          "所有受支持的 Mac 都能读取 CPU 与 GPU 温度；当硬件提供对应传感器时，还会读取 SSD 与电池温度。它会读取每个风扇的当前转速以及硬件上下限，菜单栏可显示图标、CPU 温度、平均转速或它们的组合。CPU 或 GPU 达到 90°C 时可选发送通知。",
      },
      {
        question: "FanBar 提供哪些散热模式？",
        answer:
          "共六种：自动（交还 macOS 控制）、固定目标转速，以及静音、均衡、性能、极速四个预设曲线。每个预设都有独立可编辑的温度 → 转速曲线，并可固定到菜单栏面板；预设可在 15 分钟、30 分钟或 1 小时后自动恢复「自动」。",
      },
      {
        question: "手动控制失效或应用退出时会怎样？",
        answer:
          "目标转速始终被限制在每个风扇的硬件范围内；当预设到期、应用退出或连接中断、控制服务失败时，FanBar 会恢复 macOS 自动控制——手动设置不会在后台悄悄持续生效。",
      },
      {
        question: "FanBar 支持哪些语言？",
        answer:
          "英文、简体中文、繁体中文与日文。在「设置 → 语言」中选择跟随系统或指定语言，菜单栏面板、设置窗口、引导流程与状态提示都会即时切换，无需重启。",
      },
    ],
  },
  finalCta: {
    badge: "下载",
    heading: "让风扇的工作，从容一点。",
    body: "已公证的 Apple Silicon、Intel 与通用版安装包。免费开源，也坦诚说明手动控制的取舍。",
    primaryCta: "下载 .dmg",
    secondaryCta: "查看 GitHub",
    caption: "MACOS 11 及以上 · APPLE SILICON 与 INTEL · GPL-3.0 许可",
  },
  footer: {
    copyright: "FanBar · GPL-3.0 许可",
    github: "GitHub",
    releases: "发行版",
    languageSwitch: "English",
  },
};

export const dictionaries: Record<Locale, Dictionary> = { en, zh };

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? dictionaries[defaultLocale];
}
