<div align="center">

<img src="Assets/FanBar-readme-banner-light.png" alt="FanBar — 免费开源的原生 macOS 风扇控制工具" width="100%">

# FanBar

> 原生 macOS 菜单栏风扇控制器：看得到温度，也能在需要时精细管理散热策略。

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md"><strong>简体中文</strong></a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.fr.md">Français</a>
</p>

<p align="center">
  <a href="https://getfanbar.com/zh?utm_source=github&utm_medium=referral&utm_campaign=readme"><strong>官网 getfanbar.com</strong></a> ·
  <a href="https://getfanbar.com/zh/is-fanbar-safe?utm_source=github&utm_medium=referral&utm_campaign=readme">FanBar 安全吗？</a> ·
  <a href="https://getfanbar.com/zh/compare/macs-fan-control?utm_source=github&utm_medium=referral&utm_campaign=readme">与 Macs Fan Control 对比</a>
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases/latest">
    <img src="https://img.shields.io/github/v/release/helson-lin/FanBar?color=brightgreen" alt="release">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/github/downloads/helson-lin/FanBar/total?color=blue" alt="downloads">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fhelson-lin%2FFanBar%2Fbadges%2Fdmg-downloads.json" alt="DMG 安装包下载量" title="所有版本 DMG 的累计下载次数，包含更新下载，每日刷新。">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/stargazers">
    <img src="https://img.shields.io/github/stars/helson-lin/FanBar?color=yellow" alt="stars">
  </a>
</p>

<p align="center">
  <a href="#-截图">截图</a> •
  <a href="#-亮点">亮点</a> •
  <a href="#️-下载">下载</a> •
  <a href="#-使用方式">使用方式</a> •
  <a href="#️-构建与运行">构建</a> •
  <a href="#️-架构">架构</a> •
  <a href="#-持续集成与发布">发布</a> •
  <a href="#-反馈问题">反馈</a>
</p>

</div>

FanBar 支持 macOS 11 Big Sur 及更高版本，适用于 Apple Silicon 与仍提供可读 AppleSMC 风扇数据的 Intel Mac。日常使用保持 macOS 自动管理，只有在用户批准签名控制服务后才开放手动调速。

## FanBar 是什么

FanBar 是一款免费开源的原生 macOS 菜单栏应用，用于查看 CPU/GPU/SSD/电池温度和风扇转速。日常散热仍由 macOS 自动管理；只有在你明确批准签名 Helper 后，才会开放有限范围内的手动控制。

- **支持设备：** macOS 11 Big Sur 及以上，且 Mac 能通过 AppleSMC 提供可读的风扇数据；Apple Silicon 与 Intel 均支持。
- **散热模式：** 自动、固定目标转速，以及静音、均衡、性能、极速；每个预设都有可编辑的温度 → 转速曲线。
- **安全边界：** 目标转速始终限制在风扇报告的硬件范围内；预设到期、应用退出、连接中断或 Helper 失败时，FanBar 会尝试恢复「自动」。
- **下载：** 请使用[最新的已公证 GitHub Release](https://github.com/helson-lin/FanBar/releases/latest)，无需账号、订阅或广告。

官网提供了一份面向回答引擎和智能代理的 [llms.txt](https://getfanbar.com/llms.txt?utm_source=github&utm_medium=referral&utm_campaign=readme)，集中列出权威产品事实和文档入口。


## 📸 截图

以下为浅色与深色外观下的简体中文界面。可在 **设置 → 通用 → 界面语言** 中切换到英文、繁体中文、日语、俄语或法语，无需重启。

<table>
  <tr>
    <th>浅色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-light-zh-CN.png" alt="FanBar 简体中文菜单栏面板 (浅色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dark-zh-CN.png" alt="FanBar 简体中文菜单栏面板 (深色)" width="100%"></td>
  </tr>
</table>

在有两个风扇的 Mac 上，面板会并排显示每个风扇各自的转速、状态和范围。下图来自一台运行「均衡」预设的 MacBook Pro（M2 Max）。

<table>
  <tr>
    <th>浅色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-light-zh-CN.png" alt="FanBar 简体中文菜单栏面板，双风扇 MacBook Pro (浅色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-dark-zh-CN.png" alt="FanBar 简体中文菜单栏面板，双风扇 MacBook Pro (深色)" width="100%"></td>
  </tr>
</table>

「散热」页为每个面板预设提供独立的温度→转速曲线，可直接拖动控制点编辑。

<table>
  <tr>
    <th>浅色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-cooling-light-zh-CN.png" alt="FanBar 简体中文散热设置 (浅色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-cooling-dark-zh-CN.png" alt="FanBar 简体中文散热设置 (深色)" width="100%"></td>
  </tr>
</table>

「外观」页可选择菜单栏图标与显示内容，并通过模拟菜单栏实时预览。

<table>
  <tr>
    <th>浅色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-appearance-light-zh-CN.png" alt="FanBar 简体中文外观设置 (浅色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-appearance-dark-zh-CN.png" alt="FanBar 简体中文外观设置 (深色)" width="100%"></td>
  </tr>
</table>

「通用」页包含本机兼容性检查、控制服务状态、自动恢复、通知、语言、登录启动、更新，以及命令行与 Raycast 设置。「日志」页可把温度和风扇转速记录为 CSV。较长的设置页面可向下滚动。

<table>
  <tr>
    <th>浅色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-general-light-zh-CN.png" alt="FanBar 简体中文通用设置 (浅色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-general-dark-zh-CN.png" alt="FanBar 简体中文通用设置 (深色)" width="100%"></td>
  </tr>
</table>

## ✨ 亮点

- **一眼掌握状态**：菜单栏可显示图标、CPU 温度、平均风扇 RPM 或组合信息；组合信息可并排显示，也可上下排列以节省菜单栏宽度。
- **六款菜单栏图标**：漩涡、环形、粗体、螺旋桨、护罩、线条可选，均与系统图标做了光学对齐；由 FanBar 控制风扇时图标中心变为实心。风扇运转时图标随之旋转，停转后缓缓静止；可在 **设置 → 外观** 中关闭，让图标保持静止并节省少量 CPU。
- **实时可视化**：每个风扇先显示转速和转速区间，转速条从 0 到最大值。资源区紧凑显示 CPU、GPU、内存和磁盘占用，按程度显示绿、橙、红，磁盘按剩余空间判断。可查看 CPU/GPU 温度；设备支持时同时显示 SSD 与电池温度，并提供近十分钟趋势图。
- **桌面组件** — macOS 14 及更高版本可将 FanBar 风扇组件添加到桌面，查看平均 RPM、各风扇转速、CPU 温度和控制模式；组件由系统调度刷新，不保证秒级实时。
- **多种散热方式**：恢复自动控制、设定目标 RPM，或使用静音、均衡、性能、极速面板预设。
- **智能温控曲线**：每个面板预设都有独立曲线，按芯片温度平滑调速，可在设置中分别编辑。
- **温度来源可选**：温控曲线支持 CPU、GPU 或硬盘（SSD）温度作为控制来源；设备未提供对应传感器时会保持安全回退。
- **高温通知**：可在设置中开启 CPU/GPU 高温通知，达到设定温度（60–105°C，默认 90°C）时发送 macOS 通知；同一次高温只提醒一次，降温后会重新提醒。可选择提示音，即使关闭了通知声音或开启了专注模式也会播放。过热时面板会提供一键切换到最大散热。
- **命令行与 Raycast**：`fanbar` 命令行工具可以在终端或脚本里查看状态和温度、切换预设、设置固定转速，或把风扇交还给 macOS，并支持 `--json` 输出，方便自动化。在 **设置 → 通用 → 命令行与自动化** 中一键安装，同一处还能设置 Raycast 脚本命令。
- **CSV 日志**：每 2–60 秒把 CPU、GPU、SSD、电池温度、风扇转速和控制模式写入 `~/Library/Application Support/FanBar/Logs` 下的 CSV 文件，可选择在启动时、每天零点或从不新建文件。
- **安全回退**：转速始终限制在硬件报告范围内；退出、断连或服务异常时尽力恢复系统自动控制。
- **原生授权流程**：首次使用会解释控制服务用途，并自动打开正确的 macOS 设置页面。
- **六种界面语言**：English、简体中文、繁體中文、日本語、Русский、Français，也可跟随系统语言。

## ⬇️ 下载

最新已公证版本见 [GitHub Releases](https://github.com/helson-lin/FanBar/releases/latest)：

| 芯片 | 文件 |
|:--|:--|
| Apple Silicon | `FanBar-<version>-arm64.dmg` |
| Intel | `FanBar-<version>-x86_64.dmg` |
| Universal（Sparkle 在线更新使用） | `FanBar-<version>.dmg` |

### 通过 Homebrew 安装

安装 [Homebrew](https://brew.sh) 后，将本仓库添加为 tap 并安装：

```sh
brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git
brew install --cask helson-lin/fanbar/fanbar
```

Cask 会把已签名、公证的通用版应用安装到 `/Applications`，同时支持 Apple Silicon
和 Intel。启动 FanBar 后，按提示批准控制服务即可调节风扇。如果此前已手动安装，
请先退出 FanBar，并将已有的 `/Applications/FanBar.app` 移到废纸篓，再通过 Homebrew 安装。

FanBar 仍可通过 Sparkle 自动更新；也可以明确使用 Homebrew 升级：

```sh
brew update
brew upgrade --cask helson-lin/fanbar/fanbar
```

卸载前先退出 FanBar，然后运行：

```sh
brew uninstall --cask helson-lin/fanbar/fanbar
```

添加 `--zap` 可同时删除偏好设置和缓存。卸载风扇控制服务时，Homebrew 可能要求输入管理员密码。

### 系统要求

- macOS 11 Big Sur 或更高版本
- 一台能被 AppleSMC 读取到风扇数据的 Mac
- 如需自行构建：Xcode 26 与 Swift 6

> [!WARNING]
> SMC 是 Apple 未公开支持的硬件接口。降低转速可能导致过热；持续高转速可能增加噪音、功耗与机械磨损。请只在理解风险的前提下启用手动控制，并优先使用“自动”或“智能温控”。

## 🚀 使用方式

1. 启动 FanBar 后，从菜单栏查看当前温度和风扇转速。
2. 需要手动控制时，选择“启用风扇控制”，并按系统提示完成授权。
3. 从菜单栏选择面板预设或固定转速；完成后可随时恢复“自动”模式。

固定转速和面板预设支持在 15 分钟、30 分钟或 1 小时后自动恢复 macOS 管理，避免忘记关闭手动控制。

在 macOS 14 及更高版本中，打开通知中心的组件编辑器，搜索并添加 **FanBar**。组件展示主应用最近发布的风扇快照；WidgetKit 的刷新频率由 macOS 决定，因此需要秒级实时数据时仍应使用菜单栏面板。

### 命令行与 Raycast

在 **设置 → 通用 → 命令行与自动化 → 命令行工具** 中点「安装…」，会把 `/usr/local/bin/fanbar` 链接到 App 内的工具，随 FanBar 一起更新。

```sh
fanbar status                  # 模式、预设、风扇、温度
fanbar preset set performance
fanbar mode fixed 3000 --hold  # 保持到你手动更改
fanbar mode auto               # 把风扇交还给 macOS
```

不加 `--hold` 时，会按设置里的自动恢复时间交还 macOS 控制。加 `--json` 可输出机器可读结果。FanBar 未运行时，命令会在后台打开它；切换模式需要已批准风扇控制服务。

Raycast：在同一区块点「在 Raycast 中设置…」，然后在 Raycast 中添加一次脚本目录（设置 → Extensions → **+** → Add Script Directory）。之后就能在 Raycast 里切换预设、设置固定转速、交还自动控制，并在根搜索中直接看到 CPU、GPU、SSD 温度。

完整说明见 [docs/cli.md](docs/cli.md)（英文）。

### 切换界面语言

打开 **设置 → 通用 → 界面语言**，可选择：

- **System**：跟随 Mac 当前语言（简体中文、繁体中文、日语、俄语、法语，其他语言显示英文）
- **English**：英文界面
- **简体中文**：简体中文界面
- **繁體中文**：繁体中文界面（台湾用语）
- **日本語**：日语界面
- **Русский**：俄语界面
- **Français**：法语界面

语言设置会同步应用到菜单栏面板、设置窗口、首次使用引导、状态消息、控制服务错误提示和桌面组件。

## 🤝 社区

[贡献指南](CONTRIBUTING.md) · [行为准则](CODE_OF_CONDUCT.md) · [使用支持](SUPPORT.md) · [安全政策](SECURITY.md)

疑似安全漏洞请按安全政策私下报告；普通问题、功能建议和使用咨询请使用下面的公开 Issue 表单。

## 🐛 反馈问题

提交前请先搜索[已有 Issue](https://github.com/helson-lin/FanBar/issues)，再通过 [Issue 表单](https://github.com/helson-lin/FanBar/issues/new/choose)选择问题反馈、功能建议或使用问题。反馈 bug 时请提供 FanBar 版本、macOS 版本、Mac 型号及复现步骤；上传截图或日志前请移除个人信息。

## 🛠️ 构建与运行

克隆仓库后，执行以下命令生成一个仅用于本机测试的应用包：

```sh
zsh scripts/generate-icons.sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=-` 生成的 ad-hoc 包仅用于构建验证，特权 Helper 无法通过认证。测试风扇控制或发布时请使用真实签名身份；开发准备与验证方式见[贡献指南](CONTRIBUTING.md)。

### 创建本地 DMG

```sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

默认产物为 `dist/FanBar-<version>.dmg`。架构构建、签名和 DMG 验证方式请参考 [English README](README.md) 中的 Build and run 小节。

## 🏗️ 架构

FanBar 将界面与特权写入操作分开：

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

Helper 不提供任意 SMC 写入接口，只支持查询、固定/预设/按比例设置，以及恢复自动控制。macOS 13+ 使用 `SMAppService` 管理服务；macOS 11–12 使用兼容的 launchd 注册流程。

## 📦 持续集成与发布

FanBar 使用 Sparkle 2 检查和安装在线更新。稳定更新源为 GitHub Release 中的
`appcast.xml`；更新包必须同时通过 Developer ID、公证和 FanBar 专用 EdDSA
签名验证。

本机首次配置 Apple 公证凭据：

```sh
xcrun notarytool store-credentials FanBar-notary \
  --apple-id "你的 Apple ID" \
  --team-id "64S5F787T9"
```

将 `CFBundleShortVersionString` 和递增的 `CFBundleVersion` 提交到 `main` 后，执行：

```sh
gh auth login -h github.com
FANBAR_NOTARY_PROFILE=FanBar-notary zsh scripts/release-local.sh
```

本地发布脚本要求工作区干净且位于 `main`，会依次完成 universal2 构建、独立的
`arm64` / `x86_64` DMG、签名、公证、DMG 验证、校验和、签名 Appcast、Git
标签和 GitHub Release 上传。已有 Release 默认不会被覆盖；仅在明确重试时使用
`--replace-assets`。

Sparkle 私钥保存在登录钥匙串的 `FanBar` 账户中。首次发布后不要重新生成该密钥，
否则已安装版本无法验证后续更新。CI 发布还需将导出的私钥保存为
`SPARKLE_PRIVATE_KEY` GitHub Actions secret。

GitHub Actions 同样会在推送和 Pull Request 时验证 universal2 构建。本地发布是
默认方式；如果要改由标签触发 CI 发布，需要设置仓库变量
`FANBAR_PUBLISH_FROM_CI=true`，并配置 `SPARKLE_PRIVATE_KEY` 等 Release secrets。
不要同时启用 CI 发布和运行本地发布脚本。

启用 CI 发布模式后，推送与 App 版本匹配的标签：

```sh
git tag -a v0.6.3 -m "FanBar 0.6.3"
git push origin v0.6.3
```

### 更新 Homebrew Cask

通过本地脚本或 CI 发布稳定版后，运行以下命令下载通用 DMG、计算校验和，并将生成的
Cask 变更提交为 PR：

```sh
python3 scripts/update-homebrew-cask.py          # 最新稳定版
# 或：python3 scripts/update-homebrew-cask.py v0.6.3
```

脚本需要 Python 3 和已登录的 `gh` CLI，会拒绝草稿、预发布版本及缺少通用 DMG 的版本。
将 `Casks/fanbar.rb` 合并到 `main` 后，用户即可通过 `brew update` 获取新版。
Homebrew CI 会检查 Cask 格式、下载校验和、安装和卸载。

## ⭐ Star 趋势

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=helson-lin/FanBar&type=Date)](https://star-history.com/#helson-lin/FanBar&Date)

</div>

## 🙏 致谢与许可

Copyright © 2024–2026 Jarin He。FanBar 源代码采用 [GNU 通用公共许可证 v3.0（GPL-3.0）](LICENSE) 授权。

你可以使用、修改和再分发 FanBar（包括商业用途），但须遵守 GPL-3.0：保留版权与许可声明，并以相同许可证公开所分发修改版本的源代码。

**名称与图标不在授权范围内。**「FanBar」名称及 FanBar 图标/Logo 不属于 GPL-3.0 的授权范围。分发修改版本时必须更改名称并替换图标，以免与官方 FanBar 混淆。

Apple Silicon 的控制序列参考了 MIT 许可的 [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan)。完整的第三方归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

感谢以下朋友反馈 bug，帮助 FanBar 变得更好：

<table>
  <tr>
    <td align="center">
      <img src="docs/contributors/qingcang.png" width="64" height="64" alt="倾藏的头像"><br>
      <sub><b>倾藏</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/yisasayisa.png" width="64" height="64" alt="一撒撒一撒的头像"><br>
      <sub><b>一撒撒一撒</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/taolela.png" width="64" height="64" alt="Taolela 的头像"><br>
      <sub><b>Taolela</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/estelle00.png" width="64" height="64" alt="Estelle00 的头像"><br>
      <sub><b>Estelle00</b></sub>
    </td>
  </tr>
</table>

### 本机兼容性检测

在 **设置 → 通用 → 设备兼容性** 查看本机 CPU、GPU、SSD、电池温度与风扇读取结果，以及控制服务和控制请求状态。首次启动摘要和散热异常提示也能打开同一页面。

检测在本机完成，不联网、不自动安装控制服务，也不会为了测试改变转速。缺少读数或一次失败不会被判定为机型不支持；控制服务就绪、请求成功与实际转速验证是不同的证据。控制请求记录仅保留在本次运行中。

机型记录随应用提供，按机型和系统／应用／控制服务版本匹配。当前列表尚无正式验证记录，页面会明确说明，不推测兼容范围。可以离线预览并保存固定字段的 JSON 报告；主动准备上报、查看规则并确认后，才向 https://report.getfanbar.com 提交。原始报告默认私有，用户可选择审核后公开；每份报告的独立撤回凭证在发送前保存在本机钥匙串。不会收集序列号、设备唯一标识、用户名、文件路径、进程列表或温度历史。

Workers＋D1 服务、公开兼容性页、审核后台、上传字段与处理规则的源码见 [services/compatibility](services/compatibility/README.md) 和 [contracts](contracts)。
