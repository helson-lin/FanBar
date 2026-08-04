import AppKit
import FanBarShared
import SwiftUI

struct FanBarSettingsView: View {
    @ObservedObject var controller: FanController
    @AppStorage(MenuBarDisplayMode.preferenceKey)
    private var displayModeRawValue = MenuBarDisplayMode.defaultMode.rawValue
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visibleCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRawValue) ?? .defaultMode
    }

    private var visibleCoolingPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visibleCoolingPresetsRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(fanBarText("菜单栏显示", "Menu bar display"))
                    .font(.headline)

                preview

                Picker(
                    fanBarText("显示内容", "Display content"),
                    selection: Binding(
                        get: { displayMode },
                        set: { displayModeRawValue = $0.rawValue }
                    )
                ) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(displayMode.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            coolingPresetSettings

            Divider()
            languageSettings

            Divider()
            freeSoftwareNotice
        }
        .padding(22)
        .frame(width: 420)
    }

    private var coolingPresetSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fanBarText("散热预设", "Cooling presets"))
                    .font(.headline)
                Spacer()
                Text("\(visibleCoolingPresets.count) / 2")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(fanBarText(
                "选择最多两个显示在主面板中。转速按每枚风扇的最大值分别计算。",
                "Choose up to two presets to show on the main panel. Each fan uses its own maximum RPM."
            ))
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(FanCoolingPreset.allCases) { preset in
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

                    Text(fanBarFormat(
                        "最大转速 %@",
                        "Maximum RPM %@",
                        preset.percentageText
                    ))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var languageSettings: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fanBarText("语言", "Language"))
                    .font(.headline)
                Text(fanBarText(
                    "切换 FanBar 的界面语言，修改会立即生效。",
                    "Change FanBar's interface language. The change takes effect immediately."
                ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker(
                "",
                selection: Binding(
                    get: { languageRawValue },
                    set: { languageRawValue = $0 }
                )
            ) {
                ForEach(FanBarLanguage.allCases) { language in
                    Text(language.title).tag(language.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(fanBarText("FanBar 设置", "FanBar Settings"))
                    .font(.title3.weight(.semibold))
                Text(fanBarText("自定义菜单栏中的实时信息", "Customize the live menu-bar information"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
        .padding(.vertical, 3)
    }
}
