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
    @AppStorage(PanelAnimationPreferences.preferenceKey)
    private var panelAnimationEnabled = true
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @AppStorage(AppIconChoice.preferenceKey)
    private var appIconRawValue = AppIconChoice.classic.rawValue
    @AppStorage(SupportPrompt.firstUseKey)
    private var supportPromptFirstUse = 0.0
    @AppStorage(SupportPrompt.dismissedKey)
    private var isSupportPromptDismissed = false

    @State private var contentHeight: CGFloat = 580
    @State private var chartRange: TemperatureChartRange = .tenMinutes
    @State private var expandedResource: PanelResourceList.Resource?
    @State private var fixedSliderRPM = 0.0
    @State private var isDraggingFixedSlider = false
    @State private var isShowingFailureDetail = false

    /// Width of the v2 panel.
    static let panelWidth: CGFloat = 368
    /// The panel never grows past the screen; layout tests raise this so a
    /// short CI display cannot cap the height they measure.
    static var visibleScreenHeight: () -> CGFloat = { NSScreen.main?.visibleFrame.height ?? 800 }
    static let padding: CGFloat = 16
    static let headerIconSize: CGFloat = 32
    static let headerSpacing: CGFloat = 10
    static let headerSpacerMinimum: CGFloat = 8
    static let settingsButtonSize: CGFloat = 26
    /// The settings glyph, not its hover well, lines up with the content edge.
    static let settingsButtonOverhang: CGFloat = 6

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

    private var isShowingSupportPrompt: Bool {
        SupportPrompt.shouldShow(
            firstUse: supportPromptFirstUse,
            dismissed: isSupportPromptDismissed,
            now: Date(),
            isShowingOtherNotice: focus?.level == .hot || controller.helperState != .enabled || isShowingModeFailureBanner
        )
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

    // MARK: Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            panelContent
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateContentHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { updateContentHeight($0) }
                })
        }
        .frame(width: Self.panelWidth, height: min(contentHeight, max(240, Self.visibleScreenHeight() - 70)))
        .background(PanelGlassBackground())
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
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

            if controller.isAvailable {
                divider
                TemperatureChart(samples: controller.temperatureHistory, range: $chartRange,
                                 alertThreshold: controller.highTemperatureThresholdCelsius)
                    .padding(.horizontal, Self.padding)
                    .padding(.vertical, PanelLayout.rowVerticalPadding)
            }

            if isShowingSupportPrompt {
                SupportPromptRow(
                    onSupport: {
                        NSWorkspace.shared.open(FanBarLinks.donation)
                        isSupportPromptDismissed = true
                    },
                    onDismiss: { isSupportPromptDismissed = true }
                )
                .padding(.horizontal, Self.padding)
                .padding(.top, 4)
            }

            footer
        }
        .frame(width: Self.panelWidth)
        .onAppear {
            if supportPromptFirstUse == 0 { supportPromptFirstUse = Date().timeIntervalSince1970 }
        }
        .animation(animatesPanel ? .easeOut(duration: 0.2) : nil, value: focus?.level == .hot)
        .animation(animatesPanel ? .easeOut(duration: 0.2) : nil, value: controller.helperState != .enabled)
    }

    private var divider: some View {
        PanelDivider()
            .padding(.horizontal, Self.padding)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Self.headerSpacing) {
            Image(nsImage: (AppIconChoice(rawValue: appIconRawValue) ?? .classic).image
                  ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: Self.headerIconSize, height: Self.headerIconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("FanBar")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if controller.isAvailable, !controller.fans.isEmpty {
                    subtitle
                }
            }

            Spacer(minLength: Self.headerSpacerMinimum)

            PanelIconButton(systemImage: "gearshape", size: Self.settingsButtonSize) {
                SettingsWindowPresenter.shared.show(controller: controller)
            }
            .accessibilityLabel(fanBarText("打开 FanBar 设置", "Open FanBar Settings"))
            .help(fanBarText("设置", "Settings"))
            // Optically align the glyph, not its hover well, with the content edge.
            .padding(.trailing, -Self.settingsButtonOverhang)
        }
    }

    /// One sentence that answers "how is it right now", naming the part when one is past its limit.
    static func alertStatusParts(_ focus: ThermalFocus, mode: FanController.Mode) -> [String] {
        let part = focus.part.name
        if focus.level == .warm {
            return [fanBarFormat("%@温度偏高", "%@ is running warm", part)]
        }
        // macOS raises fan speed for hot chips on its own; a hot SSD or battery it may not.
        guard mode == .automatic, [.cpu, .gpu].contains(focus.part) else {
            return [fanBarFormat("%@温度很高", "%@ is very hot", part)]
        }
        return [fanBarFormat("%@温度很高", "%@ is very hot", part), fanBarText("系统已提速", "macOS has sped up the fans")]
    }

    /// Scoped to the fans: their state and who drives them, plus the restore countdown while FanBar does.
    private var subtitle: some View {
        let isAlert = focus?.isAlert == true
        let parts = isAlert
            ? focus.map { Self.alertStatusParts($0, mode: controller.mode) } ?? []
            : Self.calmStatusParts(isManual: isManual, focus: focus)
        let indicatorWidth: CGFloat = level == .hot ? Self.hotIndicatorWidth : Self.calmIndicatorWidth
        let weight: NSFont.Weight = isAlert ? .semibold : .regular
        let trailingWidth = isManual ? Self.restoreMenuWidth : 0
        let width = PanelHeaderStatus.textWidth(indicatorWidth: indicatorWidth)
        let lines = PanelHeaderStatus.lines(parts, weight: weight, trailingWidth: trailingWidth, fitting: width)
        let restoreInline = PanelHeaderStatus.trailingFits(
            after: lines, weight: weight, trailingWidth: trailingWidth, fitting: width
        )
        return HStack(alignment: .top, spacing: PanelHeaderStatus.indicatorSpacing) {
            Group {
                if level == .hot {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(palette.hot)
                } else {
                    Circle()
                        .fill(palette.color(for: level))
                        .frame(width: Self.calmIndicatorWidth, height: Self.calmIndicatorWidth)
                }
            }
            // Centered on the first line when the status wraps.
            .frame(height: Self.statusLineHeight)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: PanelHeaderStatus.indicatorSpacing) {
                        Text(line)
                            .fontWeight(isAlert ? .semibold : .regular)
                            .foregroundColor(isAlert ? (level == .hot ? palette.hot : palette.warmInk) : palette.secondaryText)
                            .lineLimit(1)
                        if isManual, restoreInline, index == lines.count - 1 {
                            restoreMenu(inline: true)
                        }
                    }
                }
                if isManual, !restoreInline {
                    restoreMenu(inline: false)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .font(.system(size: PanelHeaderStatus.fontSize))
        .foregroundColor(palette.secondaryText)
    }

    private static let calmIndicatorWidth: CGFloat = 6
    private static let hotIndicatorWidth: CGFloat = 12
    private static let statusLineHeight: CGFloat = 14

    /// The countdown ticks every second, so the wrap decision reserves its widest text instead.
    static var restoreMenuWidth: CGFloat {
        [fanBarFormat("%@ 后恢复", "restores in %@", "8:88:88"), fanBarText("不自动恢复", "No auto restore")]
            .map { PanelHeaderStatus.measure("· \($0)", monospacedDigits: true) }
            .max() ?? 0
    }

    /// "风扇正常 · macOS 控制 · CPU 65°": names what is normal and who is in control.
    static func calmStatusParts(isManual: Bool, focus: ThermalFocus?) -> [String] {
        let owner = isManual ? fanBarText("FanBar 控制", "FanBar in control") : fanBarText("macOS 控制", "macOS in control")
        var parts = [fanBarText("风扇正常", "Fans normal"), owner]
        if !isManual, let focus {
            parts.append("\(focus.part.headerName) \(Int(focus.celsius.rounded()))°")
        }
        return parts
    }

    /// Inline it follows the status after " · "; on its own line it starts like a sentence.
    private func restoreMenu(inline: Bool) -> some View {
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
                Text(inline ? "· \(restoreSummary(at: date))" : Self.sentenceCase(restoreSummary(at: date)))
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

    private static func sentenceCase(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
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
            .disabled(controller.isBusy || controller.helperState != .enabled || controller.manualControlUnsupported)
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

            if controller.manualControlUnsupported {
                unsupportedNote
            } else if controller.controlNotice != nil {
                controlNoticeRow
            }
        }
        .animation(animatesPanel ? .easeOut(duration: 0.2) : .easeOut(duration: 0.15), value: controller.controlNotice)
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

    /// What failed, whether the fans are safe, one way to recover, and the
    /// raw error behind the info button. Overlays the strip, so it never resizes the panel.
    private func modeActionFeedbackBanner(
        _ feedback: FanController.ModeActionFeedback
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: feedback.recovery == .openHelperSettings ? "powerplug" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.hot)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(feedback.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                if let safety = feedback.safety {
                    Text(safety)
                        .font(.system(size: 11, weight: feedback.isRisk ? .medium : .regular).monospacedDigit())
                        .foregroundColor(feedback.isRisk ? palette.hot : palette.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)

            failureActions(feedback)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Two lines need more than the strip's height; reach into the gaps
        // around it instead of growing the panel.
        .padding(.vertical, -5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.raised)
                .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                .padding(.vertical, -5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
                .padding(.vertical, -5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fanBarText("控制模式切换失败", "Control mode switch failed"))
        .onAppear { Self.announce([feedback.title, feedback.safety].compactMap { $0 }.joined(separator: "\n")) }
    }

    /// One recovery button, the details button, and dismiss.
    @ViewBuilder
    private func failureActions(_ feedback: FanController.ModeActionFeedback) -> some View {
        if let recovery = feedback.recovery {
            Button {
                controller.performRecovery(recovery)
            } label: {
                Text(Self.recoveryTitle(recovery))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.surface)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(PanelDimButtonStyle())
            .fixedSize()
            .disabled(controller.isBusy)
        }

        if feedback.detail != nil {
            PanelIconButton(systemImage: "info.circle", size: 22) {
                isShowingFailureDetail.toggle()
            }
            .accessibilityLabel(fanBarText("错误详情", "Error details"))
            .popover(isPresented: $isShowingFailureDetail, arrowEdge: .bottom) {
                failureDetail(feedback)
            }
        }

        PanelIconButton(systemImage: "xmark", size: 22) {
            controller.clearModeActionFeedback()
        }
        .accessibilityLabel(fanBarText("关闭提示", "Dismiss"))
    }

    static func recoveryTitle(_ recovery: FanController.ModeActionFeedback.Recovery) -> String {
        switch recovery {
        case .retry: fanBarText("重试", "Try again")
        case .openHelperSettings: fanBarText("打开系统设置", "Open System Settings")
        case .enableHelper: fanBarText("启用控制服务", "Turn on control service")
        case .chooseTemperatureSource: fanBarText("换温度来源", "Change source")
        }
    }

    /// The raw error, with enough context to paste into a bug report.
    private func failureDetail(_ feedback: FanController.ModeActionFeedback) -> some View {
        let report = Self.failureReport(feedback, device: controller.compatibilityDevice)
        return VStack(alignment: .leading, spacing: 8) {
            Text(fanBarText("错误详情", "Error details"))
                .font(.system(size: 12, weight: .semibold))
            Text(report)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.track))
            HStack {
                Text(fanBarText("反馈问题时附上这段文字", "Include this when reporting a problem"))
                    .font(.system(size: 11))
                    .foregroundColor(palette.secondaryText)
                Spacer(minLength: 8)
                Button(fanBarText("复制", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    static func failureReport(_ feedback: FanController.ModeActionFeedback, device: CompatibilityDevice) -> String {
        [
            feedback.detail ?? feedback.message,
            "FanBar \(device.appVersion) · Helper \(device.helperVersion) · macOS \(device.macOSVersion)",
            device.modelIdentifier,
        ].joined(separator: "\n")
    }

    /// Speaks a notice that appeared without the user moving focus to it.
    static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    // MARK: Control notices

    /// The notice to show, if it is still current and no failure covers the strip.
    private func visibleControlNotice(at date: Date) -> ControlNotice? {
        guard let notice = controller.controlNotice, !notice.isExpired(at: date),
              !isShowingModeFailureBanner else { return nil }
        return notice
    }

    /// A quiet row under the mode strip for what FanBar did, or is about to do, on its own.
    private var controlNoticeRow: some View {
        CountdownTimerView { date in
            noticeBody(at: date)
        }
    }

    @ViewBuilder
    private func noticeBody(at date: Date) -> some View {
        if let notice = visibleControlNotice(at: date) {
            HStack(spacing: 8) {
                Image(systemName: Self.noticeSymbol(notice))
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondaryText)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(ControlNoticeText.panelMessage(
                    notice,
                    controller: controller,
                    countdown: Self.countdown(for: notice, at: date)
                ))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                noticeAction(notice)

                PanelIconButton(systemImage: "xmark", size: 20) {
                    controller.dismissControlNotice()
                }
                .accessibilityLabel(fanBarText("关闭提示", "Dismiss"))
            }
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.track))
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .transition(.opacity)
            .onAppear {
                Self.announce(ControlNoticeText.panelMessage(
                    notice, controller: controller, countdown: Self.countdown(for: notice, at: date)
                ))
            }
        }
    }

    private static func noticeSymbol(_ notice: ControlNotice) -> String {
        if case .handedBack(_, .missingTemperature, _, _) = notice { return "thermometer" }
        if case .handedBack(_, .smcRejectingWrites, _, _) = notice { return "exclamationmark.triangle" }
        return "arrow.uturn.backward"
    }

    private static func countdown(for notice: ControlNotice, at date: Date) -> String {
        guard case .handBackSoon(_, _, let deadline) = notice else { return "" }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(date))))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    @ViewBuilder
    private func noticeAction(_ notice: ControlNotice) -> some View {
        switch notice {
        case .handBackSoon(let mode, _, _):
            durationMenu(
                title: fanBarText("延长", "Extend"),
                header: fanBarFormat("%@再保持", "Keep %@ on for", ControlNoticeText.modeName(mode, controller: controller)),
                selected: controller.automaticRestoreDuration
            ) { controller.setAutomaticRestoreDuration($0) }
        case .handedBack(let mode, .timer, let duration, _):
            durationMenu(
                title: fanBarText("重新开启", "Turn on again"),
                header: fanBarFormat("重新开启%@，保持", "Turn %@ on again for", ControlNoticeText.modeName(mode, controller: controller)),
                selected: duration
            ) { controller.turnOnAgain(mode, for: $0) }
        case .handedBack(let mode, .missingTemperature, let duration, _),
             .handedBack(let mode, .smcRejectingWrites, let duration, _):
            PanelTextButton {
                controller.turnOnAgain(mode, for: duration)
            } label: {
                Text(fanBarText("重试", "Try again")).fontWeight(.semibold)
            }
            .disabled(controller.isBusy || controller.helperState != .enabled)
        }
    }

    private func durationMenu(
        title: String,
        header: String,
        selected: FanController.AutomaticRestoreDuration,
        choose: @escaping (FanController.AutomaticRestoreDuration) -> Void
    ) -> some View {
        Menu {
            Section(header: Text(header)) {
                ForEach(FanController.AutomaticRestoreDuration.allCases) { duration in
                    Button {
                        choose(duration)
                    } label: {
                        let label = duration == .never ? fanBarText("一直保持", "Keep on") : duration.title
                        if duration == selected {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(controller.isBusy || controller.helperState != .enabled)
    }

    /// Permanent on Macs whose SMC cannot hand fan control to an app.
    private var unsupportedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "nosign")
                .font(.system(size: 12))
                .foregroundColor(palette.secondaryText)
                .accessibilityHidden(true)
            (Text(fanBarText(
                "这台 Mac 不提供风扇模式键，无法手动控制风扇。温度与转速仍可查看。",
                "This Mac has no fan mode key, so fans can't be controlled manually. Temperatures and speeds still show."
            )) + Text(" "))
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PanelTextButton {
                CompatibilityWindowPresenter.shared.show(controller: controller)
            } label: {
                Text(fanBarText("查看兼容性", "Compatibility")).fontWeight(.semibold)
            }
        }
        .padding(.top, 8)
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
