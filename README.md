# FanBar

FanBar 是一个 macOS 原生菜单栏风扇控制应用，面向 Apple Silicon 和仍使用
`fpe2` 风扇数据的旧款 Mac。

## 功能

- 菜单栏实时显示每个风扇的 RPM。
- 可在设置窗口中选择菜单栏显示图标、CPU 温度、平均风扇 RPM 或二者组合。
- 风扇周围的冰蓝气流动效会随实时 RPM 改变速度和强度。
- 首次启动提供可跳过的三步快速引导，并可通过底部 `?` 随时重播。
- 显示 CPU/GPU 当前温度与最近约三分钟的滚动曲线。
- 可通过 macOS 原生登录项设置登录时自动启动。
- 恢复 macOS 自动散热策略。
- 将全部风扇设置为固定目标 RPM，并按硬件报告的最小/最大值截断。
- 提供静音 35%、均衡 50%、性能 65% 和极速 80% 四档散热预设；设置中最多选择两个快捷展示。
- 智能温控可随芯片温度在 35% 到 100% 间平滑调速，并支持一键开启或关闭。
- 散热预设或固定转速可在 15 分钟、30 分钟或 1 小时后自动恢复 macOS 管理。
- Apple Silicon 上运行时探测 `F%dMd` / `F%dmd` 模式键。
- 必要时使用 `Ftst` 解锁序列等待 `thermalmonitord` 释放系统模式。
- App 退出、XPC 断连或 Helper 终止时尽力恢复自动控制。
- 睡眠唤醒后重新应用用户选择的固定模式。

## 架构与权限

普通 FanBar 进程只读取 SMC，并负责 SwiftUI 界面。写入由随 App 签名的
`local.fanbar.helper` LaunchDaemon 完成：

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

Helper 不暴露任意 SMC 写接口，只接受查询、设置全部风扇和恢复自动三类请求。
它还会校验调用方必须是 Team ID `64S5F787T9` 签名的
`local.fanbar.app`。

首次点击“启用风扇控制服务”时，macOS 会要求用户批准后台 root 服务。可在
“系统设置 → 通用 → 登录项与扩展”中查看或撤销。FanBar 会先解释服务用途，
再打开对应的系统设置页面，并每两秒检测批准状态；成功后会在原引导位置确认
“控制服务已启用”。

## 构建

需要 Xcode 26、Swift 6，以及钥匙串中的：

`Developer ID Application: JiangLin He (64S5F787T9)`

运行：

```sh
zsh scripts/generate-icons.sh
zsh scripts/package-app.sh
open dist/FanBar.app
```

生成物位于 `dist/FanBar.app`。构建脚本会先签名内嵌 Helper，再签名主 App。

生成本地 DMG：

```sh
zsh scripts/build-dmg.sh
```

只读挂载并验证签名、架构、安装结构和遥测：

```sh
zsh scripts/test-dmg.sh dist/FanBar-0.4.0.dmg
```

GitHub Actions 会在普通提交上验证 universal2 构建，并在推送与 App 版本匹配的
`v*` 标签时完成 Developer ID 签名、Apple 公证和 GitHub Release。首次使用前
按照 [`docs/releasing.md`](docs/releasing.md) 配置仓库 Secrets。

## 安全边界

SMC 是 Apple 未公开支持的硬件接口。固定转速可能增加噪音、功耗和机械磨损；
过低转速可能造成过热。FanBar 不允许绕过硬件报告的安全范围，并在部分失败时
回滚全部风扇到自动模式。

Apple Silicon 控制序列参考了 MIT 许可的
[`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan)。
完整归属信息见 `THIRD_PARTY_NOTICES.md`。
