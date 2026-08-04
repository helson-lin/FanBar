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
                Text("快速开始")
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
                Button("跳过") { onSkip() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)

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
            Button(isTelemetryAvailable ? "看懂了" : "继续") { onNext() }
                .buttonStyle(DefaultButtonStyle())
                .controlSize(.small)
        case 1:
            Button("保持自动并继续") { onNext() }
                .buttonStyle(DefaultButtonStyle())
                .controlSize(.small)
        default:
            switch helperState {
            case .enabled:
                Button("完成") { onFinish() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .requiresApproval:
                Button("以后再说") { onFinish() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("打开系统设置") { onOpenHelperSettings() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .notRegistered:
                Button("以后再说") { onFinish() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("继续并打开设置") { onEnableHelper() }
                    .buttonStyle(DefaultButtonStyle())
                    .controlSize(.small)
            case .unavailable:
                Button("控制服务不可用") {}
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
        case 0: isTelemetryAvailable ? "实时状态就在这里" : "正在连接硬件传感器"
        case 1: "系统控制是安全默认值"
        default:
            switch helperState {
            case .enabled: "控制服务已启用"
            case .requiresApproval: "在系统设置中批准"
            case .notRegistered: "允许 FanBar 调整风扇"
            case .unavailable: "控制服务不可用"
            }
        }
    }

    private var detail: String {
        switch step {
        case 0:
            isTelemetryAvailable
                ? "叶片动画反映相对转速，RPM 数字提供精确读数；下方曲线记录最近的温度变化。"
                : "连接成功后，这里会显示每枚风扇的真实转速与 CPU、GPU 温度。"
        case 1:
            "日常使用无需干预。FanBar 启动时交由 macOS 自动管理，只有你主动开启智能温控或选择手动模式才会切换。"
        default:
            switch helperState {
            case .enabled:
                "智能温控、散热预设和固定转速现已可用。退出 FanBar 时会自动恢复 macOS 管理。"
            case .requiresApproval:
                "请在“登录项与扩展”中允许 FanBar。批准后无需手动刷新，这里会自动确认结果。"
            case .notRegistered:
                "实时监测无需权限。智能温控和手动模式需要签名控制服务；它只接受 FanBar 的受限请求。"
            case .unavailable:
                "当前应用包中未找到签名控制服务，请重新安装完整版本的 FanBar。"
            }
        }
    }
}
