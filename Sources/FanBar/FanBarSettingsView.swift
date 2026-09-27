import AppKit
import FanBarShared
import SwiftUI

/// Settings panes. The selection persists so the window reopens where the
/// user left off. The native labeled toolbar navigation is installed by the
/// window presenter so content can use the full height below the title bar.
/// Case order is the toolbar order (and ⌘1…⌘3).
enum SettingsTab: String, CaseIterable, Identifiable {
    /// Primary task: smart cooling curve (see `.impeccable.md`).
    case cooling
    case menuBar
    case general

    static let preferenceKey = "fanbar.settingsSelectedTab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooling: fanBarText("散热", "Cooling")
        case .menuBar: fanBarText("菜单栏", "Menu Bar")
        case .general: fanBarText("通用", "General")
        }
    }

    var symbol: String {
        switch self {
        case .cooling: "fan"
        case .menuBar: "macwindow"
        case .general: "gearshape"
        }
    }
}

struct FanBarSettingsView: View {
    @ObservedObject var controller: FanController
    @AppStorage(MenuBarDisplayMode.preferenceKey)
    private var displayModeRawValue = MenuBarDisplayMode.defaultMode.rawValue
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @AppStorage(SwitchFeedbackPreferences.preferenceKey)
    private var switchFeedbackAnimationEnabled = true
    @AppStorage(PanelAnimationPreferences.preferenceKey)
    private var panelAnimationEnabled = true
    @AppStorage(SettingsTab.preferenceKey)
    private var selectedTabRawValue = SettingsTab.cooling.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The alert temperature is set rarely, so its slider stays tucked away.
    @State private var isThresholdExpanded = false

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRawValue) ?? .defaultMode
    }

    private var currentTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .cooling
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
                switch currentTab {
                case .cooling: coolingTab
                case .menuBar: menuBarTab
                case .general: generalTab
                }
            }
            .padding(.horizontal, SettingsChrome.horizontalPadding)
            .padding(.top, SettingsChrome.topPadding)
            .padding(.bottom, SettingsChrome.bottomPadding)
            .frame(width: SettingsChrome.contentWidth, alignment: .topLeading)
        }
        .frame(width: SettingsChrome.contentWidth)
        .background(Color(NSColor.windowBackgroundColor))
        // Invisible commands preserve fast keyboard navigation while the
        // visible controls live in AppKit's title-bar toolbar.
        .background(SettingsTabKeyboardShortcuts(selection: $selectedTabRawValue))
        .onChange(of: selectedTabRawValue) { _ in
            SettingsWindowPresenter.shared.resizeToFitContentSoon()
        }
    }

    // MARK: - Cooling

    @ViewBuilder
    private var coolingTab: some View {
        // Attention states only: when the service is healthy, the General
        // pane carries its status and the curve keeps the first position.
        if controller.helperState != .enabled {
            ControlServiceBanner(controller: controller)
        }
        CoolingPresetTiles(controller: controller)
        FanCurveEditorView(controller: controller)
    }

    // MARK: - Menu Bar

    @ViewBuilder
    private var menuBarTab: some View {
        SettingsSection(
            title: fanBarText("菜单栏显示", "Menu Bar display"),
            footer: fanBarText("选择状态在菜单栏里的样子。", "Choose how FanBar looks in the menu bar.")
        ) {
            MenuBarPreviewStrip(controller: controller, displayMode: displayMode)

            ForEach(MenuBarDisplayMode.allCases) { mode in
                SettingsChrome.rowDivider
                MenuBarDisplayOptionRow(
                    controller: controller,
                    mode: mode,
                    isSelected: mode == displayMode,
                    onSelect: { displayModeRawValue = mode.rawValue }
                )
            }
        }
        .accessibilityElement(children: .contain)

        SettingsSection(
            title: fanBarText("动画", "Animation"),
            footer: fanBarText(
                "动画需要持续重绘界面。关闭可降低 FanBar 的 CPU 占用，主界面动画仅在面板打开时运行。",
                "Animations redraw continuously. Turning them off lowers FanBar's CPU use; panel animation runs only while the panel is open."
            )
        ) {
            Toggle(isOn: $switchFeedbackAnimationEnabled) {
                SettingsRowText(
                    title: fanBarText("菜单栏图标动画", "Menu bar icon animation"),
                    detail: fanBarText(
                        "风扇运转时图标旋转并跟随实际转速，停转后缓缓静止。",
                        "The icon spins with the fans and coasts to a stop when they halt."
                    )
                )
            }
            .toggleStyle(.switch)
            .settingsRow()

            SettingsChrome.rowDivider

            Toggle(isOn: $panelAnimationEnabled) {
                SettingsRowText(
                    title: fanBarText("主界面动画", "Panel animation"),
                    detail: fanBarText(
                        "主界面的风扇转动与模式切换过渡。关闭后仍实时显示转速。",
                        "Spinning fans and mode transitions in the menu bar panel. RPM readings still update live."
                    )
                )
            }
            .toggleStyle(.switch)
            .settingsRow()
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalTab: some View {
        fanControlSection
        notificationsSection
        appSection
        freeSoftwareNotice
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    /// Manual control's prerequisite and its safety net belong together.
    private var fanControlSection: some View {
        SettingsSection(
            title: fanBarText("风扇控制", "Fan Control")
        ) {
            controlServiceRow
            SettingsChrome.rowDivider
            automaticRestoreRow
        }
    }

    /// App-level preferences that are set once and rarely revisited.
    private var appSection: some View {
        SettingsSection(
            title: "FanBar",
            trailing: SoftwareUpdateController.shared.currentVersion,
            action: SettingsSectionAction(
                title: fanBarText("检查更新…", "Check for Updates…"),
                perform: { SoftwareUpdateController.shared.checkForUpdates() }
            )
        ) {
            launchAtLoginRow
            SettingsChrome.rowDivider
            languageRow
            SettingsChrome.rowDivider
            softwareUpdateRow
        }
    }

    private var launchAtLoginRow: some View {
        Toggle(
            isOn: Binding(
                get: { controller.launchAtLoginEnabled },
                set: { controller.setLaunchAtLogin($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                SettingsRowText(
                    title: fanBarText("登录时启动 FanBar", "Launch FanBar at login"),
                    detail: fanBarText("登录后自动出现在菜单栏。", "Appears in the menu bar after you sign in.")
                )
                if controller.launchAtLoginRequiresApproval {
                    Button(fanBarText("等待系统批准 · 打开设置", "Waiting for approval · Open Settings")) {
                        controller.openLoginItemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }
        }
        .toggleStyle(.switch)
        .settingsRow()
    }

    /// Healthy: one quiet status line. Needs attention: symbol, guidance and action.
    @ViewBuilder
    private var controlServiceRow: some View {
        let state = controller.helperState
        if state == .enabled {
            HStack(spacing: 8) {
                Text(fanBarText("控制服务", "Control service"))
                Spacer(minLength: 12)
                Image(systemName: state.symbolName)
                    .foregroundColor(state.tint)
                    .accessibilityHidden(true)
                Text(fanBarText("已启用", "Enabled"))
                    .foregroundColor(.secondary)
            }
            .settingsRow()
            .help(state.noticeDetail)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 12) {
                Image(systemName: state.symbolName)
                    .font(.system(size: 18))
                    .foregroundColor(state.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                SettingsRowText(title: state.noticeTitle, detail: state.noticeDetail)
                if let actionTitle = state.actionTitle {
                    Button(actionTitle, action: controller.performHelperAction)
                }
            }
            .settingsRow()
            .accessibilityElement(children: .contain)
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: fanBarText("通知", "Notifications")) {
            Toggle(
                isOn: Binding(
                    get: { controller.highTemperatureNotificationsEnabled },
                    set: { controller.setHighTemperatureNotificationsEnabled($0) }
                )
            ) {
                SettingsRowText(
                    title: fanBarText("高温提醒", "High-temperature alerts"),
                    detail: fanBarText(
                        "同一次高温只提醒一次；温度回落后再次升高会重新通知。",
                        "One alert per high-temperature episode; it resets after cooling down."
                    )
                )
            }
            .toggleStyle(.switch)
            .disabled(controller.isRequestingHighTemperatureNotificationPermission)
            .settingsRow()

            SettingsChrome.rowDivider

            thresholdRow
        }
    }

    private var thresholdRow: some View {
        let range = ThermalAlertSettings.thresholdRange
        let value = controller.highTemperatureThresholdCelsius
        let isEnabled = controller.highTemperatureNotificationsEnabled
        let isExpanded = isThresholdExpanded && isEnabled
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1)) {
                    isThresholdExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(fanBarText("提醒温度", "Alert temperature"))
                        .foregroundColor(.primary)
                    Spacer(minLength: 12)
                    Text(String(format: "%.0f°C", value))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                }
                .settingsRow()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(fanBarText("提醒温度", "Alert temperature"))
            .accessibilityValue(String(format: "%.0f°C", value))
            .accessibilityHint(isExpanded
                ? fanBarText("收起温度设置", "Collapse the temperature setting")
                : fanBarText("展开以调整温度", "Expand to adjust the temperature"))

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // A slider reaches any value in one drag instead of ±1 clicks.
                    Slider(
                        value: Binding(
                            get: { controller.highTemperatureThresholdCelsius },
                            set: { controller.setHighTemperatureThreshold($0) }
                        ),
                        // No `step:`: macOS would draw a tick for every degree.
                        // The controller rounds to whole degrees instead.
                        in: range
                    ) {
                        Text(fanBarText("提醒温度", "Alert temperature"))
                    } minimumValueLabel: {
                        Text(String(format: "%.0f°", range.lowerBound))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text(String(format: "%.0f°", range.upperBound))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .labelsHidden()
                    .accessibilityValue(String(format: "%.0f°C", value))

                    Text(fanBarFormat(
                        "默认 %.0f°C。",
                        "Default %.0f°C.",
                        ThermalAlertSettings.defaultThresholdCelsius
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                .padding(.bottom, SettingsChrome.rowHorizontalPadding)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .disabled(!isEnabled)
    }

    private var automaticRestoreRow: some View {
        HStack {
            SettingsRowText(
                title: fanBarText("自动恢复系统控制", "Restore automatic control"),
                detail: fanBarText(
                    "手动模式到时交还 macOS；主界面中的修改只对当次生效。",
                    "Manual modes hand back to macOS when time runs out. Menu changes apply to that session only."
                )
            )
            Spacer(minLength: 12)
            Picker(
                fanBarText("自动恢复系统控制", "Restore automatic control"),
                selection: Binding(
                    get: { controller.defaultAutomaticRestoreDuration },
                    set: { controller.setDefaultAutomaticRestoreDuration($0) }
                )
            ) {
                ForEach(FanController.AutomaticRestoreDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }
            .labelsHidden()
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
    }

    private var languageRow: some View {
        HStack {
            Text(fanBarText("界面语言", "Interface language"))
            Spacer(minLength: 12)
            Picker(
                fanBarText("界面语言", "Interface language"),
                selection: Binding(
                    get: { languageRawValue },
                    set: {
                        languageRawValue = $0
                        SettingsWindowPresenter.shared.updateTitle()
                    }
                )
            ) {
                ForEach(FanBarLanguage.allCases) { language in
                    Text(language.title).tag(language.rawValue)
                }
            }
            .labelsHidden()
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
    }

    private var softwareUpdateRow: some View {
        let updater = SoftwareUpdateController.shared
        return Toggle(
            isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            )
        ) {
            SettingsRowText(title: fanBarText("自动检查更新", "Automatically check for updates"))
        }
        .toggleStyle(.switch)
        .settingsRow()
    }

    private var freeSoftwareNotice: some View {
        HStack(spacing: 6) {
            Link(destination: URL(string: "https://github.com/helson-lin")!) {
                Image(nsImage: GitHubMark.image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            .accessibilityLabel(fanBarText("打开 GitHub 主页", "Open the GitHub profile"))
            .help(fanBarText("在浏览器中打开 GitHub 主页", "Open the GitHub profile in a browser"))

            Text(fanBarText("FanBar 是免费软件，可自由使用。", "FanBar is free software. You are free to use it."))
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

/// Shown on the Cooling pane only when the control service needs attention,
/// with the state named by symbol and text rather than color alone.
struct ControlServiceBanner: View {
    @ObservedObject var controller: FanController

    var body: some View {
        let state = controller.helperState
        HStack(spacing: 12) {
            Image(systemName: state.symbolName)
                .font(.system(size: 18))
                .foregroundColor(state.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.noticeTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(fanBarText(
                    "曲线已保存，服务可用后才会生效。\(state.noticeDetail)。",
                    "Your curves are saved and apply once the service is available. \(state.noticeDetail)."
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle = state.actionTitle {
                Button(actionTitle, action: controller.performHelperAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                .fill(state.tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                .stroke(state.tint.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
