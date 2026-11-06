// swiftlint:disable file_length type_body_length
// Legacy size debt: split this file before removing the disable above.
import AppKit
import Combine
import FanBarShared
import SwiftUI

/// A flat menu panel with shared borders between its fan and resource columns.
struct FanMenu: View {
    @ObservedObject var controller: FanController
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var menuCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.focusedMenuBarResource) private var focusedMenuBarResource
    @AppStorage(PanelAnimationPreferences.preferenceKey)
    private var panelAnimationEnabled = true
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @AppStorage(AppIconChoice.preferenceKey)
    private var appIconRawValue = AppIconChoice.classic.rawValue

    @State private var contentHeight: CGFloat = 580
    @State private var chartRange: TemperatureChartRange = .tenMinutes
    @State private var expandedResource: PanelResourceList.Resource?
    @State private var fixedSliderRPM = 0.0
    @State private var isDraggingFixedSlider = false

    /// Width of the v2 panel.
    static let panelWidth: CGFloat = 368
    private static let padding: CGFloat = 16

    private enum ModeOption: Hashable {
        case automatic
        case preset(CoolingPresetID)
        case fixed
    }

    private var palette: PanelPalette { PanelPalette(colorScheme: colorScheme) }

    private var animatesPanel: Bool {
        panelAnimationEnabled && !reduceMotion
    }

    private var slideInTransition: AnyTransition {
        animatesPanel ? .opacity.combined(with: .move(edge: .top)) : .identity
    }

    private var isManual: Bool {
        controller.mode != .automatic
    }

    private var isFixed: Bool {
        if case .fixed = controller.mode { return true }
        return false
    }

    private var currentFixedRPM: Int? {
        if case .fixed(let rpm) = controller.mode { return rpm }
        return nil
    }

    private var isShowingModeFailureBanner: Bool {
        controller.modeActionFeedback?.kind == .failure
    }

    private var visibleCoolingPresets: [CoolingPresetSummary] {
        let all = controller.allPresets
        return CoolingPresetPreferences.presets(
            from: menuCoolingPresetsRawValue,
            available: all.map(\.id)
        ).compactMap { id in all.first { $0.id == id } }
    }

    private var focus: ThermalFocus? {
        ThermalFocus.from(controller.temperatureHistory.last)
    }

    private var level: ThermalLevel {
        focus?.level ?? .normal
    }

    private var fanWord: String {
        switch controller.fans.count {
        case 1: fanBarText("单风扇", "Single fan")
        case 2: fanBarText("双风扇", "Dual fans")
        default: fanBarFormat("%d 个风扇", "%d fans", controller.fans.count)
        }
    }

    private var modeName: String {
        switch controller.mode {
        case .automatic: fanBarText("系统", "Automatic")
        case .temperatureCurve: controller.presetTitle(for: controller.curveCoolingPreset)
        case .fixed: fanBarText("固定", "Fixed")
        }
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical, showsIndicators: false) {
                panelContent
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { updateContentHeight(proxy.size.height) }
                            .onChange(of: proxy.size.height) { updateContentHeight($0) }
                    })
            }
            .onAppear {
                if focusedMenuBarResource != nil { scroll.scrollTo("resources", anchor: .center) }
            }
            .onChange(of: focusedMenuBarResource) { resource in
                scroll.scrollTo(resource == nil ? "panelTop" : "resources", anchor: resource == nil ? .top : .center)
            }
        }
        .frame(width: Self.panelWidth, height: min(contentHeight, max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 70)))
        .background(PanelGlassBackground())
    }

    /// Measure the final intrinsic height without interpolation. The popover grows
    /// downward to fit disk details; scrolling is reserved for the screen-height cap.
    private func updateContentHeight(_ measuredHeight: CGFloat) {
        let height = measuredHeight.rounded(.up)
        guard height.isFinite, height > 0, abs(height - contentHeight) >= 1 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { contentHeight = height }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .id("panelTop")
                .padding(.horizontal, Self.padding)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if let focus, focus.level == .hot {
                overheatBanner(focus)
                    .padding(.horizontal, Self.padding)
                    .padding(.bottom, 12)
                    .transition(slideInTransition)
            }

            if controller.isAvailable, !controller.fans.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(controller.fans.enumerated()), id: \.element.id) { index, fan in
                            PanelFanReadout(fan: fan, isSingleFan: controller.fans.count == 1)
                                .padding(.leading, index > 0 ? 12 : 0)
                                .padding(.trailing, index < controller.fans.count - 1 ? 12 : 0)
                                .frame(width: (Self.panelWidth - Self.padding * 2) / (controller.fans.count == 1 ? 1 : 2))
                        }
                    }
                }
                .padding(.horizontal, Self.padding)
                .padding(.bottom, 8)
            } else if controller.isAvailable {
                Text(fanBarText(
                    "硬件接口未报告风扇，控制能力尚未验证",
                    "No fans reported; control is not yet verified"
                ))
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
                .padding(.horizontal, Self.padding)
                .padding(.bottom, 12)
            } else {
                unavailableState
                    .padding(.horizontal, Self.padding)
                    .padding(.bottom, 12)
            }

            if controller.helperState != .enabled {
                helperNotice
                    .padding(.horizontal, Self.padding)
                    .padding(.bottom, 12)
                    .transition(slideInTransition)
            }

            if controller.isAvailable, !controller.fans.isEmpty {
                modeSection
                    .padding(.horizontal, Self.padding)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }

            divider

            PanelResourceList(
                usage: controller.usage,
                thermal: controller.temperatureHistory.last,
                cpuHistory: controller.cpuHistory,
                gpuHistory: controller.gpuHistory,
                animates: animatesPanel,
                expanded: $expandedResource
            )
            .padding(.horizontal, Self.padding)
            .id("resources")

            if controller.isAvailable {
                divider
                TemperatureChart(samples: controller.temperatureHistory, range: $chartRange,
                                 alertThreshold: controller.highTemperatureThresholdCelsius)
                    .padding(.horizontal, Self.padding)
                    .padding(.vertical, PanelLayout.rowVerticalPadding)
            }

            footer
        }
        .frame(width: Self.panelWidth)
        .animation(animatesPanel ? .easeOut(duration: 0.2) : nil, value: focus?.level == .hot)
        .animation(animatesPanel ? .easeOut(duration: 0.2) : nil, value: controller.helperState != .enabled)
    }

    private var divider: some View {
        PanelDivider()
            .padding(.horizontal, Self.padding)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: (AppIconChoice(rawValue: appIconRawValue) ?? .classic).image
                  ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("FanBar")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if controller.isAvailable, !controller.fans.isEmpty {
                    subtitle
                }
            }

            Spacer(minLength: 8)

            PanelIconButton(systemImage: "gearshape") {
                SettingsWindowPresenter.shared.show(controller: controller)
            }
            .accessibilityLabel(fanBarText("打开 FanBar 设置", "Open FanBar Settings"))
            .help(fanBarText("设置", "Settings"))
            // Optically align the glyph, not its hover well, with the content edge.
            .padding(.trailing, -6)
        }
    }

    /// One sentence that answers "how is it right now", naming the part when one is past its limit.
    private var headerTitle: String {
        guard controller.isAvailable else { return controller.message }
        guard let focus, focus.isAlert else { return fanBarText("散热良好", "Cooling normally") }
        let part = focus.part.name
        if focus.level == .warm {
            return fanBarFormat("%@温度偏高", "%@ is running warm", part)
        }
        // macOS raises fan speed for hot chips on its own; a hot SSD or battery it may not.
        let macOSRespondsByItself = controller.mode == .automatic && [.cpu, .gpu].contains(focus.part)
        return macOSRespondsByItself
            ? fanBarFormat("%@温度很高 · 系统已提速", "%@ is very hot · macOS has sped up the fans", part)
            : fanBarFormat("%@温度很高", "%@ is very hot", part)
    }

    /// Scoped to the fans: their state and who drives them, plus the restore countdown while FanBar does.
    private var subtitle: some View {
        let isAlert = focus?.isAlert == true
        return HStack(spacing: 6) {
            Group {
                if level == .hot {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(palette.hot)
                } else {
                    Circle()
                        .fill(palette.color(for: level))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Text(isAlert ? headerTitle : calmSubtitle)
                .fontWeight(isAlert ? .semibold : .regular)
                .foregroundColor(isAlert ? (level == .hot ? palette.hot : palette.warmInk) : palette.secondaryText)
                .lineLimit(1)

            if isManual {
                restoreMenu
            }
        }
        .font(.system(size: 11))
        .foregroundColor(palette.secondaryText)
    }

    /// "风扇正常 · macOS 控制 · CPU 65°": names what is normal and who is in control.
    private var calmSubtitle: String {
        let owner = isManual ? fanBarText("FanBar 控制", "FanBar in control") : fanBarText("macOS 控制", "macOS in control")
        var parts = [fanBarText("风扇正常", "Fans normal"), owner]
        if !isManual, let focus {
            parts.append("\(focus.part.name) \(Int(focus.celsius.rounded()))°")
        }
        return parts.joined(separator: " · ")
    }

    private var restoreMenu: some View {
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
                Text("· \(restoreSummary(at: date))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(palette.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .hidingSystemMenuIndicatorWhenAvailable()
            .fixedSize()
            .accessibilityLabel(fanBarText("自动恢复", "Automatic restore"))
            .accessibilityValue(automaticRestoreAccessibilityValue(at: date))
        }
    }

    private func restoreSummary(at date: Date) -> String {
        if controller.automaticRestoreDeadline == nil, controller.automaticRestoreDuration == .never {
            return fanBarText("不自动恢复", "No auto restore")
        }
        return fanBarFormat("%@ 后恢复", "restores in %@", automaticRestoreValue(at: date))
    }

    // MARK: Fans

    /// What FanBar is asking this fan to do: nil in Automatic, where macOS
    /// decides. Curve targets use the helper's own rule; fixed targets are
    /// clamped to the fan's range as the helper does.
    private func targetRPM(_ fan: FanReading) -> Int? {
        switch controller.mode {
        case .automatic:
            return nil
        case .fixed(let requested):
            return min(max(requested, fan.minimumRPM), fan.maximumRPM)
        case .temperatureCurve:
            guard let fraction = controller.curveOutputFraction else { return nil }
            return Int(FanCoolingTarget.targetRPM(
                fraction: fraction,
                minimum: Float(fan.minimumRPM),
                maximum: Float(fan.maximumRPM)
            ))
        }
    }

    // MARK: Modes

    private var modeOptions: [(id: ModeOption, title: String)] {
        [(ModeOption.automatic, fanBarText("自动", "Auto"))]
            + visibleCoolingPresets.map { (ModeOption.preset($0.id), $0.title) }
            + [(ModeOption.fixed, fanBarText("固定", "Fixed"))]
    }

    private var selectedMode: ModeOption {
        switch controller.mode {
        case .automatic: .automatic
        case .temperatureCurve: .preset(controller.curveCoolingPreset)
        case .fixed: .fixed
        }
    }

    private func modeIcon(_ option: ModeOption) -> String? {
        switch option {
        case .automatic: "arrow.triangle.2.circlepath"
        case .preset(let id): controller.allPresets.first { $0.id == id }?.systemImage
        case .fixed: "lock"
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSegmentedControl(options: modeOptions, selection: selectedMode, systemImage: modeIcon) { option in
                select(option)
            }
            .disabled(controller.isBusy || controller.helperState != .enabled)
            .animation(
                animatesPanel ? .spring(response: 0.3, dampingFraction: 1) : .easeOut(duration: 0.15),
                value: selectedMode
            )
            // The failure banner covers the strip without changing popover size;
            // hide the strip (not remove it) so its labels can't show through.
            .opacity(isShowingModeFailureBanner ? 0 : 1)
            .allowsHitTesting(!isShowingModeFailureBanner)
            .accessibilityHidden(isShowingModeFailureBanner)
            .overlay(
                Group {
                    if let feedback = controller.modeActionFeedback, feedback.kind == .failure {
                        modeActionFeedbackBanner(feedback)
                            .transition(.opacity)
                    }
                }
            )
            .animation(animatesPanel ? .easeOut(duration: 0.15) : nil, value: isShowingModeFailureBanner)
            // Floats in the gap above the strip: an overlay is excluded from fitting-size
            // calculation, keeping the popover frame pixel-stable while a request is in flight.
            .overlay(modeProgressIndicator.offset(y: -18), alignment: .topTrailing)

            if isFixed, let range = controller.fixedRPMRange {
                fixedSlider(range: range)
                    .padding(.top, 10)
            }

            // Automatic needs no caption: the selected "自动" already says macOS is driving.
            if isManual {
                modeLine
                    .padding(.top, 8)
            }
        }
    }

    private func select(_ option: ModeOption) {
        switch option {
        case .automatic:
            if controller.mode != .automatic { controller.setAutomatic() }
        case .preset(let id):
            controller.setCoolingPreset(id)
        case .fixed:
            guard !isFixed, let range = controller.fixedRPMRange else { return }
            let preferred = controller.customFixedRPM
                ?? FanController.fixedRPMPresets.first(where: range.contains)
                ?? range.lowerBound
            controller.setFixedRPM(min(max(preferred, range.lowerBound), range.upperBound))
        }
    }

    /// One RPM for every fan. The request goes out when the drag ends, so a
    /// slide does not flood the helper with intermediate targets.
    private func fixedSlider(range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Slider(
                value: $fixedSliderRPM,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 100
            ) { editing in
                isDraggingFixedSlider = editing
                guard !editing else { return }
                let rpm = min(max(Int(fixedSliderRPM.rounded()), range.lowerBound), range.upperBound)
                if rpm != currentFixedRPM { controller.setCustomFixedRPM(rpm) }
            }
            .tintedWhenAvailable(palette.accent)
            .disabled(controller.isBusy || controller.helperState != .enabled)
            .accessibilityLabel(fanBarText("固定转速", "Fixed RPM"))

            Text("\(FanBarNumberFormatter.grouped(Int(fixedSliderRPM.rounded()))) RPM")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(minWidth: 74, alignment: .trailing)
        }
        .onAppear { syncFixedSlider() }
        .onChange(of: currentFixedRPM) { _ in
            if !isDraggingFixedSlider { syncFixedSlider() }
        }
    }

    private func syncFixedSlider() {
        if let rpm = currentFixedRPM { fixedSliderRPM = Double(rpm) }
    }

    /// How the selected mode is steering the fans, said once.
    private var modeLine: some View {
        HStack(spacing: 8) {
            Text(Self.modeDescription(
                for: controller.mode,
                sensor: controller.curveProfile.sensor,
                reading: controller.temperatureHistory.last,
                fanCount: controller.fans.count
            ))
                .lineLimit(1)
            Spacer(minLength: 4)
            modeTarget
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundColor(palette.secondaryText)
    }

    static func modeDescription(
        for mode: FanController.Mode,
        sensor: FanCurveSensor,
        reading: ThermalReading?,
        fanCount: Int
    ) -> String {
        switch mode {
        case .automatic:
            return fanBarText("交由 macOS 自动调节", "Controlled by macOS")
        case .temperatureCurve:
            return sensor.controlDescription(for: reading)
        case .fixed:
            return fanCount > 1
                ? fanBarText("双风扇保持同一转速", "Fans hold the same speed")
                : fanBarText("风扇保持固定转速", "The fan holds a fixed speed")
        }
    }

    @ViewBuilder private var modeTarget: some View {
        if case .temperatureCurve = controller.mode {
            let targets = controller.fans.prefix(2).compactMap(targetRPM)
            if !targets.isEmpty {
                Text(fanBarText("目标", "Target") + " ")
                    + Text(targets.map(FanBarNumberFormatter.grouped).joined(separator: " / "))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    + Text(" RPM")
            }
        }
    }

    private var inProgressFeedback: FanController.ModeActionFeedback? {
        guard let feedback = controller.modeActionFeedback,
              feedback.kind == .inProgress else { return nil }
        return feedback
    }

    /// Always laid out at a fixed height and faded in place, so a request in
    /// flight never re-measures the panel.
    private var modeProgressIndicator: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
            Text(inProgressFeedback?.message ?? " ")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 16)
        .clipped()
        .opacity(inProgressFeedback == nil ? 0 : 1)
        .animation(animatesPanel ? .easeOut(duration: 0.15) : nil, value: inProgressFeedback == nil)
        .accessibilityHidden(inProgressFeedback == nil)
    }

    // swiftlint:disable:next function_body_length
    private func modeActionFeedbackBanner(
        _ feedback: FanController.ModeActionFeedback
    ) -> some View {
        let isFailure = feedback.kind == .failure
        let tint = isFailure ? palette.hot : palette.accent

        return HStack(alignment: .center, spacing: 9) {
            Group {
                if isFailure {
                    Image(systemName: "exclamationmark.circle.fill")
                } else {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            // The banner overlays the fixed-height control strip, so it must not grow.
            Text(feedback.message)
                .font(.caption)
                .foregroundColor(isFailure ? .primary : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(feedback.message)

            if isFailure {
                if feedback.offersHelperSettings {
                    Button(fanBarText("打开系统设置", "Open System Settings")) {
                        controller.openHelperSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundColor(palette.accent)
                    .fixedSize()
                    .accessibilityHint(fanBarText(
                        "前往“登录项与扩展”批准控制服务",
                        "Approve the control service in Login Items & Extensions"
                    ))
                }

                Button {
                    controller.clearModeActionFeedback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityLabel(fanBarText("关闭错误提示", "Dismiss error"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(isFailure ? 0.09 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(isFailure ? 0.22 : 0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isFailure
                ? fanBarText("控制模式切换失败", "Control mode switch failed")
                : fanBarText("正在切换控制模式", "Switching control mode")
        )
        .accessibilityValue(feedback.message)
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

    // MARK: States and notices

    private static let maximumCoolingPreset = CoolingPresetID.builtIn(.extreme)

    /// Only for a part past its hot limit: what is happening, and one way to act on it.
    private func overheatBanner(_ focus: ThermalFocus) -> some View {
        HStack(spacing: 10) {
            Text(overheatDetail(focus))
                .font(.system(size: 11))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canBoostCooling {
                Button {
                    controller.setCoolingPreset(Self.maximumCoolingPreset)
                } label: {
                    Text(fanBarFormat(
                        "切到%@",
                        "Switch to %@",
                        controller.presetTitle(for: Self.maximumCoolingPreset)
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.surface)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PanelDimButtonStyle())
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.hot.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
    }

    private var canBoostCooling: Bool {
        guard controller.helperState == .enabled, !controller.isBusy else { return false }
        if case .temperatureCurve = controller.mode, controller.curveCoolingPreset == Self.maximumCoolingPreset {
            return false
        }
        return true
    }

    private func overheatDetail(_ focus: ThermalFocus) -> String {
        let reading = fanBarFormat(
            "%@ %d°，已超过 %d° 告警线。",
            "%@ is at %d°, past its %d° limit.",
            focus.part.name,
            Int(focus.celsius.rounded()),
            Int(focus.part.hotThreshold)
        )
        guard controller.mode == .automatic else { return reading }
        return reading + fanBarText("当前为自动模式，macOS 可能正在降频。", " macOS is in control and may be throttling.")
    }

    private var unavailableState: some View {
        HStack(spacing: 10) {
            Image(systemName: FanBarSymbols.fanSlash)
                .font(.system(size: 14))
                .foregroundColor(palette.secondaryText)
            Text(fanBarText(
                "当前机型未返回可识别的风扇数据。",
                "This Mac did not return readable fan data."
            ))
            .font(.system(size: 11))
            .foregroundColor(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PanelLayout.rowVerticalPadding)
    }

    private var helperNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: controller.helperState.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(helperNoticeTint)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.helperState.noticeTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(controller.helperState.noticeDetail)
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle = controller.helperState.actionTitle {
                    helperActionButton(actionTitle, action: controller.performHelperAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.track)
        )
        .accessibilityElement(children: .contain)
    }

    private func helperActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.surface)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PanelDimButtonStyle())
        // A custom-drawn button; suppress the persistent AppKit focus ring after clicks.
        .fixedSize()
    }

    private var helperNoticeTint: Color {
        controller.helperState == .unavailable ? palette.hot : palette.secondaryText
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            PanelTextButton(action: openActivityMonitor) {
                Text(fanBarText("活动监视器", "Activity Monitor"))
            }

            Spacer(minLength: 8)

            PanelIconButton(systemImage: "questionmark.circle", size: 22) {
                OnboardingWindowPresenter.shared.show(controller: controller)
            }
            .accessibilityLabel(fanBarText("重新查看快速开始", "Replay quick start"))
            .help(fanBarText("快速开始", "Quick start"))

            PanelTextButton(action: controller.quit) {
                HStack(spacing: 4) {
                    Text(fanBarText("退出", "Quit"))
                    Text("⌘Q")
                        .foregroundColor(palette.tertiaryText)
                }
            }
            .keyboardShortcut("q")
            .accessibilityLabel(fanBarText("退出 FanBar", "Quit FanBar"))
        }
        // Text buttons carry a 7pt hover inset; pull it out so labels sit on the content edge.
        .padding(.horizontal, Self.padding - 7)
        .padding(.vertical, 10)
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A borderless icon button that shows the well on hover.
private struct PanelIconButton: View {
    let systemImage: String
    var size: CGFloat = 26
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size > 24 ? 14 : 12))
                .foregroundColor(isHovered ? .primary : palette.secondaryText)
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PanelWellButtonStyle(cornerRadius: 7, isHovered: isHovered))
        // Prevent AppKit from drawing a persistent focus ring around this icon-only action.
        .onHover { isHovered = $0 }
    }
}

/// A small text action in the footer that shows the well on hover.
private struct PanelTextButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        Button(action: action) {
            label()
                .font(.system(size: 11))
                .foregroundColor(isHovered ? .primary : palette.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PanelWellButtonStyle(cornerRadius: 6, isHovered: isHovered))
        .onHover { isHovered = $0 }
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

    /// Accent-colors controls on macOS 12+; macOS 11 keeps the system accent.
    @ViewBuilder
    func tintedWhenAvailable(_ color: Color) -> some View {
        if #available(macOS 12.0, *) {
            tint(color)
        } else {
            self
        }
    }
}
