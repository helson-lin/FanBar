// Copy for /stats and /zh/stats. Kept out of i18n.ts: the page exists only in English and Simplified Chinese.

import type { Locale } from "./i18n";
import { siteUrl } from "./seo";

export const statsApiUrl = "https://update.getfanbar.com/api/stats";
export const privacyUrl = "https://github.com/helson-lin/FanBar/blob/main/services/update/PRIVACY.md";
export const statsUrl = `${siteUrl}/stats`;
export const statsZhUrl = `${siteUrl}/zh/stats`;

export function statsPath(locale: Locale): string {
  return locale === "zh" ? "/zh/stats" : "/stats";
}

export interface StatsCopy {
  title: string;
  description: string;
  crumb: string;
  label: string;
  h1: string;
  h1Accent: string;
  intro: string;
  loading: string;
  unavailableTitle: string;
  unavailable: string;
  noData: string;
  checks: { label: string; title: string; lede: string; legend: string; other: string; total: string; days: string; table: string; checks: string; date: string; version: string; none: string };
  retention: { label: string; title: string; lede: string; cohort: string; users: string; weeksAfter: string; legacyTitle: string; legacy: (n: string, week: string) => string; empty: string; caption: string; cell: (cohort: string, k: number, pct: string) => string };
  dist: { label: string; title: string; lede: (week: string) => string; empty: string; model: string; os: string; arch: string; country: string; reports: string; share: string; other: string; total: (n: string) => string };
  method: { label: string; title: string; items: string[]; privacy: string; turnOff: string };
  footer: string;
}

export const statsCopy: Record<"en" | "zh", StatsCopy> = {
  en: {
    title: "FanBar Usage Statistics",
    description: "Anonymous, aggregated FanBar update-check counts and opt-in usage statistics, with the method and limits explained.",
    crumb: "Usage stats",
    label: "Usage statistics",
    h1: "What FanBar's update checks",
    h1Accent: "can and cannot tell us.",
    intro: "Aggregated, anonymous counts from FanBar's own update service. Groups smaller than 5 are never shown. These numbers describe update checks and opted-in users, not everyone who has installed FanBar.",
    loading: "Loading statistics…",
    unavailableTitle: "Statistics are not available yet",
    unavailable: "The statistics service has not published any data yet, or it could not be reached. Nothing is wrong with FanBar. Please check back later.",
    noData: "Not enough data to show yet.",
    checks: {
      label: "Update checks", title: "Update checks per day",
      lede: "Each bar is the number of update checks received that day, split by app version. One person can send several checks a day, so this is not a count of users or devices.",
      legend: "App version", other: "Other versions", total: "update checks in the last 180 days", days: "days", table: "View data as a table", checks: "Checks", date: "Date", version: "Version", none: "No data",
    },
    retention: {
      label: "Retention", title: "Weekly retention by install week",
      lede: "Of the opted-in users who reported in their install week, the share who reported again N weeks later. Only users who turned on usage statistics are included, and they tend to be more active than average, so this is not retention for all users.",
      cohort: "Install week", users: "Users", weeksAfter: "Weeks after install",
      legacyTitle: "Opted-in users who installed before statistics existed",
      legacy: (n, week) => `${n} reports in ${week}. They have no install week, so they are not part of the table.`,
      empty: "No install-week group is large enough to show yet.",
      caption: "Retention by install week and weeks since install, as percentages",
      cell: (cohort, k, pct) => `Install week ${cohort}, ${k} weeks after install: ${pct}`,
    },
    dist: {
      label: "Distribution", title: "Who opted in, latest complete week",
      lede: (week) => `Opted-in users in ${week}, the most recent finished week. Shares are of opted-in reports that week.`,
      empty: "No finished week with enough data yet.",
      model: "Mac model", os: "macOS version", arch: "Chip architecture", country: "Country or region", reports: "Reports", share: "Share", other: "Other", total: (n) => `${n} reports`,
    },
    method: {
      label: "Method", title: "How these numbers are made",
      items: [
        "By default FanBar counts one update check, with the app version only. Nothing else is attached.",
        "Everything else (retention, Mac model, macOS version, chip and country) comes only from users who opted in, reported once per week. Retention therefore reflects opted-in users, who tend to be more active, and is not all users.",
        "Groups with fewer than 5 are hidden.",
        "No IP address, device ID or serial number is stored.",
        "Data comes from FanBar's own Cloudflare Worker. There is no third-party analytics.",
      ],
      privacy: "What is collected",
      turnOff: "Turning off automatic update checks stops all counting.",
    },
    footer: "Usage stats",
  },
  zh: {
    title: "FanBar 使用统计",
    description: "FanBar 匿名、汇总的更新检查次数与自愿开启的使用统计，并说明统计方法与局限。",
    crumb: "使用统计",
    label: "使用统计",
    h1: "FanBar 的更新检查数据，",
    h1Accent: "能说明什么、不能说明什么。",
    intro: "数据来自 FanBar 自己的更新服务，均为汇总后的匿名计数。少于 5 的分组一律不显示。这些数字反映的是更新检查次数和开启统计的用户，不代表所有安装过 FanBar 的人。",
    loading: "正在加载统计数据…",
    unavailableTitle: "暂时还没有统计数据",
    unavailable: "统计服务尚未发布数据，或暂时无法访问。这不影响 FanBar 的使用，请稍后再来看看。",
    noData: "数据还不够，暂时无法显示。",
    checks: {
      label: "更新检查", title: "每日更新检查次数",
      lede: "每根柱子是当天收到的更新检查次数，按应用版本分色。同一个人一天可能检查多次，所以这不是用户数或设备数。",
      legend: "应用版本", other: "其他版本", total: "次更新检查（最近 180 天）", days: "天", table: "以表格查看数据", checks: "检查次数", date: "日期", version: "版本", none: "无数据",
    },
    retention: {
      label: "留存", title: "按安装周统计的每周留存",
      lede: "在安装当周上报过的、开启统计的用户中，N 周后再次上报的比例。只包含开启了使用统计的用户，他们通常比普通用户更活跃，所以这不是全部用户的留存。",
      cohort: "安装周", users: "用户数", weeksAfter: "安装后第几周",
      legacyTitle: "统计功能上线前就已安装的开启统计用户",
      legacy: (n, week) => `${week} 有 ${n} 条上报。他们没有安装周，因此不在表中。`,
      empty: "暂时没有足够大的安装周分组可以显示。",
      caption: "按安装周与安装后周数统计的留存百分比",
      cell: (cohort, k, pct) => `安装周 ${cohort}，安装后第 ${k} 周：${pct}`,
    },
    dist: {
      label: "分布", title: "开启统计的用户，最近完整一周",
      lede: (week) => `${week}（最近一个已结束的周）开启统计的用户。占比为该周上报总数中的比例。`,
      empty: "暂时没有数据足够的已结束周。",
      model: "Mac 型号", os: "macOS 版本", arch: "芯片架构", country: "国家或地区", reports: "上报数", share: "占比", other: "其他", total: (n) => `共 ${n} 条上报`,
    },
    method: {
      label: "方法", title: "这些数字是怎么来的",
      items: [
        "默认情况下，FanBar 只按一次更新检查计数，只带应用版本，不附带其他信息。",
        "其他数据（留存、Mac 型号、macOS 版本、芯片和国家）只来自主动开启统计的用户，每周上报一次。因此留存反映的是开启统计的用户，他们通常更活跃，并不代表全部用户。",
        "少于 5 的分组不显示。",
        "不存储 IP 地址、设备 ID 或序列号。",
        "数据来自 FanBar 自己的 Cloudflare Worker，没有使用第三方统计服务。",
      ],
      privacy: "收集了哪些信息",
      turnOff: "关闭自动检查更新后，将不再有任何计数。",
    },
    footer: "使用统计",
  },
};
