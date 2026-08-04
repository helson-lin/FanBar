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

    private var isPreset: Bool {
        if case .preset = controller.mode { return true }
        return false
    }

    private var modeLabel: String {
        switch controller.mode {
        case .automatic: "系统"
        case .temperatureCurve: "智能温控"
        case .fixed(let rpm): "\(rpm) RPM"
        case .preset(let preset): "\(preset.title) \(preset.percentageText)"
        }
    }

    private var visibleCoolingPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visibleCoolingPresetsRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            } else {
                unavailableState
            }

            if controller.helperState != .enabled {
                helperNotice
            }

            launchAtLoginRow
            footer
        }
        .padding(16)
        .frame(width: 384)
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
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                SettingsWindowPresenter.shared.show(controller: controller)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            // Prevent AppKit from drawing a persistent focus ring around this icon-only action.
            .focusable(false)
            .accessibilityLabel("打开 FanBar 设置")
            .help("设置")

        }
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isManual ? Color.accentColor : Color.green)
                .frame(width: 5, height: 5)
            Text(modeLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
    }

    private var fanPanel: some View {
        HStack(spacing: 0) {
            ForEach(Array(controller.fans.prefix(2)).indices, id: \.self) { position in
                let fan = controller.fans[position]
                FanGauge(fan: fan)

                if position < min(controller.fans.count, 2) - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 142)
                }
            }
        }
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制模式")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Button {
                    if controller.mode != .automatic {
                        controller.setAutomatic()
                    }
                } label: {
                    modeButtonLabel(
                        title: "系统",
                        systemImage: "wand.and.stars",
                        selected: controller.mode == .automatic
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button {
                    if controller.mode != .temperatureCurve {
                        controller.setTemperatureCurveEnabled(true)
                    }
                } label: {
                    modeButtonLabel(
                        title: "智能",
                        systemImage: "thermometer.variable",
                        selected: controller.mode == .temperatureCurve
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("按芯片温度动态调整风扇转速")

                Menu {
                    Section(header: Text("散热预设")) {
                        ForEach(visibleCoolingPresets) { preset in
                            Button {
                                controller.setCoolingPreset(preset)
                            } label: {
                                if controller.mode == .preset(preset) {
                                    Label(
                                        "\(preset.title) · \(preset.percentageText)",
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Label(
                                        "\(preset.title) · \(preset.percentageText)",
                                        systemImage: preset.systemImage
                                    )
                                }
                            }
                        }
                    }

                    Section(header: Text("固定转速")) {
                        ForEach([2500, 3500, 4500, 5500], id: \.self) { rpm in
                            Button {
                                controller.setFixedRPM(rpm)
                            } label: {
                                if controller.mode == .fixed(rpm) {
                                    Label("\(rpm) RPM", systemImage: "checkmark")
                                } else {
                                    Text("\(rpm) RPM")
                                }
                            }
                        }
                    }
                } label: {
                    modeButtonLabel(
                        title: "手动",
                        systemImage: "slider.horizontal.3",
                        selected: isFixed || isPreset,
                        showsChevron: true
                    )
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("选择手动散热模式")
                .help("选择散热预设或固定转速")
            }
            .disabled(controller.isBusy || controller.helperState != .enabled)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )

            if isManual {
                automaticRestoreRow
            }
        }
    }

    private var automaticRestoreRow: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.mode == .temperatureCurve
                ? "thermometer.variable"
                : "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(manualModeDetail)
                .font(.caption)
                .font(.system(size: 12, design: .monospaced))

            Spacer()

            CountdownTimerView { date in
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
                    HStack(spacing: 7) {
                        // Display the selected restore duration directly; when active, this becomes its countdown.
                        Text(automaticRestoreValue(at: date))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 9)
                            .padding(.trailing, 7)
                            .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.045)))
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                // Keep the custom trailing chevron as the only visible menu indicator.
                .hidingSystemMenuIndicatorWhenAvailable()
                .fixedSize()
                .accessibilityLabel("自动恢复")
                .accessibilityValue(automaticRestoreAccessibilityValue(at: date))
            }
            .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.top, 1)
    }

    private var manualModeDetail: String {
        if controller.mode == .temperatureCurve,
           let temperature = controller.curveTemperatureCelsius,
           let fraction = controller.curveOutputFraction {
            return String(format: "%.0f°C → %.0f%%", temperature, fraction * 100)
        }
        return "硬件安全限制"
    }

    private func automaticRestoreValue(at date: Date) -> String {
        guard let deadline = controller.automaticRestoreDeadline else {
            return controller.automaticRestoreDuration == .never
                ? "关闭"
                : controller.automaticRestoreDuration.title
        }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func automaticRestoreAccessibilityValue(at date: Date) -> String {
        guard let deadline = controller.automaticRestoreDeadline else {
            return controller.automaticRestoreDuration == .never
                ? "已关闭"
                : "将在 \(controller.automaticRestoreDuration.title)后恢复"
        }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return "剩余 \(hours) 小时 \(minutes) 分 \(seconds) 秒"
        }
        return "剩余 \(minutes) 分 \(seconds) 秒"
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
                .font(.system(size: 13, design: .monospaced))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundColor(selected ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var launchAtLoginRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("登录时启动 FanBar")
                    .font(.caption)
                if controller.launchAtLoginRequiresApproval {
                    Button("等待系统批准 · 打开设置") {
                        controller.openLoginItemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(Color.orange)
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
        .padding(.horizontal, 6)
    }

    private var unavailableState: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.slash")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("当前机型未返回可识别的风扇数据。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var helperNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: helperNoticeIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(helperNoticeTint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(helperNoticeTint.opacity(0.1)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(helperNoticeTitle)
                    .font(.caption.weight(.semibold))
                Text(helperNoticeDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            .background(Capsule().fill(Color.primary.opacity(0.055)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundColor(Color.accentColor)
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
                .foregroundColor(.secondary)

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
            .foregroundColor(.secondary)
            .accessibilityLabel("重新查看快速开始")
            .help("快速开始")

            Button("退出 FanBar") { controller.quit() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
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

/// Timer-driven replacement for TimelineView, which was introduced after macOS 11.
private struct CountdownTimerView<Content: View>: View {
    let content: (Date) -> Content
    @State private var now = Date()

    private let timer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        content(now)
            .onReceive(timer) { now = $0 }
    }
}

private extension View {
    /// Hides Menu's AppKit indicator on macOS 12+, while preserving macOS 11 compatibility.
    @ViewBuilder
    func hidingSystemMenuIndicatorWhenAvailable() -> some View {
        if #available(macOS 12.0, *) {
            menuIndicator(.hidden)
        } else {
            self
        }
    }
}
