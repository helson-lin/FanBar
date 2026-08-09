import AppKit
import FanBarShared
import SwiftUI

struct FanMenu: View {
    @ObservedObject var controller: FanController
    @AppStorage("fanbar.onboarding.v1.completed")
    private var hasCompletedOnboarding = false
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visibleCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
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
        case .automatic: fanBarText("系统", "Automatic")
        case .temperatureCurve: fanBarText("智能温控", "Smart cooling")
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
            .accessibilityLabel(fanBarText("打开 FanBar 设置", "Open FanBar Settings"))
            .help(fanBarText("设置", "Settings"))

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
            Text(fanBarText("控制模式", "Control mode"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Button {
                    if controller.mode != .automatic {
                        controller.setAutomatic()
                    }
                } label: {
                    modeButtonLabel(
                        title: fanBarText("系统", "Automatic"),
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
                        title: fanBarText("智能", "Smart"),
                        systemImage: "thermometer.variable",
                        selected: controller.mode == .temperatureCurve
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(fanBarFormat(
                    "按芯片温度动态调速 · 当前曲线：%@",
                    "Adjust fan speed from chip temperature · Curve: %@",
                    controller.curveProfile.displayName
                ))

                Menu {
                    Section(header: Text(fanBarText("散热预设", "Cooling presets"))) {
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

                    Section(header: Text(fanBarText("固定转速", "Fixed RPM"))) {
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
                        title: fanBarText("手动", "Manual"),
                        systemImage: "slider.horizontal.3",
                        selected: isFixed || isPreset,
                        showsChevron: true
                    )
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(fanBarText("选择手动散热模式", "Choose a manual cooling mode"))
                .help(fanBarText("选择散热预设或固定转速", "Choose a cooling preset or fixed RPM"))
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
                .accessibilityLabel(fanBarText("自动恢复", "Automatic restore"))
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
            return fanBarFormat(
                "%@ · %.0f°C → %.0f%%",
                "%@ · %.0f°C → %.0f%%",
                controller.curveProfile.displayName,
                temperature,
                fraction * 100
            )
        }
        return fanBarText("硬件安全限制", "Hardware safety limits")
    }

    private func automaticRestoreValue(at date: Date) -> String {
        guard let deadline = controller.automaticRestoreDeadline else {
            return controller.automaticRestoreDuration == .never
                ? fanBarText("关闭", "Off")
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
                ? fanBarText("已关闭", "Off")
                : fanBarFormat(
                    "将在 %@后恢复",
                    "Restores after %@",
                    controller.automaticRestoreDuration.title
                )
        }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return fanBarFormat(
                "剩余 %d 小时 %d 分 %d 秒",
                "%d h %d m %d s remaining",
                hours,
                minutes,
                seconds
            )
        }
        return fanBarFormat(
            "剩余 %d 分 %d 秒",
            "%d m %d s remaining",
            minutes,
            seconds
        )
    }

    private func modeButtonLabel(
        title: String,
        systemImage: String,
        selected: Bool,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
                .font(.system(size: 13, design: .monospaced))
                // Keep localized mode names on one line; English "Automatic"
                // needs to remain readable inside the compact three-way control.
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundColor(selected ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
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
                Text(fanBarText("登录时启动 FanBar", "Launch FanBar at login"))
                    .font(.caption)
                if controller.launchAtLoginRequiresApproval {
                    Button(fanBarText("等待系统批准 · 打开设置", "Waiting for approval · Open Settings")) {
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
            .accessibilityLabel(fanBarText("登录时启动 FanBar", "Launch FanBar at login"))
        }
        .padding(.horizontal, 6)
    }

    private var unavailableState: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.slash")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(fanBarText(
                "当前机型未返回可识别的风扇数据。",
                "This Mac did not return readable fan data."
            ))
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
                helperActionButton(fanBarText("继续", "Continue"), action: presentHelperAuthorizationGuide)
            } else if controller.helperState == .notRegistered {
                helperActionButton(fanBarText("了解", "Learn more"), action: presentHelperAuthorizationGuide)
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
        case .requiresApproval: fanBarText("批准控制服务", "Approve control service")
        case .notRegistered: fanBarText("启用固定转速", "Enable fan control")
        case .unavailable: fanBarText("控制服务不可用", "Control service unavailable")
        case .enabled: fanBarText("控制服务已启用", "Control service enabled")
        }
    }

    private var helperNoticeDetail: String {
        switch controller.helperState {
        case .requiresApproval: fanBarText("在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions")
        case .notRegistered: fanBarText("实时监测无需权限", "Live monitoring does not need permission")
        case .unavailable: fanBarText("请重新安装已签名的 FanBar", "Reinstall the signed FanBar app")
        case .enabled: fanBarText("仅接受同一开发者签名的请求", "Only requests signed by the same developer are accepted")
        }
    }

    private var footer: some View {
        HStack {
            Text(fanBarText("每 2 秒更新", "Updates every 2 seconds"))
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
            .accessibilityLabel(fanBarText("重新查看快速开始", "Replay quick start"))
            .help(fanBarText("快速开始", "Quick start"))

            Button(fanBarText("退出 FanBar", "Quit FanBar")) { controller.quit() }
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
