# FanBar 更新检查计数服务：规格

状态：已实现（`src/`，测试见 `test/update.test.ts`）。日期：2026-11-03。

## 1. 目标与边界

服务地址 `https://update.getfanbar.com`。它是 Sparkle 更新源的入口：**永远把请求 302 跳转到 GitHub 上的 appcast**，顺带统计匿名计数。

- 不保存原始请求、IP、User-Agent 原文或任何设备标识。
- D1 只存「按天或按周 × 单一维度」的计数，维度之间不交叉。
- 计数失败、限流、输入非法、数据库故障，都不能影响 302。

不在本规格内：Swift 客户端的实现（另写规格）、`getfanbar.com/stats` 页面、外部拨测服务的选型（见第 7 节）。

## 2. 接口

### `GET /appcast.xml`（以及 `HEAD`）

- 响应：始终是 `302`，`Location` 为 `APPCAST_URL` 的值，带 `Cache-Control: no-store`。不转发查询参数。
- 计数（异步执行，用 `ctx.waitUntil`）：
  - **默认计数**：从 User-Agent 解析出 `FanBar/<版本> Sparkle/<版本>`。版本号在已发布版本列表中时，`checks_daily(当天 UTC, 版本) += 1`。不在列表中的版本（包括格式错误的），一律计入 `other`。User-Agent 不是 `FanBar/… Sparkle/…` 这种形式时（拨测、爬虫、浏览器访问），不计数。
  - **开启统计后的计数**：请求带有 `fb_cohort` 时，才处理下面这些字段。字段之间互不影响，非法的字段单独丢弃：

| 参数 | 合法值 | 写入 |
|---|---|---|
| `fb_cohort` | `legacy`，或 UTC ISO 周 `YYYY-Www`，且在 `FIRST_COHORT_WEEK` 和当前周之间（含两端） | `cohort_weekly(本周, cohort)` |
| `fb_model` | 在 `contracts/mac-model-names.json` 中。形式符合 Mac 机型（`Mac`、`MacBook`、`MacBookAir`、`MacBookPro`、`MacPro`、`Macmini`、`iMac`、`iMacPro`、`VirtualMac` 加上 `数字,数字`）但不在列表中的，记为 `other`；其他值（如 `iPhone15,2`）丢弃 | `model_weekly(本周, model)` |
| `fb_os` | 11–40 之间的整数（macOS 主版本号） | `os_weekly(本周, os)` |
| `fb_arch` | `arm64` 或 `x86_64` | `arch_weekly(本周, arch)` |
| （无参数，取自 `request.cf.country`） | 两位国家代码 | `country_weekly(本周, country)` |

  - 「本周」由服务端按 UTC ISO 周计算，不信任客户端传来的时间。
  - 同一个请求最多 6 次 upsert，用 `db.batch()` 一次提交。
- 限流：以 `SHA-256(LIMIT_SALT + CF-Connecting-IP)` 为 key，每 60 秒 10 次。超过限制只跳过计数，仍然返回 302。

### `GET /api/stats`

- 返回最近 180 天的 `checksDaily`（每行 `{day, version, n}`），以及最近 26 周的 `cohorts`、`models`、`os`、`arch`、`countries`（每行 `{week, value, n}`）。
- 任何一行 `n < 5` 都不返回，响应中带 `"minimumGroupSize": 5`。
- 带 `Access-Control-Allow-Origin: <STATS_ORIGIN>` 和 `Cache-Control: public, max-age=3600`。生产环境用 Cache API 在边缘缓存 1 小时（缓存键忽略查询参数），不会每次访问都查询 D1。
- 数据库出错时返回 `503`（`no-store`，仍带 CORS 头）。

### 其他路径

一律返回 `404`。

### 定时任务（每天 UTC 04:23）

1. 从 GitHub Releases API（最近 100 个）同步已发布的版本号到 `releases` 表：去掉 tag 前面的 `v`，只接受 `数字.数字[.数字]`，可带预发布后缀（如 `0.9.0-beta.1`、`0.9.0b1`），只增不删。同步失败时保留旧列表。
2. 删除超过 730 天的计数行。

## 3. 客户端约定（供 Swift 端规格引用）

- 参数只在用户开启统计后、**每个 UTC ISO 周第一次成功加载 appcast 时**附带一次。「本周已上报」的标记要在 `updater(_:didFinishLoading:)` 之后才写入。
- 升级上来的老用户，`fb_cohort=legacy`。新安装的用户，取首次启动所在的 UTC ISO 周（只存在本机）。
- 未开启统计时，不附带任何 `fb_` 参数。

## 4. 存储（D1，与 `fanbar-compatibility` 共用；迁移记录在 `d1_migrations_update`）

```sql
releases(version TEXT PRIMARY KEY)
checks_daily(day TEXT, version TEXT, n INTEGER, PRIMARY KEY(day, version))
cohort_weekly(week TEXT, value TEXT, n INTEGER, PRIMARY KEY(week, value))
model_weekly / os_weekly / arch_weekly / country_weekly(week TEXT, value TEXT, n INTEGER, PRIMARY KEY(week, value))
```

写入一律用 `INSERT … ON CONFLICT DO UPDATE SET n = n + 1`。

## 5. 配置（`wrangler.jsonc`，结构参照 `services/compatibility`）

- 名称 `fanbar-update`，Custom Domain `update.getfanbar.com`，关闭 `workers_dev` 和预览 URL，`invocation_logs: false`。
- vars：`APPCAST_URL`、`FIRST_COHORT_WEEK`、`STATS_ORIGIN=https://getfanbar.com`。
- secret：`LIMIT_SALT`。
- 绑定：D1 `DB`，限流 `COUNT_LIMIT`。

## 6. 要测试的行为（按优先级，逐条 TDD）

测试都通过 `SELF.fetch` 和 `/api/stats` 这两个公开接口来验证，不直接查询数据库表。

1. `/appcast.xml` 返回 302，跳转到 `APPCAST_URL`，带 `no-store`，不带查询参数。
2. 合法的 Sparkle User-Agent 会让当天对应版本的计数 +1，可以在 `/api/stats` 里看到。
3. 计数低于 5 的分组不出现在 `/api/stats` 里。
4. 非 Sparkle 的 User-Agent 返回 302，但不计数。
5. 未发布的版本计入 `other`。
6. 数据库出错时，仍然返回 302（向 `default.fetch` 传入一个会抛错的 DB）。
7. 超过限流后，仍然返回 302，但不计数。
8. 开启统计后的字段：合法值被计入，非法值单独丢弃，不影响其他字段和版本计数。
9. `fb_cohort` 的边界：`legacy`、首周、当前周合法；早于首周、晚于当前周、格式错误的都不合法。
10. 周的计算：周日 23:59 UTC 和周一 00:00 UTC 属于不同的 ISO 周，包括跨年的情况（如 2026-12-31 属于 2026-W53）。
11. 不带 `fb_cohort` 时，其他 `fb_` 参数和国家都不计数。
12. 定时任务：同步版本列表（mock GitHub API）、同步失败时保留旧列表、删除 730 天前的数据。
13. 其他路径返回 404。

## 7. 上线前的运维事项（不写测试）

- 域名开启自动续费和转移锁。
- 外部拨测：每 5 分钟请求一次 `/appcast.xml`，期望得到 302，失败就告警。拨测请求的 User-Agent 不是 Sparkle 的，所以不会被计数。
- Worker 单独稳定运行一周后，再发布修改了 `SUFeedURL` 的 Beta 版。
