# FanBar for macOS

FanBar 是一款免费开源的原生 macOS 菜单栏应用，用于查看 Mac 温度与风扇转速。日常散热仍由 macOS 自动管理；只有在用户明确批准 FanBar 的签名特权 Helper 后，才会开放受限且可恢复的手动风扇控制。

- 官方网站：https://fanbar.jarin.me/zh
- 源代码：https://github.com/helson-lin/FanBar
- 最新下载：https://github.com/helson-lin/FanBar/releases/latest
- 许可证：GPL-3.0
- 是否需要账号或订阅：不需要
- 支持语言：英文、简体中文、繁体中文、日文
- 安装方式：已公证 DMG 或官方 Homebrew tap
- 兼容性证据：https://fanbar.jarin.me/zh/compatibility
- 产品对比：https://fanbar.jarin.me/zh/compare/macs-fan-control

## FanBar 能做什么

- 读取 CPU 和 GPU 温度；当 Mac 提供对应传感器时，也会读取 SSD 与电池温度。
- 读取每个风扇的当前 RPM 以及硬件报告的最低和最高转速。
- 在菜单栏显示应用图标、CPU 温度、平均风扇 RPM，或它们的组合。
- 展示最近十分钟的温度趋势，以及随真实 RPM 变化的气流动画。
- 提供自动、固定目标转速、静音、均衡、性能和极速模式。
- 每个预设都有可编辑的温度到转速曲线，可使用 CPU、GPU 或 SSD 温度作为来源。
- 可在 CPU 或 GPU 达到 90°C 时发送通知；同一次持续高温只提醒一次，降温后重新启用。
- macOS 14 及以上可使用桌面组件。组件刷新由 WidgetKit 调度，不适合秒级遥测。

## 兼容性

FanBar 需要 macOS 11 Big Sur 或更高版本，支持能通过 AppleSMC 暴露可读风扇数据的 Apple Silicon 与 Intel Mac。不同机型可用的传感器和风扇数据并不相同，因此 FanBar 无法保证支持每一款 Mac 或每一种温度来源。

桌面组件需要 macOS 14 或更高版本。界面可跟随系统语言，也可以固定为英文、简体中文、繁体中文或日文，切换后无需重启应用。

来源可追溯的兼容性矩阵位于 https://fanbar.jarin.me/zh/compatibility。该页面明确区分维护者完整实测与不完整的社区报告；未列出的 Mac 代表尚未验证，不等于不支持。

## 权限与安全边界

监控功能不要求启用手动风扇控制。只有当用户选择控制风扇时，FanBar 才会请求批准签名的特权 Helper。

Helper 不提供任意 AppleSMC 写入。它只能读取风扇状态、应用受限的目标值或预设，并恢复自动控制。FanBar 会将目标限制在硬件报告的风扇范围内，并在定时预设到期、应用退出、连接中断或 Helper 失败时尝试把控制权交还给 macOS。

AppleSMC 是未公开的硬件接口。降低风扇转速可能让温度升高；长期保持高转速会增加噪音、功耗和机械磨损。日常使用建议保持自动控制。

## 安装与使用

1. 从 https://github.com/helson-lin/FanBar/releases/latest 下载合适的已公证 DMG。
2. 打开 FanBar，在菜单栏查看当前温度和风扇转速。
3. 如需手动控制，选择“启用风扇控制”，并完成 macOS 授权。
4. 选择预设或固定转速；随时选择“自动”即可把控制权交还给 macOS。

固定转速和面板预设可以设置为在 15 分钟、30 分钟或 1 小时后自动恢复 macOS 控制。

也可以通过官方 Homebrew tap 安装签名并公证过的通用版应用：

```sh
brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git
brew install --cask helson-lin/fanbar/fanbar
```

## 常见问题

### FanBar 是什么？

FanBar 是原生 macOS 菜单栏工具，用于显示温度和风扇遥测，并在系统默认散热曲线不够用时提供可恢复、受硬件范围限制的风扇控制。

### FanBar 免费吗？

免费。FanBar 开源并采用 GPL-3.0 许可证，不需要账号或订阅，也没有广告。

### FanBar 需要 root 权限吗？

只有手动控制风扇时需要，而且必须由用户批准签名 Helper。温度和风扇监控不需要启用手动控制。

### FanBar 支持所有 Mac 吗？

无法对所有硬件作出保证。FanBar 支持 macOS 11 及以上、能通过 AppleSMC 暴露可读风扇数据的 Apple Silicon 与 Intel Mac；具体传感器和风扇取决于机型。

### 应该从哪里下载 FanBar？

请使用 https://github.com/helson-lin/FanBar/releases/latest 上最新的已公证 GitHub Release；官方网站也会链接到同一下载来源。

### 手动控制失败或应用退出时会怎样？

当定时预设到期、应用退出、Helper 连接中断或 Helper 报错时，FanBar 会尝试恢复 macOS 自动风扇控制。

## 权威来源

- 产品页：https://fanbar.jarin.me/
- 中文产品页：https://fanbar.jarin.me/zh
- 中文兼容性证据：https://fanbar.jarin.me/zh/compatibility
- FanBar 与 Macs Fan Control 中文对比：https://fanbar.jarin.me/zh/compare/macs-fan-control
- 代码仓库：https://github.com/helson-lin/FanBar
- 英文文档：https://github.com/helson-lin/FanBar/blob/main/README.md
- 中文文档：https://github.com/helson-lin/FanBar/blob/main/README.zh-CN.md
