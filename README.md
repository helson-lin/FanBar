# FanBar

> 原生 macOS 菜单栏风扇控制器：看得到温度，也能在需要时精细管理散热策略。

FanBar 面向 macOS 11 Big Sur 及更高版本，适用于 Apple Silicon 与仍提供 `fpe2`
风扇数据的部分 Intel Mac。它以轻量的菜单栏界面呈现风扇转速和温度，并在用户明确
启用控制服务后提供固定转速、散热预设与智能温控。

## 亮点

- **一眼掌握状态**：菜单栏可显示图标、CPU 温度、平均风扇 RPM 或组合信息。
- **实时可视化**：查看 CPU/GPU 温度、近三分钟趋势，以及随 RPM 变化的气流动画。
- **多种散热方式**：恢复自动控制、设定目标 RPM，或使用静音、均衡、性能、极速预设。
- **智能温控**：按芯片温度在 35%–100% 之间平滑调速，可随时一键关闭。
- **安全回退**：转速始终限制在硬件报告范围内；退出、断连或服务异常时尽力恢复系统自动控制。
- **原生体验**：SwiftUI 界面、登录时启动、首次使用引导，以及 macOS 原生的控制服务授权流程。

## 系统要求

- macOS 11 Big Sur 或更高版本
- 一台能被 AppleSMC 读取到风扇数据的 Mac
- 如需自行构建：Xcode 26 与 Swift 6

> [!WARNING]
> SMC 是 Apple 未公开支持的硬件接口。降低转速可能导致过热；持续高转速可能增加噪音、
> 功耗与机械磨损。请只在理解风险的前提下启用手动控制，并优先使用“自动”或“智能温控”。

## 使用方式

1. 启动 FanBar 后，从菜单栏查看当前温度和风扇转速。
2. 需要手动控制时，选择“启用风扇控制服务”，并按系统提示完成授权。
3. 从菜单栏选择预设、固定转速或智能温控；完成后可随时恢复“自动”模式。

固定转速与预设支持 15 分钟、30 分钟或 1 小时的自动恢复，避免忘记关闭手动控制。

## 构建与运行

克隆仓库后，执行以下命令生成一个仅用于本机测试的应用包：

```sh
zsh scripts/generate-icons.sh
FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_SIGN_IDENTITY=-` 会使用 ad-hoc 签名，适合本地构建验证。若使用自己的有效
macOS 签名身份，可将该环境变量替换为相应身份名称。

### 创建本地 DMG

```sh
FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

默认产物为 `dist/FanBar-<version>.dmg`。若要为特定架构构建，可显式传入架构和输出路径：

```sh
FANBAR_ARCHS=arm64 FANBAR_APP_OUTPUT=dist/FanBar-arm64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-arm64.dmg zsh scripts/build-dmg.sh dist/FanBar-arm64.app

FANBAR_ARCHS=x86_64 FANBAR_APP_OUTPUT=dist/FanBar-x86_64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-x86_64.dmg zsh scripts/build-dmg.sh dist/FanBar-x86_64.app
```

验证 DMG 的签名、架构与安装结构：

```sh
zsh scripts/test-dmg.sh dist/FanBar-0.4.0.dmg
```

## 架构

FanBar 将界面与特权写入操作分开：主应用仅负责读取 SMC 数据和呈现 SwiftUI 界面；
受限的风扇控制请求通过 XPC 交给特权 helper 处理。

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

Helper 不提供任意 SMC 写入接口，只支持查询、固定/预设/按比例设置，以及恢复自动控制。
macOS 13+ 使用 `SMAppService` 管理服务；macOS 11–12 使用兼容的 launchd 注册流程。

## 持续集成与发布

GitHub Actions 会在推送和 Pull Request 时验证 universal2 构建；推送与 App 版本一致的
`v*` 标签时，会创建对应的 GitHub Release。

```sh
git tag -a v0.4.0 -m "FanBar 0.4.0"
git push origin v0.4.0
```

## 致谢与许可

Apple Silicon 的控制序列参考了 MIT 许可的
[`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan)。
完整的第三方归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
