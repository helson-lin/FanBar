# FanBar 更新检查与匿名计数服务

Cloudflare Workers + D1，服务地址 `https://update.getfanbar.com`。它是 Sparkle 更新源的入口：**永远把请求 302 跳转到 GitHub 上的 appcast**，顺带统计匿名计数。计数失败、限流、输入非法或数据库故障，都不会影响跳转。

默认只按天、按版本统计更新检查次数；用户在 App 中主动开启「共享匿名使用统计」后，每周另外统计安装批次、机型、macOS 主版本、架构和国家。数据库只存「按天或按周 × 单一维度」的计数，不保存 IP、User-Agent 原文或任何设备标识。

- 规格与边界：[SPEC.md](SPEC.md)
- 对用户公开的说明（App 链接到此处；中文界面打开中文版，其他语言打开英文版；英文版为准）：[PRIVACY.md](PRIVACY.md)（英文）· [PRIVACY.zh-CN.md](PRIVACY.zh-CN.md)（中文）
- 公开统计页：`https://getfanbar.com/stats`（页面不在本目录）

## API

| 方法与路径 | 行为 |
| --- | --- |
| GET /appcast.xml | 始终 302 到 `APPCAST_URL`，带 `Cache-Control: no-store`，不转发查询参数。用 `ctx.waitUntil` 异步计数；只有 Sparkle 的 User-Agent 才计数；带合法 `fb_cohort` 时才处理 `fb_model`、`fb_os`、`fb_arch` 和国家 |
| GET /api/stats | 最近 180 天的 `checksDaily`，最近 26 周的 `cohorts`、`models`、`os`、`arch`、`countries`；小于 5 的分组不返回，响应带 `minimumGroupSize: 5`；CORS 仅允许 `STATS_ORIGIN`，缓存 1 小时 |
| 其他路径 | 404 |
| 定时任务（每天 UTC 04:23） | 从 GitHub Releases 同步已发布版本号（只增不删，失败时保留旧列表）；删除超过 730 天的计数 |

限流：以 `SHA-256(LIMIT_SALT + CF-Connecting-IP)` 为键，每 60 秒 10 次，超出只跳过计数。哈希只送入限流器，不写入数据库。

## 本地开发

Node 24+。复制 `.dev.vars.example` 为 `.dev.vars`，把 `LIMIT_SALT` 换成随机值（例如 `openssl rand -base64 32`）；文件不得提交，开发和生产必须使用不同的值。

```sh
npm ci
npm run db:local
npm run dev
```

打开 `http://localhost:8787/appcast.xml` 应得到 302。检查与测试：

```sh
npm run check
npm test
npm run dry-run
```

`npm run check` 校验从配置生成的绑定类型并运行 `tsc`；`npm test` 在 Workers 模拟运行时里通过公开接口验证行为；`npm run dry-run` 用 production 环境配置做一次不发布的部署检查。CI（`.github/workflows/update-service.yml`）依次运行这三项。

## 生产部署

1. `npx wrangler login`，确认当前账号管理 `getfanbar.com`。
2. 创建 D1：`npx wrangler d1 create fanbar-usage`，把返回的 UUID 写入 `wrangler.jsonc` 中 `env.production.d1_databases` 的 `database_id`。顶层的开发绑定只用于本地模拟。
3. 保存生产用的 LIMIT_SALT（随机值，不要放进命令参数、源码或日志）：

   ```sh
   npx wrangler secret put LIMIT_SALT --env production
   ```

4. 应用迁移、干运行、部署：

   ```sh
   npx wrangler d1 migrations apply fanbar-usage --env production --remote
   npm run dry-run
   npm run deploy
   ```

5. Custom Domain 固定为 `update.getfanbar.com`（写在 production 环境的 `routes`，部署时由 Wrangler 绑定）；`workers_dev` 和预览 URL 关闭。部署后确认 `curl -sI https://update.getfanbar.com/appcast.xml` 返回 302 和正确的 `Location`。

`APPCAST_URL`、`FIRST_COHORT_WEEK`、`STATS_ORIGIN` 是 `wrangler.jsonc` 中的普通变量。

## 上线前的运维清单

规格第 7 节：

- [ ] 域名开启自动续费和转移锁。
- [ ] 外部拨测：每 5 分钟请求一次 `/appcast.xml`，期望得到 302，失败就告警。拨测的 User-Agent 不是 Sparkle 的，不会被计数。
- [ ] Worker 单独稳定运行一周后，再发布修改了 `SUFeedURL` 的 Beta 版客户端。

## 日志

只输出无请求细节的固定错误信息；Workers 调用日志关闭。不要额外配置抓取完整请求的 Logpush、调试日志或第三方埋点。
