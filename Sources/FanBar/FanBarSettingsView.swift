import AppKit
import FanBarShared
import SwiftUI

struct FanBarSettingsView: View {
    @ObservedObject var controller: FanController
    @AppStorage(MenuBarDisplayMode.preferenceKey)
    private var displayModeRawValue = MenuBarDisplayMode.defaultMode.rawValue
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visibleCoolingPresetsRawValue = CoolingPresetPreferences.defaultRawValue

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
                Text("菜单栏显示")
                    .font(.headline)

                preview

                Picker(
                    "显示内容",
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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            coolingPresetSettings
        }
        .padding(22)
        .frame(width: 420)
    }

    private var coolingPresetSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("散热预设")
                    .font(.headline)
                Spacer()
                Text("\(visibleCoolingPresets.count) / 2")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("选择最多两个显示在主面板中。转速按每枚风扇的最大值分别计算。")
                .font(.caption)
                .foregroundStyle(.secondary)

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

                    Text("最大转速 \(preset.percentageText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                Text("FanBar 设置")
                    .font(.title3.weight(.semibold))
                Text("自定义菜单栏中的实时信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preview: some View {
        HStack {
            Text("预览")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            MenuBarStatusLabel(controller: controller, displayMode: displayMode)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .padding(.vertical, 3)
    }
}
