import { github, releases } from "./links";
import { siteName, siteUrl } from "./seo";

export const compatibilityUrl = `${siteUrl}/compatibility`;
export const compatibilityMarkdownUrl = `${siteUrl}/compatibility.md`;
export const compatibilityZhUrl = `${siteUrl}/zh/compatibility`;
export const compatibilityZhMarkdownUrl = `${siteUrl}/zh/compatibility.md`;
export const compatibilityUpdated = "2026-10-11";

export type EvidenceStatus = "Community report" | "Retest needed";

export interface CompatibilityReport {
  device: string;
  chip: string;
  macOS: string;
  version: string;
  evidence: string;
  limits: string;
  status: EvidenceStatus;
  date: string;
  source: string;
}

export const compatibilityReports: CompatibilityReport[] = [
  {
    device: "Mac mini",
    chip: "M6",
    macOS: "macOS 27",
    version: "Not recorded",
    evidence: "The reporter observed fan speed rising after switching from Automatic to Performance, Extreme, and Fixed modes.",
    limits: "The report discusses a timed return to Automatic; it is not a full sensor-by-sensor test.",
    status: "Community report",
    date: "October 2, 2026",
    source: "https://github.com/helson-lin/FanBar/issues/43",
  },
  {
    device: "MacBook Pro 16-inch",
    chip: "M2 Max",
    macOS: "macOS 27",
    version: "0.5.0",
    evidence: "The issue confirms the app launches and runs long enough for CPU and memory use to be observed.",
    limits: "Manual RPM and temperature-curve control were not recorded; the performance report remains open.",
    status: "Community report",
    date: "October 9, 2026",
    source: "https://github.com/helson-lin/FanBar/issues/63",
  },
  {
    device: "Apple Silicon Mac (Mac15,8)",
    chip: "Exact chip not recorded",
    macOS: "macOS 26.5",
    version: "0.4.3",
    evidence: "The report exercised the privileged helper and manual-control restore path.",
    limits: "This older version reported a shutdown restore crash. The issue is closed, but the current release still needs a standardized retest on this model.",
    status: "Retest needed",
    date: "August 20, 2026",
    source: "https://github.com/helson-lin/FanBar/issues/6",
  },
  {
    device: "Mac mini (2014)",
    chip: "Intel",
    macOS: "Not recorded",
    version: "Not recorded",
    evidence: "The report confirms the app and its background/menu-bar integration were running on the device.",
    limits: "Temperature reading, fan RPM, fixed control, and curve control were not recorded.",
    status: "Community report",
    date: "October 7, 2026",
    source: "https://github.com/helson-lin/FanBar/issues/50",
  },
];

export const compatibilityReportsZh: CompatibilityReport[] = [
  {
    device: "Mac mini",
    chip: "M6",
    macOS: "macOS 27",
    version: "未记录",
    evidence: "报告者观察到从「自动」切换到「性能」「极速」和「固定转速」后，风扇转速会上升。",
    limits: "报告讨论了定时恢复自动控制，但没有完成逐项传感器测试。",
    status: "Community report",
    date: "2026 年 10 月 2 日",
    source: "https://github.com/helson-lin/FanBar/issues/43",
  },
  {
    device: "16 英寸 MacBook Pro",
    chip: "M2 Max",
    macOS: "macOS 27",
    version: "0.5.0",
    evidence: "该 Issue 证明应用可以启动并持续运行，足以观察 CPU 与内存占用。",
    limits: "没有记录固定转速或温控曲线测试；性能问题目前仍处于开放状态。",
    status: "Community report",
    date: "2026 年 10 月 9 日",
    source: "https://github.com/helson-lin/FanBar/issues/63",
  },
  {
    device: "Apple Silicon Mac（Mac15,8）",
    chip: "Issue 未记录具体芯片",
    macOS: "macOS 26.5",
    version: "0.4.3",
    evidence: "报告涉及特权 Helper 与手动控制恢复路径。",
    limits: "旧版本曾报告关机恢复崩溃。Issue 已关闭，但当前版本仍需在该机型上按标准流程复测。",
    status: "Retest needed",
    date: "2026 年 8 月 20 日",
    source: "https://github.com/helson-lin/FanBar/issues/6",
  },
  {
    device: "Mac mini（2014）",
    chip: "Intel",
    macOS: "未记录",
    version: "未记录",
    evidence: "报告证明应用及其后台/菜单栏集成曾在该设备上运行。",
    limits: "没有记录温度读取、风扇 RPM、固定转速或曲线控制结果。",
    status: "Community report",
    date: "2026 年 10 月 7 日",
    source: "https://github.com/helson-lin/FanBar/issues/50",
  },
];

export const verificationChecklist = [
  "App launches and remains stable",
  "CPU and GPU temperatures are readable",
  "SSD and battery temperatures are readable when the hardware exposes them",
  "Current, minimum, and maximum RPM are shown for every fan",
  "Fixed RPM changes fan output and stays inside the reported hardware range",
  "A temperature-based curve changes fan output as expected",
  "Automatic control is restored on quit, disconnect, timeout, and helper failure",
  "Sleep, wake, restart, and login-item behavior are stable",
];

export const compatibilityFaq = [
  {
    question: "Does FanBar work on Apple Silicon?",
    answer:
      "Yes, on Apple Silicon Macs that expose readable fan data through AppleSMC. Hardware sensors and fan behavior vary by model, so check the evidence table for the exact Mac you use. A model not listed is unverified, not necessarily unsupported.",
  },
  {
    question: "Is FanBar free and open source?",
    answer:
      "Yes. FanBar is free under GPL-3.0, requires no account or subscription, and publishes the complete source code, including its privileged helper.",
  },
  {
    question: "Why does fan control need administrator permission?",
    answer:
      "Reading temperatures does not need manual fan control. Changing fan targets talks to AppleSMC through a signed privileged helper, so macOS asks for approval before that helper can run with the required access.",
  },
  {
    question: "What happens when FanBar quits?",
    answer:
      "FanBar attempts to restore macOS automatic fan control when the app quits, its helper connection is lost, a timed preset ends, or the helper reports a failure. Requested targets are also clamped to each fan's reported hardware range.",
  },
];

export const compatibilityFaqZh = [
  {
    question: "FanBar 支持 Apple Silicon 吗？",
    answer:
      "支持能通过 AppleSMC 提供可读风扇数据的 Apple Silicon Mac。不同机型的传感器与风扇行为可能不同，请在证据表中查找你的具体机型。未列出表示尚未验证，不等于不支持。",
  },
  {
    question: "FanBar 免费且开源吗？",
    answer:
      "是。FanBar 采用 GPL-3.0 许可，免费使用，无需账号或订阅，并公开包含特权 Helper 在内的完整源码。",
  },
  {
    question: "为什么控制风扇需要管理员权限？",
    answer:
      "读取温度不需要启用手动控制。修改风扇目标值需要通过签名的特权 Helper 访问 AppleSMC，因此 macOS 会先要求你明确授权。",
  },
  {
    question: "FanBar 退出时会发生什么？",
    answer:
      "当应用退出、Helper 连接中断、定时预设结束或 Helper 报告失败时，FanBar 会尝试恢复 macOS 自动风扇控制。目标转速也始终限制在硬件报告的范围内。",
  },
];

export function compatibilityStructuredData() {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebPage",
        "@id": `${compatibilityUrl}/#page`,
        url: compatibilityUrl,
        name: "FanBar Mac Compatibility and Test Evidence",
        description:
          "A source-linked compatibility evidence table for FanBar, separating maintainer verification from community reports and unverified hardware.",
        inLanguage: "en",
        dateModified: compatibilityUpdated,
        isPartOf: { "@id": `${siteUrl}/#website` },
        about: { "@id": `${siteUrl}/#app` },
        mainEntity: { "@id": `${compatibilityUrl}/#faq` },
      },
      {
        "@type": "FAQPage",
        "@id": `${compatibilityUrl}/#faq`,
        mainEntity: compatibilityFaq.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
      {
        "@type": "SoftwareApplication",
        "@id": `${siteUrl}/#app`,
        name: siteName,
        operatingSystem: "macOS 11 or later",
        applicationCategory: "UtilitiesApplication",
        url: siteUrl,
        downloadUrl: releases,
        codeRepository: github,
        license: "https://www.gnu.org/licenses/gpl-3.0.html",
        isAccessibleForFree: true,
      },
    ],
  };
}

export function compatibilityZhStructuredData() {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebPage",
        "@id": `${compatibilityZhUrl}/#page`,
        url: compatibilityZhUrl,
        name: "FanBar Mac 兼容性与测试证据",
        description: "FanBar 的来源可追溯兼容性证据表，明确区分维护者实测、社区报告与尚未验证的硬件。",
        inLanguage: "zh-Hans",
        dateModified: compatibilityUpdated,
        isPartOf: { "@id": `${siteUrl}/#website` },
        about: { "@id": `${siteUrl}/#app` },
        mainEntity: { "@id": `${compatibilityZhUrl}/#faq` },
      },
      {
        "@type": "FAQPage",
        "@id": `${compatibilityZhUrl}/#faq`,
        inLanguage: "zh-Hans",
        mainEntity: compatibilityFaqZh.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
      {
        "@type": "SoftwareApplication",
        "@id": `${siteUrl}/#app`,
        name: siteName,
        operatingSystem: "macOS 11 or later",
        applicationCategory: "UtilitiesApplication",
        url: siteUrl,
        downloadUrl: releases,
        codeRepository: github,
        license: "https://www.gnu.org/licenses/gpl-3.0.html",
        isAccessibleForFree: true,
      },
    ],
  };
}
