import FanBarShared
import SwiftUI

/// "Recording mode": three purpose cards (name, one-line use case, one line
/// of values) and, below them, how much disk the choice can take.
struct TemperatureLogPresetPicker: View {
    /// The cards' inputs don't change with the language, so they are rebuilt
    /// on this value; otherwise they keep the previous language's text.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @Binding var intervalSeconds: Int
    @Binding var retentionDays: Int
    let columnCount: Int

    private var selected: TemperatureLogPreset? {
        TemperatureLogPreset.matching(intervalSeconds: intervalSeconds, retentionDays: retentionDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            HStack(spacing: 4) {
                Text(fanBarText("记录方式", "Recording mode"))
                    .font(.system(size: 12, weight: .semibold))
                Text("·")
                Text(fanBarText("可随时更改", "Change anytime"))
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 8) {
                ForEach(TemperatureLogPreset.allCases) { preset in
                    TemperatureLogPresetCard(preset: preset, isSelected: selected == preset) {
                        intervalSeconds = preset.intervalSeconds
                        retentionDays = preset.retentionDays
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .id(languageRawValue)

            Text(TemperatureLogText.presetLine(
                intervalSeconds: intervalSeconds, retentionDays: retentionDays, columnCount: columnCount
            ))
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fanBarText("记录方式", "Recording mode"))
    }
}

private struct TemperatureLogPresetCard: View {
    let preset: TemperatureLogPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                    if preset == .everyday {
                        Text(fanBarText("推荐", "Recommended"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                    }
                    Spacer(minLength: 4)
                    // A radio dot repeats the selection without relying on the outline color alone.
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accentColor : Color(NSColor.tertiaryLabelColor))
                }
                .padding(.bottom, 2)
                Text(preset.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(preset.useCase)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(TemperatureLogText.facts(intervalSeconds: preset.intervalSeconds, retentionDays: preset.retentionDays))
                    .font(.system(size: 11).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SettingsChrome.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Everything technical, folded by default; the summary line shows the values.
struct TemperatureLogAdvancedCard: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var intervalSeconds: Int
    @Binding var retentionDays: Int
    @Binding var logTemperatures: Bool
    @Binding var logFanSpeeds: Bool

    @AppStorage(TemperatureLogPreferences.directoryKey)
    private var directoryPath = ""
    @AppStorage(TemperatureLogPreferences.newLogPolicyKey)
    private var newLogPolicyRawValue = TemperatureLogPreferences.defaultPolicy.rawValue
    @State private var expanded = false

    private var policy: Binding<TemperatureLogPreferences.NewLogPolicy> {
        Binding(
            get: { TemperatureLogPreferences.NewLogPolicy(rawValue: newLogPolicyRawValue) ?? TemperatureLogPreferences.defaultPolicy },
            set: { newLogPolicyRawValue = $0.rawValue }
        )
    }

    private var summary: String {
        "\(TemperatureLogText.facts(intervalSeconds: intervalSeconds, retentionDays: retentionDays)) · "
            + TemperatureLogText.policy(policy.wrappedValue)
    }

    var body: some View {
        SettingsChrome.settingsCard {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    Text(fanBarText("高级", "Advanced"))
                    Spacer(minLength: 8)
                    if !expanded {
                        Text(summary)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .settingsRow()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? fanBarText("已展开", "Expanded") : fanBarText("已收起", "Collapsed"))

            if expanded {
                rows
            }
        }
        .onChange(of: expanded) { _ in SettingsChrome.requestWindowRefit() }
    }

    @ViewBuilder
    private var rows: some View {
        SettingsChrome.rowDivider
        pickerRow(fanBarText("采样间隔", "Sampling interval"), selection: $intervalSeconds,
                  options: TemperatureLogPreferences.intervalOptions) { fanBarFormat("%d 秒", "%d s", $0) }
        SettingsChrome.rowDivider
        pickerRow(fanBarText("保留", "Keep"), selection: $retentionDays,
                  options: TemperatureLogPreferences.retentionOptions) {
            $0 == 0 ? fanBarText("永久", "Forever") : fanBarFormat("%d 天", "%d days", $0)
        }
        SettingsChrome.rowDivider
        pickerRow(fanBarText("新建文件", "New file"), selection: policy,
                  options: [.daily, .onStartup, .never], label: TemperatureLogText.policy)
        SettingsChrome.rowDivider
        HStack(spacing: 16) {
            Text(fanBarText("记录内容", "Logged Data"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(fanBarText("温度", "Temperatures"), isOn: $logTemperatures)
            Toggle(fanBarText("风扇转速和模式", "Fan speeds and mode"), isOn: $logFanSpeeds)
        }
        .toggleStyle(.checkbox)
        .settingsRow()
        SettingsChrome.rowDivider
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fanBarText("保存位置", "Save location"))
                Text((TemperatureLogSettings.current().directory.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(fanBarText("更改…", "Change…")) { TemperatureLogFolderPicker.choose() }
        }
        .settingsRow()
        .id(directoryPath)
    }

    private func pickerRow<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .id(languageRawValue)
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
    }
}
