import AppKit
import FanBarShared
import SwiftUI

/// Settings panes. The selection persists so the window reopens where the
/// user left off. Tabs are presented by the window toolbar (the macOS
/// settings convention); the view only swaps content.
enum SettingsTab: String, CaseIterable, Identifiable {
    case menuBar
    case cooling
    case general

    static let preferenceKey = "fanbar.settingsSelectedTab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: fanBarText("菜单栏", "Menu Bar")
        case .cooling: fanBarText("散热", "Cooling")
        case .general: fanBarText("通用", "General")
        }
    }

    var symbol: String {
        switch self {
        case .menuBar: "macwindow"
        case .cooling: "fan"
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
    private var selectedTabRawValue = SettingsTab.menuBar.rawValue

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRawValue) ?? .defaultMode
    }

    private var visibleCoolingPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visibleCoolingPresetsRawValue)
    }

    private var currentTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .menuBar
    }

    var body: some View {
        Group {
            switch currentTab {
            case .menuBar: menuBarTab
            case .cooling: coolingTab
            case .general: generalTab
            }
        }
        .frame(width: 460)
    }

    // MARK: - Tabs

    private var menuBarTab: some View {
        menuBarSection
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var coolingTab: some View {
        coolingPresetSection
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            generalSection

            freeSoftwareNotice
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            settingsCard {
                preview
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                rowDivider

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
                // AppKit caches radio-group item titles; rebuild the group when the language changes.
                .id(languageRawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                rowDivider

                Toggle(isOn: $switchFeedbackAnimationEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fanBarText("风扇运转动画", "Fan activity animation"))
                        Text(fanBarText(
                            "风扇运转时图标持续旋转并跟随实际转速，停转后缓缓静止。",
                            "The icon spins with the fans, matching their speed, and coasts to a stop when they halt."
                        ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            sectionFooter(displayMode.detail)
        }
    }

    private var coolingPresetSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                fanBarText("散热预设", "Cooling presets"),
                trailing: "\(visibleCoolingPresets.count) / 2"
            )

            settingsCard {
                ForEach(Array(FanCoolingPreset.allCases.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { rowDivider }

                    HStack(spacing: 9) {
                        Toggle(
                            isOn: presetSelectionBinding(for: preset)
                        ) {
                            Label(preset.title, systemImage: preset.systemImage)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(
                            !visibleCoolingPresets.contains(preset)
                                && visibleCoolingPresets.count >= 2
                        )

                        Spacer()

                        Text(preset.percentageText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            sectionFooter(fanBarText(
                "最多选择两个显示在主面板中，百分比为该预设的最大转速。",
                "Choose up to two presets for the main panel. The percentage is each preset's maximum RPM."
            ))
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            settingsCard {
                Toggle(
                    isOn: Binding(
                        get: { controller.highTemperatureNotificationsEnabled },
                        set: { controller.setHighTemperatureNotificationsEnabled($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fanBarFormat(
                            "CPU 或 GPU 达到 %.0f°C 时通知",
                            "Notify when CPU or GPU reaches %.0f°C",
                            ThermalAlertSettings.thresholdCelsius
                        ))
                        Text(fanBarText(
                            "同一次高温只通知一次，降温后再次升高会重新通知。",
                            "One notification per high-temperature episode; it resets after cooling down."
                        ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .disabled(controller.isRequestingHighTemperatureNotificationPermission)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

                rowDivider

                HStack {
                    Text(fanBarText("语言", "Language"))

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
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Building blocks

    /// Section title floating above its card, following the macOS grouped
    /// settings convention.
    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Explanatory text belongs below the card, not between the controls.
    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    /// Color(nsColor:) requires macOS 12; on 11 a primary-tinted fill reads
    /// as an inset panel in light mode and a raised group in dark mode.
    @ViewBuilder
    private var cardBackground: some View {
        if #available(macOS 12.0, *) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 12)
    }

    // MARK: - Pieces carried over

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

    /// Clarifies the app's pricing model without competing with settings content.
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
