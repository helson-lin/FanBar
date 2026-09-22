import FanBarShared
import SwiftUI

/// User-facing description of the control service, shared by the menu panel
/// and the settings window so the two always say the same thing.
extension FanController.HelperState {
    /// Each state has a distinct symbol, so status never relies on color alone.
    var symbolName: String {
        switch self {
        case .requiresApproval: "lock.open"
        case .notRegistered: "lock.shield"
        case .unavailable: "exclamationmark.triangle"
        case .enabled: "checkmark.shield"
        }
    }

    var tint: Color {
        switch self {
        case .enabled: .green
        case .unavailable: .red
        case .requiresApproval, .notRegistered: .orange
        }
    }

    var noticeTitle: String {
        switch self {
        case .requiresApproval: fanBarText("批准控制服务", "Approve control service")
        case .notRegistered: fanBarText("控制服务未启用", "Control service is off")
        case .unavailable: fanBarText("控制服务不可用", "Control service unavailable")
        case .enabled: fanBarText("控制服务已启用", "Control service enabled")
        }
    }

    var noticeDetail: String {
        switch self {
        case .requiresApproval: fanBarText("在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions")
        case .notRegistered: fanBarText(
            "启用后可使用温控预设和手动控制",
            "Enable it for cooling presets and manual control"
        )
        case .unavailable: fanBarText("请重新安装已签名的 FanBar", "Reinstall the signed FanBar app")
        case .enabled: fanBarText("仅接受同一开发者签名的请求", "Only requests signed by the same developer are accepted")
        }
    }

    /// The one action that moves the service toward enabled; nil when none applies.
    var actionTitle: String? {
        switch self {
        case .requiresApproval: fanBarText("打开系统设置", "Open System Settings")
        case .notRegistered: fanBarText("启用", "Enable")
        case .enabled, .unavailable: nil
        }
    }
}

extension FanController {
    func performHelperAction() {
        switch helperState {
        case .requiresApproval: openHelperSettings()
        case .notRegistered: enableHelper()
        case .enabled, .unavailable: break
        }
    }
}
