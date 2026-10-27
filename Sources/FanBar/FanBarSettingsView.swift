import AppKit
import FanBarShared
import SwiftUI

/// Settings panes. The selection persists so the window reopens where the
/// user left off. The native labeled toolbar navigation is installed by the
/// window presenter so content can use the full height below the title bar.
/// Case order is the toolbar order (and ⌘1…⌘4).
enum SettingsTab: String, CaseIterable, Identifiable {
    /// Primary task: smart cooling curve (see `.impeccable.md`).
    case cooling
    /// Raw value kept from the former "Menu Bar" pane so a saved selection survives.
    case appearance = "menuBar"
    case general
    /// Last so ⌘1…⌘3 keep their existing meaning.
    case log

    static let preferenceKey = "fanbar.settingsSelectedTab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooling: fanBarText("散热", "Cooling")
        case .appearance: fanBarText("外观", "Appearance")
        case .general: fanBarText("通用", "General")
        case .log: fanBarText("日志", "Log")
        }
    }

    var symbol: String {
        switch self {
        case .cooling: FanBarSymbols.fan
        case .appearance: "paintbrush"
        case .general: "gearshape"
        case .log: "doc.text"
        }
    }
}

struct FanBarSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                case .appearance: appearanceTab
                case .general: generalTab
                case .log: logTab
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
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    // MARK: - Cooling

    @ViewBuilder
    private var coolingTab: some View {
        // Attention states only: when the service is healthy, the General
        // pane carries its status and the curve keeps the first position.
        if controller.helperState != .enabled {
            ControlServiceBanner(controller: controller)
            Button(fanBarText("查看本机兼容性…", "Check this Mac’s compatibility…")) {
                CompatibilityWindowPresenter.shared.show(controller: controller)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
        } else if controller.compatibilitySnapshot?.fanCount == nil
            || controller.compatibilitySnapshot?.fanCount == 0 {
            compatibilitySection
        }
        CoolingPresetTiles(controller: controller)
        FanCurveEditorView(controller: controller)
    }

    // MARK: - Appearance

    /// How FanBar looks: in the menu bar, as an app icon, and in motion.
    @ViewBuilder
    private var appearanceTab: some View {
        // Icon and readout are one decision about the same status item, so
        // they share a card instead of two sections.
        SettingsSection(
            title: fanBarText("菜单栏", "Menu Bar"),
            footer: fanBarText(
                "选择 FanBar 在菜单栏里的图标和显示内容。",
                "Choose FanBar's icon and what it shows in the menu bar."
            )
        ) {
            // The strip shows the chosen icon and readout between system
            // items, so their combined width is judged in context.
            MenuBarPreviewStrip(controller: controller, displayMode: displayMode)

            MenuBarIconStylePicker(controller: controller)

            SettingsChrome.rowDivider

            // One decision, so no dividers between choices; the selected
            // one is tinted instead.
            VStack(spacing: 2) {
                ForEach(Array(MenuBarDisplayMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    MenuBarDisplayOptionRow(
                        controller: controller,
                        mode: mode,
                        isSelected: mode == displayMode,
                        position: index + 1,
                        count: MenuBarDisplayMode.allCases.count,
                        onSelect: { displayModeRawValue = mode.rawValue }
                    )
                }
            }
            .padding(SettingsChrome.choiceInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fanBarText("菜单栏", "Menu Bar"))

        SettingsSection(
            title: fanBarText("App 图标", "App Icon"),
            footer: fanBarText(
                "用于访达、启动台和菜单栏面板。",
                "Used in Finder, Launchpad, and the menu bar panel."
            )
        ) {
            AppIconPickerRow()
        }

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

    /// CSV logging of temperatures and fan speeds; see docs/design/temperature-logging.md.
    private var logTab: some View {
        TemperatureLogSettingsView(controller: controller)
    }

    @ViewBuilder
    private var generalTab: some View {
        fanControlSection
        NotificationSettingsSection(controller: controller)
        appSection
        ToolIntegrationsSection()
        compatibilitySection
        freeSoftwareNotice
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var compatibilitySection: some View {
        SettingsSection(
            title: fanBarText("设备兼容性", "Device Compatibility"),
            footer: fanBarText("检测在本机完成，不会自动上传设备信息。", "Checks run locally. Device information is not automatically uploaded.")
        ) {
            Button {
                CompatibilityWindowPresenter.shared.show(controller: controller)
            } label: {
                HStack(spacing: 16) {
                    SettingsRowText(
                        title: fanBarText("本机能力与兼容性", "This Mac’s capabilities and compatibility"),
                        detail: controller.compatibilitySnapshot?.summary
                            ?? fanBarText("查看本机可用功能。", "See which features are available on this Mac.")
                    )
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
                .settingsRow()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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
        SettingsSection(title: "FanBar") {
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
                Circle()
                    .fill(PanelPalette(colorScheme: colorScheme).accent)
                    .frame(width: 6, height: 6)
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

    private var automaticRestoreRow: some View {
        HStack {
            SettingsRowText(
                title: fanBarText("自动恢复为自动模式", "Restore automatic control"),
                detail: fanBarText(
                    "手动模式到时交还 macOS；主界面中的修改只对当次生效。",
                    "Manual modes hand back to macOS when time runs out. Menu changes apply to that session only."
                )
            )
            Spacer(minLength: 12)
            Picker(
                fanBarText("自动恢复为自动模式", "Restore automatic control"),
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
            .id(languageRawValue)
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
            .id(languageRawValue)
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
    }

    /// Version, manual check and the automatic-check switch share one row,
    /// so everything about updates is found in one place.
    private var softwareUpdateRow: some View {
        let updater = SoftwareUpdateController.shared
        return HStack(spacing: 12) {
            SettingsRowText(
                title: fanBarText("自动检查更新", "Automatically check for updates"),
                detail: fanBarFormat("当前版本 %@", "Current version %@", updater.currentVersion)
            )
            Button(fanBarText("检查更新…", "Check for Updates…")) {
                updater.checkForUpdates()
            }
            Toggle(
                fanBarText("自动检查更新", "Automatically check for updates"),
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .settingsRow()
    }

    private var freeSoftwareNotice: some View {
        SettingsSupportFooter()
    }
}

/// One quiet line at the foot of the General tab: FanBar is free and open
/// source, then a link to Star the repository and a link to the donation checkout.
struct SettingsSupportFooter: View {
    /// Read so the footer repaints when the interface language changes.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    var body: some View {
        HStack(spacing: 0) {
            // Match the links' 8pt inset so the dots sit evenly between items.
            Text(fanBarText("FanBar 免费开源", "FanBar is free and open source"))
                .padding(.trailing, 8)
            separator
            SettingsFooterLink(
                destination: FanBarLinks.repository,
                title: fanBarText("在 GitHub 点 Star", "Star on GitHub"),
                help: fanBarText("在浏览器中打开 FanBar 的 GitHub 仓库", "Open the FanBar GitHub repository in a browser")
            ) {
                Image(nsImage: GitHubMark.image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            separator
            SettingsFooterLink(
                destination: FanBarLinks.donation,
                title: fanBarText("支持开发", "Support"),
                help: fanBarText(
                    "随意付，用于签名证书与维护。在浏览器中打开支持页面",
                    "Pay what you want toward signing and upkeep. Opens in your browser."
                )
            ) {
                Image(systemName: "heart")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        Text("·").accessibilityHidden(true)
    }
}

/// Pages FanBar opens in the browser.
enum FanBarLinks {
    static let repository = URL(string: "https://github.com/helson-lin/FanBar")!
    /// Dodo Payments checkout for donations.
    static let donation = URL(string: "https://checkout.dodopayments.com/buy/pdt_0NqThcy5f4slzzZQspCty?quantity=1")!
}

/// A caption-sized link at the foot of the General tab that turns accent on hover.
struct SettingsFooterLink<Icon: View>: View {
    let destination: URL
    let title: String
    let help: String
    @ViewBuilder let icon: () -> Icon
    @State private var isHovered = false

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                icon()
                    .accessibilityHidden(true)
                Text(title)
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(isHovered ? .accentColor : .secondary)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Shown on the Cooling pane only when the control service needs attention,
/// with the state named by symbol and text rather than color alone.
struct ControlServiceBanner: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

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
                Text(fanBarFormat(
                    "曲线已保存，服务可用后才会生效。%@。",
                    "Your curves are saved and apply once the service is available. %@.",
                    state.noticeDetail
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
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}

/// Turns the one-minute warning and the hand-back notification on or off.
private struct HandBackReminderRow: View {
    /// Repaints the copy when the interface language changes.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @ObservedObject var controller: FanController

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { controller.handBackRemindersEnabled },
                set: { controller.setHandBackRemindersEnabled($0) }
            )
        ) {
            // swiftlint:disable line_length
            SettingsRowText(
                title: fanBarText("控制交回 macOS 前提醒", "Remind before handing back to macOS"),
                detail: fanBarText(
                    "定时结束前 1 分钟提醒，可以直接延长；没有处理，交回后再提示一次。面板开着时只在面板里显示。",
                    "One minute before a timer ends, with a button to extend; if nothing changes, once more after the hand-back. With the panel open, it shows there instead."
                )
            )
            // swiftlint:enable line_length
        }
        .toggleStyle(.switch)
        .settingsRow()
    }
}

/// High-temperature alerts and hand-back reminders.
private struct NotificationSettingsSection: View {
    /// Repaints the copy when the interface language changes.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @ObservedObject var controller: FanController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsSection(title: fanBarText("通知", "Notifications")) {
            HandBackReminderRow(controller: controller)

            SettingsChrome.rowDivider

            Toggle(
                isOn: Binding(
                    get: { controller.highTemperatureNotificationsEnabled },
                    set: { controller.setHighTemperatureNotificationsEnabled($0) }
                )
            ) {
                SettingsRowText(
                    title: fanBarText("高温提醒", "High-temperature alerts"),
                    detail: fanBarText(
                        "同一次高温只提醒一次，降温后重置。面板会同时显示过热提示。",
                        "One alert per high-temperature episode; it resets after cooling down. The panel shows the same warning."
                    )
                )
            }
            .toggleStyle(.switch)
            .disabled(controller.isRequestingHighTemperatureNotificationPermission)
            .settingsRow()

            SettingsChrome.rowDivider

            thresholdRow

            SettingsChrome.rowDivider

            ThermalAlertSoundRow(controller: controller)
        }
    }

    /// Inline stepper: reachable by keyboard and VoiceOver without a
    /// disclosure step, and matches the curve editor's Advanced rows.
    private var thresholdRow: some View {
        let range = ThermalAlertSettings.thresholdRange
        let value = controller.highTemperatureThresholdCelsius
        let valueText = String(format: "%.0f°C", value)
        return HStack {
            SettingsRowText(
                title: fanBarText("提醒温度", "Alert temperature"),
                detail: fanBarFormat(
                    "默认 %.0f°C；面板和曲线上的告警线使用同一数值。",
                    "Default %.0f°C. The panel and the curve's alert line use the same value.",
                    ThermalAlertSettings.defaultThresholdCelsius
                )
            )
            Spacer(minLength: 12)
            Stepper(
                value: Binding(
                    get: { Int(controller.highTemperatureThresholdCelsius.rounded()) },
                    set: { controller.setHighTemperatureThreshold(Double($0)) }
                ),
                in: Int(range.lowerBound)...Int(range.upperBound)
            ) {
                // The panel's warm step: this value is where its alert line sits.
                Text(valueText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(PanelPalette(colorScheme: colorScheme).warmInk)
                    .frame(width: 40, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel(fanBarText("提醒温度", "Alert temperature"))
            .accessibilityValue(valueText)
        }
        .settingsRow()
        .disabled(!controller.highTemperatureNotificationsEnabled)
    }
}
