# 面板数据与显示问题复盘

## 无风扇时用量重复采样

根因：风扇读取失败会清空 SMC 连接。旧版 `refresh()` 在采样用量后调用重连方法，重连方法又调用 `refresh()`，导致同一次刷新采样两次。第二次 CPU 计数差分的时间窗口极短，历史也会重复追加。

修复：连接恢复在当前刷新内完成，用量每次刷新只采样一次。空风扇列表是有效读数，不触发重连。

回归测试位于 `Tests/FanBarTests/FanControllerReadingTests.swift`：

- `testEachRefreshSamplesUsageOnceAcrossFanReadFailuresAndRecovery`：持续读取失败及恢复时，采样次数和历史条数保持一致。
- `testEmptyFanListSamplesUsageOnceAndKeepsTheConnection`：无风扇时保持连接，逐次检查采样次数、核心读数、历史顺序及长度上限。
- `testUnavailableSMCStillSamplesUsageOncePerRefreshAndRecovers`：连接完全不可用时，用量仍按一次刷新一次采样更新，恢复时不重复采样。

## 模式行写死 CPU

根因：模式行用了正确的控制温度，却在文字中固定写 CPU。只测温度选择函数无法发现显示名称错误。

修复：面板模式行根据所选温度来源生成说明，与控制逻辑共用温度选择规则。GPU 缺失并回退到 CPU 时明确说明；SSD 缺失时显示无读数，不借用 CPU 温度。

回归测试位于 `Tests/FanBarTests/FanCurveSensorDisplayTests.swift`：

- `testPanelModeLineNamesItsActualTemperatureSource`：直接测试面板使用的模式说明函数，覆盖 CPU、GPU、SSD 和 CPU/GPU 较高者。CPU 平均值和最高值刻意设置为不同数值。
- `testPanelModeLineHandlesMissingSensorsAndOtherModes`：覆盖 GPU 回退、SSD 缺失、无温度数据、自动模式和固定模式。

## 磁盘总览掩盖启动盘空间不足

根因：把多个卷的容量加总后判断剩余空间。其他卷的空闲空间不能用于启动盘，但会把启动盘告警稀释为正常。

修复：总览明确显示启动盘，容量、剩余空间、使用比例和告警均来自挂载点 `/`，不依赖卷的排列顺序。启动盘读数缺失时显示无数据，不用其他内置卷或外置卷代替。展开列表仍显示每个卷及各自的告警。

回归测试位于 `Tests/FanBarTests/PanelDiskOverviewTests.swift`：

- `testStartupDiskFullWarningSurvivesLargeExternalVolume`：启动盘空间不足、大容量外置盘空闲时仍告警，并验证所有总览数字来自同一卷。
- `testStartupDiskLowSpaceUsesAbsoluteAndPercentageThresholds`：分别覆盖固定剩余容量及剩余比例触发的预警。
- `testHealthyStartupDiskIsNotReplacedByFullExternalVolume`：总览名称和数据的范围一致，不混用其他卷。
- `testMissingStartupDiskDoesNotBorrowOtherVolumesCapacity`：覆盖无磁盘、仅外置卷及仅数据卷的情况。
- `testFreeSpaceThresholdBoundaries`：覆盖临界值，防止边界判断回退。

## 菜单栏设置的资源分组保留旧语言

根因：资源行已监听界面语言，但外层 `MenuBarResourceSettings` 只观察控制器；读数不变时，分组标题和说明没有语言依赖，可能保留切换前的文本。仅重建行内 Picker 没有覆盖整个分组。

修复：外层分组监听语言偏好，并以语言作为视图标识，切换时一并重建标题、说明和资源行，不依赖新读数触发刷新。

回归测试：`MenuBarResourceLanguageTests.testResourceSectionRepaintsWithoutNewReadings` 在固定读数、外观、Locale 和资源偏好下，对比保留视图与同语言新视图，覆盖六种界面语言。修复前简体和繁体中文比较失败，修复后通过。原有 `SettingsLanguageRefreshTests` 继续检查全部设置页的语言切换。

## macOS 11 批准后控制服务仍未启用

根因：macOS 11–12 没有 `SMAppService`，走 launchd 旧路径。旧版把守护进程 plist 写进当前用户的临时目录，再以管理员身份执行 `launchctl bootstrap system <临时文件>`。launchd 只接受属主为 root、其他用户不可写的系统域 plist，因此用户批准授权提示后命令仍失败，服务保持未启用。即使加载成功，临时 plist 随即被删除，重启后服务也会消失。该问题自 v0.4.0 引入旧路径起就存在，不是 #155 引入的。

修复：新增纯类型 `LegacyHelperDaemon`。安装时以 root:wheel、0644 把 plist 复制到 `/Library/LaunchDaemons/local.fanbar.helper.plist`，先卸载已加载的旧任务并清除禁用标记，再从该路径加载。任务标签改为与 macOS 13+ 一致的 `local.fanbar.helper`，状态检查读取同一标签。卸载时任务未加载也不报错，并删除 plist。macOS 13+ 的 `SMAppService` 路径和助手的客户端认证未改动。

回归测试位于 `Tests/FanBarTests/LegacyHelperDaemonTests.swift`：

- `testMacOS11InstallLoadsARootOwnedPlistFromLaunchDaemons`：传入 macOS 11，要求安装命令以 root 属主复制 plist 并从 `/Library/LaunchDaemons` 加载，不再加载临时文件。用旧命令运行时失败。
- `testMacOS11InstallReplacesALoadedJobAndClearsADisabledFlag`：先卸载、再启用、最后加载。
- `testMacOS11StatusChecksTheLabelTheJobIsLoadedUnder`：任务标签、Mach 服务名和状态检查一致。
- `testBigSurAndMontereyRegisterTheHelperThroughLaunchd`：11、12 走 launchd，13 起走 `SMAppService`。
- `testInstallScriptFailsWhenBootstrapFailsAndSucceedsOtherwise`：用替身命令运行生成的脚本，验证加载失败时返回非零，任务未加载时卸载仍成功。

## 后续约束

- 刷新入口负责采样次数，重连不得再次进入刷新入口。
- 显示名称和显示数值必须来自同一数据来源；测试覆盖实际面板使用的说明函数。
- 容量汇总用于统计，单卷告警按单卷判断；测试同时检查状态、名称和数值范围。
- 明确区分读取失败、合法的零值和缺少数据，不用零值或其他设备数据掩盖缺失。
