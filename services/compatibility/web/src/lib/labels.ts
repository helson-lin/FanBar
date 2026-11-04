import modelNames from './mac-model-names.json';
import { t } from '../i18n';
import { ApiError, type Capability, type CommunityStatus, type VerificationStatus } from './api';

export const capabilityOrder: Capability[] = [
  'cpuTemperature', 'gpuTemperature', 'ssdTemperature', 'batteryTemperature', 'fanReadings', 'manualControl', 'smartCooling',
];
export const capabilityTitle = (capability: Capability): string => t(({
  cpuTemperature: 'CPU 温度', gpuTemperature: 'GPU 温度', ssdTemperature: 'SSD 温度', batteryTemperature: '电池温度',
  fanReadings: '风扇转速', manualControl: '手动调速', smartCooling: '智能温控',
} as const)[capability]);

export const statusTitle = (status: CommunityStatus | VerificationStatus): string => t(({
  notApplicable: '正常（无内置电池）', available: '已读取', notDetected: '未检测到', temporarilyUnavailable: '暂时不可用', requiresAuthorization: '需要授权',
  unverified: '尚未验证', requestSucceeded: '请求成功', requestFailed: '请求失败',
  verifiedAvailable: '实测可用', verifiedUnsupported: '实测不支持',
} as const)[status]);

/**
 * Visual tone of a result. The shape and colour of the status icon follow it; the label stays neutral.
 * - ok: read or verified to work
 * - pending: a control request was accepted but actual effect is unconfirmed
 * - mixed: approved reports disagree
 * - absent: not read, unavailable or failed in reports (never proof of unsupported)
 * - unknown: no evidence yet
 * - unsupported: independently verified not to work
 */
export type Tone = 'ok' | 'pending' | 'mixed' | 'absent' | 'unknown' | 'unsupported';

export const toneOf = (status: CommunityStatus | VerificationStatus): Tone => ({
  notApplicable: 'ok', available: 'ok', verifiedAvailable: 'ok', requestSucceeded: 'pending', unverified: 'unknown',
  notDetected: 'absent', temporarilyUnavailable: 'absent', requiresAuthorization: 'absent', requestFailed: 'absent',
  verifiedUnsupported: 'unsupported',
} as const)[status];

export function errorMessage(error: unknown): string {
  const code = error instanceof ApiError ? error.code : '';
  const messages: Record<string, string> = {
    ADMIN_AUTHENTICATION_REQUIRED: 'Cloudflare Access 会话已到期，请重新登录。',
    ADMIN_ACCESS_NOT_CONFIGURED: '管理员访问尚未配置，服务已拒绝访问。',
    UPDATE_SERVICE_UNAVAILABLE: '更新服务暂时无法读取，兼容性后台不受影响。请稍后刷新。',
    INVALID_RANGE: '时间范围只能是 7、30 或 90 天。',
    RATE_LIMITED: '请求过于频繁，请稍后重试。',
    REPORT_NOT_FOUND: '报告不存在、已过期、尚未公开，或撤回凭证不正确。',
    INVALID_REPORT: '报告不符合字段或能力证据规则。',
    SERVICE_NOT_CONFIGURED: '服务尚未完成配置。',
    SAME_ORIGIN_REQUIRED: '管理操作必须从当前服务页面发起。',
    INVALID_VERIFICATION: '实测记录不完整，或验证日期晚于今天。',
  };
  return t(messages[code] ?? '请求失败，请稍后重试。');
}

export const modelTitle = (identifier: string): string => (modelNames as Record<string, string>)[identifier] ?? identifier;
