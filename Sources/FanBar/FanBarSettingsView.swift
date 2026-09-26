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

        SettingsSection(title: fanBarText("动画", "Animation")) {
            Toggle(isOn: $switchFeedbackAnimationEnabled) {
                SettingsRowText(
                    title: fanBarText("风扇运转动画", "Fan activity animation"),
                    detail: fanBarText(
                        "风扇运转时图标旋转并跟随实际转速，停转后缓缓静止。",
                        "The icon spins with the fans and coasts to a stop when they halt."
                    )
                )
            }
            .toggleStyle(.switch)
            .padding(SettingsChrome.rowHorizontalPadding)
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalTab: some View {
        startupSection
        controlServiceSection
        notificationsSection
        languageSection
        softwareUpdateSection
        freeSoftwareNotice
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var startupSection: some View {
        SettingsSection(title: fanBarText("启动", "Startup")) {
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
            .padding(SettingsChrome.rowHorizontalPadding)
        }
    }

    private var controlServiceSection: some View {
        let state = controller.helperState
        return SettingsSection(
            title: fanBarText("控制服务", "Control Service"),
            footer: fanBarText(
                "控制服务是手动调节风扇所需的系统授权；未启用时始终由 macOS 自动管理。",
                "The control service is the system approval needed for manual fan control. Without it, macOS always manages the fans."
            )
        ) {
            HStack(spacing: 12) {
                Image(systemName: state.symbolName)
                    .font(.system(size: 18))
                    .foregroundColor(state.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                SettingsRowText(title: state.title, detail: state.noticeDetail)
                if let actionTitle = state.actionTitle {
                    Button(actionTitle, action: controller.performHelperAction)
                }
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.vertical, SettingsChrome.rowVerticalPadding + 2)
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
                    title: fanBarFormat(
                        "CPU 或 GPU 达到 %.0f°C 时通知",
                        "Notify when CPU or GPU reaches %.0f°C",
                        controller.highTemperatureThresholdCelsius
                    ),
                    detail: fanBarText(
                        "同一次高温只提醒一次；温度回落后再次升高会重新通知。",
                        "One alert per high-temperature episode; it resets after cooling down."
                    )
                )
            }
            .toggleStyle(.switch)
            .disabled(controller.isRequestingHighTemperatureNotificationPermission)
            .padding(SettingsChrome.rowHorizontalPadding)

            SettingsChrome.rowDivider

            thresholdRow
        }
    }

    private var thresholdRow: some View {
        let range = ThermalAlertSettings.thresholdRange
        return HStack(spacing: 12) {
            SettingsRowText(
                title: fanBarText("提醒温度", "Alert temperature"),
                detail: fanBarFormat(
                    "可设范围 %.0f–%.0f°C，默认 %.0f°C。",
                    "Range %.0f–%.0f°C. Default %.0f°C.",
                    range.lowerBound,
                    range.upperBound,
                    ThermalAlertSettings.defaultThresholdCelsius
                )
            )
            Text(String(format: "%.0f°C", controller.highTemperatureThresholdCelsius))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .accessibilityHidden(true)
            Stepper(
                fanBarText("提醒温度", "Alert temperature"),
                value: Binding(
                    get: { controller.highTemperatureThresholdCelsius },
                    set: { controller.setHighTemperatureThreshold($0) }
                ),
                in: range,
                step: 1
            )
            .labelsHidden()
            .accessibilityValue(String(format: "%.0f°C", controller.highTemperatureThresholdCelsius))
        }
        .padding(SettingsChrome.rowHorizontalPadding)
        .disabled(!controller.highTemperatureNotificationsEnabled)
    }

    private var languageSection: some View {
        SettingsSection(title: fanBarText("语言", "Language")) {
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
                .fixedSize()
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.vertical, SettingsChrome.rowVerticalPadding)
        }
    }

    private var softwareUpdateSection: some View {
        let updater = SoftwareUpdateController.shared
        return SettingsSection(
            title: fanBarText("软件更新", "Software Update"),
            trailing: updater.currentVersion
        ) {
            Toggle(
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )
            ) {
                Text(fanBarText("自动检查更新", "Automatically check for updates"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .padding(SettingsChrome.rowHorizontalPadding)

            SettingsChrome.rowDivider

            HStack {
                Text(fanBarText("获取最新版本", "Get the latest version"))
                Spacer(minLength: 12)
                Button(fanBarText("检查更新…", "Check for Updates…")) {
                    updater.checkForUpdates()
                }
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.vertical, SettingsChrome.rowVerticalPadding)
        }
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
