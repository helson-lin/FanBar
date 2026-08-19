import FanBarShared
import SwiftUI

/// A compact, non-blocking first-run guide that teaches FanBar in the real menu.
struct OnboardingCard: View {
    let step: Int
    let helperState: FanController.HelperState
    let isTelemetryAvailable: Bool
    let onNext: () -> Void
    let onEnableHelper: () -> Void
    let onOpenHelperSettings: () -> Void
    let onFinish: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let stepCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(fanBarText("快速开始", "Quick start"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(step + 1) / \(stepCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.11)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(fanBarText("跳过", "Skip")) { onSkip() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    // AppKit otherwise assigns first focus to this plain-text
                    // action when the menu opens, producing a blue text ring.
                    .focusable(false)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                primaryAction
            }

            HStack(spacing: 5) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? tint : Color.primary.opacity(0.09))
                        .frame(width: index == step ? 18 : 6, height: 4)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
            .accessibilityHidden(true)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.accentColor.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case 0:
            Button(isTelemetryAvailable
                ? fanBarText("看懂了", "Got it")
                : fanBarText("继续", "Continue")) { onNext() }
                .buttonStyle(DefaultButtonStyle())
                .controlSize(.small)
        case 1:
            Button(fanBarText("保持自动并继续", "Keep automatic and continue")) { onNext() }
                .buttonStyle(DefaultButtonStyle())
                .controlSize(.small)
        default:
            switch helperState {
            case .enabled:
                Button(fanBarText("完成", "Done")) { onFinish() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .requiresApproval:
                Button(fanBarText("以后再说", "Not now")) { onFinish() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .focusable(false)

                Button(fanBarText("打开系统设置", "Open System Settings")) { onOpenHelperSettings() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .notRegistered:
                Button(fanBarText("以后再说", "Not now")) { onFinish() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .focusable(false)

                Button(fanBarText("继续并打开设置", "Continue and open Settings")) { onEnableHelper() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .unavailable:
                Button(fanBarText("控制服务不可用", "Control service unavailable")) {}
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
                    .disabled(true)
            }
        }
    }

    private var icon: String {
        switch step {
        case 0: isTelemetryAvailable ? "gauge.with.dots.needle.67percent" : "sensor"
        case 1: "checkmark.shield"
        default:
            switch helperState {
            case .enabled: "checkmark.circle.fill"
            case .requiresApproval: "arrow.up.forward.app"
            case .notRegistered: "lock.shield"
            case .unavailable: "exclamationmark.triangle"
            }
        }
    }

    private var tint: Color {
        guard step == 2 else { return .accentColor }
        switch helperState {
        case .enabled: return .green
        case .unavailable: return .red
        case .requiresApproval, .notRegistered: return .orange
        }
    }

    private var title: String {
        switch step {
        case 0: isTelemetryAvailable
            ? fanBarText("实时状态就在这里", "Live status is here")
            : fanBarText("正在连接硬件传感器", "Connecting to hardware sensors")
        case 1: fanBarText("系统控制是安全默认值", "System control is the safe default")
        default:
            switch helperState {
            case .enabled: fanBarText("控制服务已启用", "Control service enabled")
            case .requiresApproval: fanBarText("在系统设置中批准", "Approve in System Settings")
            case .notRegistered: fanBarText("允许 FanBar 调整风扇", "Allow FanBar to adjust fans")
            case .unavailable: fanBarText("控制服务不可用", "Control service unavailable")
            }
        }
    }

    private var detail: String {
        switch step {
        case 0:
            isTelemetryAvailable
                ? fanBarText(
                    "叶片动画反映相对转速，RPM 数字提供精确读数；下方曲线记录最近的温度变化。",
                    "Rotor motion shows relative speed, RPM provides the exact reading, and the chart tracks recent temperature changes."
                )
                : fanBarText(
                    "连接成功后，这里会显示每枚风扇的真实转速与 CPU、GPU 温度。",
                    "Once connected, this area shows each fan's actual speed and CPU/GPU temperatures."
                )
        case 1:
            fanBarText(
                "日常使用无需干预。FanBar 启动时交由 macOS 自动管理，只有你主动选择面板预设曲线或其他手动模式才会切换。",
                "No intervention is needed for everyday use. FanBar starts under macOS automatic management and only switches when you choose a panel preset curve or another manual mode."
            )
        default:
            switch helperState {
            case .enabled:
                fanBarText(
                    "面板预设曲线和固定转速现已可用。退出 FanBar 时会自动恢复 macOS 管理。",
                    "Panel preset curves and fixed RPM are ready. macOS management is restored when FanBar quits."
                )
            case .requiresApproval:
                fanBarText(
                    "请在“登录项与扩展”中允许 FanBar。批准后无需手动刷新，这里会自动确认结果。",
                    "Allow FanBar in Login Items & Extensions. The result is confirmed automatically after approval."
                )
            case .notRegistered:
                fanBarText(
                    "实时监测无需权限。面板预设曲线和手动模式需要签名控制服务；它只接受 FanBar 的受限请求。",
                    "Live monitoring needs no permission. Panel preset curves and manual modes use a signed service that accepts only limited FanBar requests."
                )
            case .unavailable:
                fanBarText(
                    "当前应用包中未找到签名控制服务，请重新安装完整版本的 FanBar。",
                    "The signed control service is missing from this app bundle. Reinstall the complete FanBar app."
                )
            }
        }
    }
}
