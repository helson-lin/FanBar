import AppKit
import FanBarShared
import SwiftUI

struct FanMenu: View {
    @ObservedObject var controller: FanController
    @AppStorage("fanbar.onboarding.v1.completed")
    private var hasCompletedOnboarding = false
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visibleCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onboardingStep = 0

    private var isManual: Bool {
        controller.mode != .automatic
    }

    private var isFixed: Bool {
        if case .fixed = controller.mode { return true }
        return false
    }

    private var modeLabel: String {
        switch controller.mode {
        case .automatic: "自动"
        case .temperatureCurve: "智能温控"
        case .fixed(let rpm): "\(rpm.formatted()) RPM"
        case .preset(let preset): "\(preset.title) \(preset.percentageText)"
        }
    }

    private var visibleCoolingPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visibleCoolingPresetsRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !hasCompletedOnboarding {
                OnboardingCard(
                    step: onboardingStep,
                    helperState: controller.helperState,
                    isTelemetryAvailable: controller.isAvailable,
                    onNext: advanceOnboarding,
                    onEnableHelper: controller.enableHelper,
                    onOpenHelperSettings: controller.openHelperSettings,
                    onFinish: completeOnboarding,
                    onSkip: completeOnboarding
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if controller.isAvailable {
                fanPanel
                TemperatureChart(samples: controller.temperatureHistory)
                modeControl
                safetyNote
            } else {
                unavailableState
            }

            if controller.helperState != .enabled {
                helperNotice
            }

            launchAtLoginRow
            footer
        }
        .padding(18)
        .frame(width: 370)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("FanBar")
                        .font(.headline)
                    modeBadge
                }
                Text(controller.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                SettingsWindowPresenter.shared.show(controller: controller)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开 FanBar 设置")
            .help("设置")

            Button { controller.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controller.isBusy)
            .accessibilityLabel("刷新风扇状态")
        }
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isManual ? Color.orange : Color.green)
                .frame(width: 5, height: 5)
            Text(modeLabel)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private var fanPanel: some View {
        HStack(spacing: 0) {
            ForEach(Array(controller.fans.prefix(2)).indices, id: \.self) { position in
                let fan = controller.fans[position]
                FanGauge(fan: fan, isManual: isManual)

                if position < min(controller.fans.count, 2) - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 142)
                }
            }
        }
        .padding(.horizontal, 7)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制模式")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            temperatureCurveControl

            HStack(spacing: 6) {
                Button {
                    controller.setAutomatic()
                } label: {
                    modeButtonLabel(
                        title: "自动",
                        systemImage: "wand.and.stars",
                        selected: !isManual
                    )
                }
                .buttonStyle(.plain)

                ForEach(visibleCoolingPresets) { preset in
                    Button {
                        controller.setCoolingPreset(preset)
                    } label: {
                        modeButtonLabel(
                            title: preset.title,
                            systemImage: preset.systemImage,
                            selected: controller.mode == .preset(preset)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("\(preset.title) · 各风扇最大转速的 \(preset.percentageText)")
                }

                Menu {
                    ForEach([2500, 3500, 4500, 5500], id: \.self) { rpm in
                        Button {
                            controller.setFixedRPM(rpm)
                        } label: {
                            if controller.mode == .fixed(rpm) {
                                Label("\(rpm.formatted()) RPM", systemImage: "checkmark")
                            } else {
                                Text("\(rpm.formatted()) RPM")
                            }
                        }
                    }
                } label: {
                    modeButtonLabel(
                        title: isFixed ? modeLabel : "固定转速",
                        systemImage: "gauge.with.dots.needle.67percent",
                        selected: isFixed,
                        showsChevron: true
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .disabled(controller.isBusy || controller.helperState != .enabled)
            .padding(4)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            if isManual {
                automaticRestoreRow
            }
        }
    }

    private var temperatureCurveControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.variable")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(controller.mode == .temperatureCurve ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("智能温控")
                    .font(.subheadline.weight(.medium))
                Text(temperatureCurveDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { controller.mode == .temperatureCurve },
                    set: { controller.setTemperatureCurveEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(controller.isBusy || controller.helperState != .enabled)
            .accessibilityLabel("智能温控")
            .accessibilityHint("开启后根据芯片温度动态调整风扇转速")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(controller.mode == .temperatureCurve ? 0.065 : 0.035),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var temperatureCurveDetail: String {
        guard controller.mode == .temperatureCurve,
              let temperature = controller.curveTemperatureCelsius,
              let fraction = controller.curveOutputFraction else {
            return "45° 低噪起步，85° 全速散热"
        }
        return String(format: "%.0f°C · 输出 %.0f%%", temperature, fraction * 100)
    }

    private var automaticRestoreRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("自动恢复")
                .font(.caption)

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Menu {
                    ForEach(FanController.AutomaticRestoreDuration.allCases) { duration in
                        Button {
                            controller.setAutomaticRestoreDuration(duration)
                        } label: {
                            if controller.automaticRestoreDuration == duration {
                                Label(duration.title, systemImage: "checkmark")
                            } else {
                                Text(duration.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(automaticRestoreLabel(at: context.date))
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("自动恢复时间")
            }
            .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.top, 1)
    }

    private func automaticRestoreLabel(at date: Date) -> String {
        guard let deadline = controller.automaticRestoreDeadline else {
            return controller.automaticRestoreDuration.title
        }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d 后", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d 后", minutes, seconds)
    }

    private func modeButtonLabel(
        title: String,
        systemImage: String,
        selected: Bool,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(title)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            selected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var safetyNote: some View {
        Label("目标转速会自动限制在硬件安全范围内", systemImage: "checkmark.shield")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var launchAtLoginRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("登录时启动 FanBar")
                    .font(.caption)
                if controller.launchAtLoginRequiresApproval {
                    Button("等待系统批准 · 打开设置") {
                        controller.openLoginItemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                }
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { controller.launchAtLoginEnabled },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("登录时启动 FanBar")
        }
    }

    private var unavailableState: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("当前机型未返回可识别的风扇数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var helperNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: helperNoticeIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(helperNoticeTint)
                .frame(width: 28, height: 28)
                .background(helperNoticeTint.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(helperNoticeTitle)
                    .font(.caption.weight(.semibold))
                Text(helperNoticeDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if controller.helperState == .requiresApproval {
                helperActionButton("继续", action: presentHelperAuthorizationGuide)
            } else if controller.helperState == .notRegistered {
                helperActionButton("了解", action: presentHelperAuthorizationGuide)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private func helperActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var helperNoticeIcon: String {
        switch controller.helperState {
        case .requiresApproval: "lock.open"
        case .notRegistered: "lock.shield"
        case .unavailable: "exclamationmark.triangle"
        case .enabled: "checkmark.shield"
        }
    }

    private var helperNoticeTint: Color {
        controller.helperState == .unavailable ? .red : .orange
    }

    private var helperNoticeTitle: String {
        switch controller.helperState {
        case .requiresApproval: "批准控制服务"
        case .notRegistered: "启用固定转速"
        case .unavailable: "控制服务不可用"
        case .enabled: "控制服务已启用"
        }
    }

    private var helperNoticeDetail: String {
        switch controller.helperState {
        case .requiresApproval: "在“登录项与扩展”中允许 FanBar"
        case .notRegistered: "实时监测无需权限"
        case .unavailable: "请重新安装已签名的 FanBar"
        case .enabled: "仅接受同一开发者签名的请求"
        }
    }

    private var footer: some View {
        HStack {
            Text("每 2 秒更新")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                onboardingStep = 0
                withAnimation(onboardingAnimation) {
                    hasCompletedOnboarding = false
                }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("重新查看快速开始")
            .help("快速开始")

            Button("退出 FanBar") { controller.quit() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.top, 1)
    }

    /// Advances only through the three essential concepts; advanced controls stay contextual.
    private func advanceOnboarding() {
        withAnimation(onboardingAnimation) {
            onboardingStep = min(onboardingStep + 1, 2)
        }
    }

    private func completeOnboarding() {
        withAnimation(onboardingAnimation) {
            hasCompletedOnboarding = true
        }
    }

    /// Every permission entry point starts with context before leaving FanBar.
    private func presentHelperAuthorizationGuide() {
        withAnimation(onboardingAnimation) {
            onboardingStep = 2
            hasCompletedOnboarding = false
        }
    }

    private var onboardingAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }
}
