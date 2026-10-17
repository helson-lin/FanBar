# FanBar Mac 兼容性与测试证据

最后更新：2026 年 10 月 11 日  
规范页面：https://fanbar.jarin.me/zh/compatibility

FanBar 支持 macOS 11 及以上、能通过 AppleSMC 提供可读风扇数据的 Apple Silicon 与 Intel Mac。不同机型的传感器与风扇行为可能不同。本页明确区分公开观察记录与维护者完整实测。

## 证据标签

- **维护者完整实测：** 使用准确 Mac 机型、macOS 版本、FanBar 构建、结果和日期完成全部测试清单。
- **社区报告：** 公开 GitHub Issue 记录了部分行为，但没有完成全部清单。
- **需要复测：** 旧版本报告或已知问题需要在当前版本重新验证。
- **未列出：** 尚无足够详细的公开证据，不代表不支持。

## 维护者完整实测

目前尚未发布。FanBar 不会在缺少标准化结果时把某个 Mac 机型标记为完整验证。

## 社区报告

| Mac | 系统 | 来源证明了什么 | 证据边界 | 日期与来源 |
| --- | --- | --- | --- | --- |
| Mac mini，M6 | macOS 27；FanBar 版本未记录 | 报告者观察到从「自动」切换到「性能」「极速」和「固定转速」后，风扇转速会上升。 | 社区报告；没有完成逐项传感器测试。 | 2026-10-02 · [Issue #43](https://github.com/helson-lin/FanBar/issues/43) |
| 16 英寸 MacBook Pro，M2 Max | macOS 27；FanBar 0.5.0 | 应用可以启动并持续运行，足以观察 CPU 与内存占用。 | 社区报告；没有记录固定转速或曲线测试，性能问题仍开放。 | 2026-10-09 · [Issue #63](https://github.com/helson-lin/FanBar/issues/63) |
| Apple Silicon Mac，Mac15,8 | macOS 26.5；FanBar 0.4.3 | 报告涉及特权 Helper 与手动控制恢复路径。 | 需要复测；旧版本曾报告关机恢复崩溃。 | 2026-08-20 · [Issue #6](https://github.com/helson-lin/FanBar/issues/6) |
| Mac mini（2014），Intel | macOS 与 FanBar 版本未记录 | 应用及其后台/菜单栏集成曾在设备上运行。 | 社区报告；没有记录温度、RPM、固定转速或曲线控制。 | 2026-10-07 · [Issue #50](https://github.com/helson-lin/FanBar/issues/50) |

## 标准验证清单

1. 应用可以启动并保持稳定。
2. CPU 与 GPU 温度可以读取。
3. 硬件提供时可以读取 SSD 与电池温度。
4. 每个风扇都显示当前、最低与最高 RPM。
5. 固定 RPM 可以改变风扇输出，且不超出硬件报告范围。
6. 温控曲线会按预期改变风扇输出。
7. 退出、断连、超时或 Helper 失败时恢复自动控制。
8. 睡眠、唤醒、重启与登录项行为稳定。

提交报告：https://github.com/helson-lin/FanBar/issues/new/choose

## 常见问题

### FanBar 支持 Apple Silicon 吗？

支持能通过 AppleSMC 提供可读风扇数据的 Apple Silicon Mac。未列出表示尚未验证，不等于不支持。

### FanBar 免费且开源吗？

是。FanBar 采用 GPL-3.0 许可，免费使用，无需账号或订阅，并公开包含特权 Helper 在内的完整源码。

### 为什么控制风扇需要管理员权限？

读取温度不需要启用手动控制。修改风扇目标值需要通过签名的特权 Helper 访问 AppleSMC，因此 macOS 会先要求你明确授权。

### FanBar 退出时会发生什么？

FanBar 会尝试恢复 macOS 自动风扇控制，目标转速也始终限制在硬件报告范围内。
