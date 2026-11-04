import type { ReactNode } from 'react';
import { Page, SiteHeader, TextLink } from '../components/shell';
import { t } from '../i18n';
import { mount } from '../lib/mount';

const source = 'https://github.com/helson-lin/FanBar/tree/codex/device-compatibility/services/compatibility';

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-9">
      <h2 className="mb-3 text-base font-semibold text-kumo-default">{t(title)}</h2>
      <div className="flex flex-col gap-3">{children}</div>
    </section>
  );
}

const P = ({ children }: { children: ReactNode }) => <p className="text-[15px] leading-7 text-kumo-default">{children}</p>;

function PrivacyPage() {
  return (
    <>
      <SiteHeader
        subtitle="公开的收集与处理规则"
        links={[{ href: '/report-schema.json', label: '完整字段' }, { href: '/withdraw.html', label: '撤回报告' }]}
      />
      <Page width="prose">
        <p className="mb-2 font-mono text-xs tracking-wide text-kumo-subtle">POLICY / 2026-10-21</p>
        <h1 className="text-2xl font-semibold tracking-tight text-kumo-default">{t('你能检查我们收集的每个字段。')}</h1>
        <div className="mt-4">
          <P>{t('本机检测不需要上报。只有你预览并确认提交时，报告才会发送到当前 FanBar 报告服务。服务由 FanBar 项目维护者运营，使用 Cloudflare Workers 与 D1。')}</P>
        </div>

        <Section title="上传哪些内容">
          <ul className="flex list-disc flex-col gap-1.5 pl-5 text-[15px] leading-7 text-kumo-default">
            <li>{t('机型标识、处理器名称、macOS／FanBar／控制服务版本。')}</li>
            <li>{t('硬件接口报告的风扇数量（如可获取）、所选温度来源。')}</li>
            <li>{t('七项能力状态与标准原因码、每次报告随机生成的编号。')}</li>
            <li>{t('可选的手动调速、智能温控本机实测确认，由用户主动勾选；不替代自动检测或开发者验证。')}</li>
            <li>{t('控制请求失败时附带固定失败码和有限的数值证据：SMC 键名、返回码、风扇序号、耗时、回读是否为手动模式、是否已恢复系统控制。不上传错误描述文本。')}</li>
            <li>{t('你是否同意公开单份报告、确认的规则版本。服务器记录接收时间、到期时间和审核状态。')}</li>
          </ul>
          <P>
            {t('兼容性报告不接收序列号、硬件 UUID、用户名、主机名、文件路径、进程列表、温度历史或诊断日志。')}
            <TextLink href="/report-schema.json" label="查看严格字段 Schema" />
            {t('；额外字段、不完整能力列表和不一致的证据会被拒绝。')}
          </P>
        </Section>

        <Section title="诊断日志">
          <P>{t('运行诊断还包含最近 24 小时内有界保留的启动、授权、连接与控制事件，最近 10 分钟可读取的 Helper 事件，以及最近 7 天内最多 3 份崩溃摘要。只提取异常类型、终止代码和固定模块名与偏移，不上传完整崩溃文件、路径、原始错误描述或系统日志。')}</P>
          <P>{t('诊断还包含最近一分钟内最多 30 次采样、温度键的数据类型与最多 8 字节原始值、有限的温度键枚举及其截断状态、SSD 和电池备用来源的读取结果。日志上限为 256 KiB。')}</P>
          <P>{t('诊断日志需单独预览并确认上传，包含设备版本、本次温度读数、传感器键、探测结果、错误码和控制服务状态。不收集系统日志、序列号、用户名、文件路径或进程列表。')}</P>
          <P>{t('日志仅管理员可见，不公开、不参与兼容性统计。在线保留 90 天，可在客户端诊断上传记录中撤回；历史恢复点最长还可能保留 30 天。每份诊断单独生成随机编号和撤回凭证，数据库仅保存凭证哈希。')}</P>
        </Section>

        <Section title="哪些数据公开">
          <P>{t('报告默认私有，仅管理员可以查看。经审核的报告会贡献公开的机型与版本汇总，统计为报告数，不代表独立设备数。只有你明确选择公开的单份报告，在审核通过后才可以通过报告编号查阅。罕见机型与版本组合也可能具有辨识度，请在提交前评估。')}</P>
        </Section>

        <Section title="如何判断兼容性">
          <P>{t('没有读数或一次失败不等于不支持。控制服务就绪、请求成功和实际转速验证分别处理。社区报告不会自动成为“开发者验证”；开发者实测必须单独发布，附带日期、版本与公开依据。不同结果会保留，不用多数票掩盖差异。')}</P>
        </Section>

        <Section title="网络元数据与安全">
          <P>{t('Cloudflare 为传输和保护服务会处理网络地址等元数据。应用数据库不保存原始 IP；服务只将带密钥且每日变化的网络地址摘要送入短期限流计数器，不用于设备追踪。服务日志不记录报告内容、撤回凭证、请求 URL 或网络地址。Cloudflare 自身的基础设施处理不等于不存在。')}</P>
          <P>{t('管理员接口只能通过 Cloudflare Access 进入，服务端会验证 Access 身份；没有管理密钥。撤回凭证每份报告独立生成，通过请求头发送；数据库只存其 SHA-256 哈希。凭证不进入公开数据或网址。所有生产请求使用 HTTPS。')}</P>
        </Section>

        <Section title="保存多久，如何删除">
          <P>
            {t('报告在线保留 90 天，到期即停止公开查询与统计，物理数据由每日清理任务删除。你可以在 FanBar 的上报记录中撤回，也可以使用报告编号和撤回凭证在')}
            <TextLink href="/withdraw.html" label="撤回页面" />
            {t('删除。撤回会删除在线报告及相关审核记录，并移除社区统计贡献；独立实测记录不会随用户报告撤回而删除。为防止迟到的请求重新写入同一报告，报告编号与凭证的哈希删除标记会私有保留 90 天，不保留报告内容。')}
          </P>
          <P>{t('在线删除不代表云平台历史恢复点立即清除。D1 历史恢复点按账户计划保留 7 天（免费）或 30 天（付费），因此历史数据最长还可能保留 30 天；不得把旧备份恢复后直接公开上线。公开数据下载或第三方副本无法由本服务追回。')}</P>
          <P>{t('浏览器只保存你选择的界面语言；不保存报告、访问密钥或撤回凭证。')}</P>
        </Section>

        <Section title="源码与变更">
          <P>
            {t('规则版本为 2026-10-21，新增控制失败证据。FanBar 0.7.0 及更早版本仍按 2026-10-13 规则提交，不包含这些字段。规则变化后，旧确认不能直接用于新提交。')}
            <TextLink href={source} label="服务端源码" />
            {t('与')}
            <TextLink href="/api/policy?version=2026-10-21" label="机器可读处理规则" />
            {t('公开；问题可在')}
            <TextLink href="https://github.com/helson-lin/FanBar/issues" label="FanBar 仓库" />
            {t('反馈，请勿在公开反馈中填写撤回凭证。')}
          </P>
        </Section>
      </Page>
    </>
  );
}

mount('收集与处理规则 · FanBar', <PrivacyPage />);
