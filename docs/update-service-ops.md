# 更新检查服务运维 / Update service operations

`update.getfanbar.com` 把 Sparkle 的更新检查 302 到 GitHub 上的 appcast，并做匿名计数（规格见 [services/update/SPEC.md](../services/update/SPEC.md)）。`SUFeedURL` 一旦写进已发布的 App 就无法收回，所以在 App 指向它之前，要先证明它稳定，并准备好退路。

## 拨测

[`update-service-probe.yml`](../.github/workflows/update-service-probe.yml) 每 5 分钟运行 [`scripts/probe-update-service.sh`](../scripts/probe-update-service.sh)，失败时 GitHub 会给最近编辑该定时任务的人发邮件。手动运行：

```sh
scripts/probe-update-service.sh
```

每次检查：返回 302、`Location` 是预期的 appcast 地址、带 `Cache-Control: no-store`、跳转耗时不超过 3 秒，并确认 GitHub 上的 appcast 可以打开。退出码 1 是 Worker 故障，2 是 GitHub 上的 appcast 打不开（此时 Worker 本身没问题）。失败会重试两次，一次网络抖动不会告警。

拨测的 User-Agent 不是 `FanBar/<版本> Sparkle/<版本>`，不会被计数。

局限：GitHub 的定时任务可能晚几分钟启动；仓库 60 天没有活动会被自动停用；它只能从一个地区探测。所以超过 30 分钟没有收到任何一次成功运行记录，也当作故障处理。

## 发布带新 `SUFeedURL` 的版本之前（必须全部满足）

- [ ] 拨测已经连续运行至少 7 天。
- [ ] 这 7 天累计不可用不超过 10 分钟（约 99.9%），没有一次响应超过 3 秒。
- [ ] Cloudflare 后台里该 Worker 的错误率为 0，日志里没有持续出现 `update check not counted`。
- [ ] 做过一次故障演练：让 D1 暂时不可用（例如在测试环境删掉绑定），确认 `/appcast.xml` 仍然返回 302。
- [ ] 按下面的「回退」步骤在不依赖 Worker 代码的情况下走通一次。
- [ ] 域名已开启自动续费和转移锁。
- [ ] 版本说明开头写明统计内容，PRIVACY 已更新（见规格 1 和 7）。

一周的数据只能证明这一周没出问题，不能保证以后不会出问题。真正的保险是拨测加回退。

## 故障处理

先分清哪一层坏了：

| 现象 | 说明 | 处理 |
|---|---|---|
| 拨测退出码 2 | Worker 正常，GitHub 的 appcast 打不开 | 不是本服务的问题，查看 GitHub 状态页 |
| 状态码不是 302，或超时 | Worker、路由或域名故障 | 立即回退 |
| `Location` 不对 | `APPCAST_URL` 配置错误 | 修正变量并重新部署，或回退 |
| 只有计数缺失 | D1 或限流故障，不影响更新 | 不用回退，修好再补充说明 |

## 回退：让更新检查完全绕过 Worker 代码

目标是让 `https://update.getfanbar.com/appcast.xml` 在 Worker 不可用时仍然跳到 GitHub。按顺序尝试，第一个能成功的就够了：

1. **回滚部署**：在 Cloudflare 的 Workers 页面把 `fanbar-update` 回滚到上一个正常的版本。
2. **用重定向规则代替 Worker**：在 `getfanbar.com` 的 Rules → Redirect Rules 新建一条，匹配主机名 `update.getfanbar.com` 且路径为 `/appcast.xml`，动态目标为 `https://github.com/helson-lin/FanBar/releases/latest/download/appcast.xml`，状态码 302，不保留查询参数。然后在 Workers 路由里把自定义域名从 Worker 上移除（规则只对经过 Cloudflare 代理的域名生效，先确认域名是代理状态）。
3. **以上都不行**：这只可能是域名或 DNS 本身出了问题，Worker 和规则都无能为力，只能修复域名；此期间已安装新版的用户检查不到更新，需要在 README 和发布页说明手动下载。

恢复之后，把「回退前的状态」写进 [docs/regression-review.md](regression-review.md)，包括根因和新增的检查。

> 步骤 2 的界面入口可能随 Cloudflare 更新而变化，第一次演练时请核对并更新这里。
