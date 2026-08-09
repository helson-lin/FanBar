import AppKit
import FanBarShared
import SwiftUI

/// Settings panes. The selection persists so the window reopens where the
/// user left off. Tabs are presented by the window toolbar (the macOS
/// settings convention); the view only swaps content.
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
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visibleCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @AppStorage(SwitchFeedbackPreferences.preferenceKey)
    private var switchFeedbackAnimationEnabled = true
    @AppStorage(SettingsTab.preferenceKey)
    private var selectedTabRawValue = SettingsTab.cooling.rawValue

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRawValue) ?? .defaultMode
    }

    private var visibleCoolingPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visibleCoolingPresetsRawValue)
    }

    private var currentTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .cooling
    }

    var body: some View {
        Group {
            switch currentTab {
            case .cooling: coolingTab
            case .menuBar: menuBarTab
            case .general: generalTab
            }
        }
        .frame(width: SettingsChrome.contentWidth)
    }

    // MARK: - Tabs

    private var coolingTab: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            FanCurveEditorView(controller: controller)
            panelPresetSection
        }
        .padding(.horizontal, SettingsChrome.horizontalPadding)
        .padding(.top, SettingsChrome.topPadding)
        .padding(.bottom, SettingsChrome.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var menuBarTab: some View {
        menuBarSection
            .padding(.horizontal, SettingsChrome.horizontalPadding)
            .padding(.top, SettingsChrome.topPadding)
            .padding(.bottom, SettingsChrome.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            notificationsSection
            languageSection
            freeSoftwareNotice
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(.horizontal, SettingsChrome.horizontalPadding)
        .padding(.top, SettingsChrome.topPadding)
        .padding(.bottom, SettingsChrome.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        SettingsSection(
            title: fanBarText("菜单栏显示", "Menu Bar display"),
            footer: displayMode.detail
        ) {
            preview
                .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                .padding(.vertical, 10)

            SettingsChrome.rowDivider

            Picker(
                "",
                selection: Binding(
                    get: { displayMode },
                    set: { displayModeRawValue = $0.rawValue }
                )
            ) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            // AppKit caches radio-group item titles; rebuild when language changes.
            .id(languageRawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.vertical, 6)

            SettingsChrome.rowDivider

            Toggle(isOn: $switchFeedbackAnimationEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fanBarText("风扇运转动画", "Fan activity animation"))
                    Text(fanBarText(
                        "风扇运转时图标旋转并跟随实际转速，停转后缓缓静止。",
                        "The icon spins with the fans and coasts to a stop when they halt."
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .padding(SettingsChrome.rowHorizontalPadding)
        }
    }

    // MARK: - Cooling (panel presets only; curve lives in FanCurveEditorView)

    private var panelPresetSection: some View {
        SettingsSection(
            title: fanBarText("面板预设", "Panel presets"),
            trailing: "\(visibleCoolingPresets.count) / 2",
            footer: fanBarText(
                "最多两个会出现在主面板的手动菜单中。",
                "Up to two appear in the main panel’s manual menu."
            )
        ) {
            ForEach(Array(FanCoolingPreset.allCases.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { SettingsChrome.rowDivider }

                HStack(spacing: 10) {
                    Toggle(isOn: presetSelectionBinding(for: preset)) {
                        Label(preset.title, systemImage: preset.systemImage)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        !visibleCoolingPresets.contains(preset)
                            && visibleCoolingPresets.count >= 2
                    )

                    Spacer(minLength: 8)

                    Text(preset.percentageText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - General

    private var notificationsSection: some View {
        SettingsSection(
            title: fanBarText("通知", "Notifications"),
            footer: fanBarText(
                "同一次高温只提醒一次；温度回落后再次升高会重新通知。",
                "One alert per high-temperature episode; it resets after cooling down."
            )
        ) {
            Toggle(
                isOn: Binding(
                    get: { controller.highTemperatureNotificationsEnabled },
                    set: { controller.setHighTemperatureNotificationsEnabled($0) }
                )
            ) {
                Text(fanBarFormat(
                    "CPU 或 GPU 达到 %.0f°C 时通知",
                    "Notify when CPU or GPU reaches %.0f°C",
                    ThermalAlertSettings.thresholdCelsius
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(controller.isRequestingHighTemperatureNotificationPermission)
            .padding(SettingsChrome.rowHorizontalPadding)
        }
    }

    private var languageSection: some View {
        SettingsSection(title: fanBarText("语言", "Language")) {
            HStack {
                Text(fanBarText("界面语言", "Interface language"))
                Spacer(minLength: 12)
                Picker(
                    "",
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

    // MARK: - Shared pieces

    private func presetSelectionBinding(for preset: FanCoolingPreset) -> Binding<Bool> {
        Binding(
            get: { visibleCoolingPresets.contains(preset) },
            set: { isSelected in
                var selection = Set(visibleCoolingPresets)
                if isSelected {
                    guard selection.count < 2 else { return }
                    selection.insert(preset)
                } else {
                    selection.remove(preset)
                }
                visibleCoolingPresetsRawValue = CoolingPresetPreferences.rawValue(for: selection)
            }
        )
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

    private var preview: some View {
        HStack {
            Text(fanBarText("预览", "Preview"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            MenuBarStatusLabel(controller: controller, displayMode: displayMode)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }
}
