import FanBarShared
import SwiftUI

/// The four cooling presets as one control: selecting a tile edits that
/// preset's curve, and its checkbox decides whether the menu panel shows it.
struct CoolingPresetTiles: View {
    @ObservedObject var controller: FanController
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var visiblePresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @State private var notice: String?

    private static let menuPresetLimit = 2

    private var menuPresets: [FanCoolingPreset] {
        CoolingPresetPreferences.presets(from: visiblePresetsRawValue)
    }

    private var menuLimitMessage: String {
        fanBarText(
            "菜单面板最多显示 2 个预设，请先取消勾选另一个。",
            "The menu panel shows up to two presets. Uncheck another one first."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            SettingsChrome.sectionHeader(
                fanBarText("预设", "Presets"),
                trailing: fanBarFormat(
                    "菜单里显示 %d / %d",
                    "Shown in menu %d / %d",
                    menuPresets.count,
                    Self.menuPresetLimit
                )
            )

            HStack(spacing: 8) {
                ForEach(FanCoolingPreset.allCases) { preset in
                    tile(for: preset)
                }
            }

            SettingsChrome.sectionFooter(notice ?? fanBarText(
                "点按预设编辑它的曲线。勾选“显示在菜单”后，该预设会作为快捷按钮出现在菜单面板里，最多 2 个。",
                "Select a preset to edit its curve. Check “Show in menu” to add it as a shortcut button in the menu panel, up to two."
            ))
        }
    }

    private func tile(for preset: FanCoolingPreset) -> some View {
        let isSelected = controller.curveCoolingPreset == preset
        let isRunning = isSelected && controller.mode == .temperatureCurve
        let profile = controller.curveProfile(for: preset)
        let shape = RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)

        return VStack(spacing: 0) {
            Button {
                controller.selectCoolingCurvePreset(preset, enableControl: false)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                        Text(preset.title)
                            .font(.system(size: 13, weight: .semibold))
                    }

                    PresetCurveThumbnail(profile: profile)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(height: 30)
                        .padding(.vertical, 2)

                    HStack {
                        Text("≤\(Int((profile.peakFraction * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        if isRunning {
                            Label(fanBarText("运行中", "Running"), systemImage: "circle.fill")
                                .labelStyle(RunningLabelStyle())
                        }
                    }
                    .frame(minHeight: 14)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preset.title)
            .accessibilityValue(isRunning ? fanBarText("运行中", "Running") : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Divider()

            menuToggle(for: preset)
        }
        .background(SettingsChrome.cardBackground)
        .clipShape(shape)
        .overlay(
            shape.stroke(
                isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                lineWidth: isSelected ? 2 : 0.5
            )
        )
    }

    /// A labeled checkbox: whether this preset is a shortcut in the menu panel.
    private func menuToggle(for preset: FanCoolingPreset) -> some View {
        let isShown = menuPresets.contains(preset)
        let isBlocked = !isShown && menuPresets.count >= Self.menuPresetLimit

        return Button {
            toggleMenuShortcut(preset, isShown: isShown)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isShown ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isShown ? .accentColor : .secondary)
                Text(fanBarText("显示在菜单", "Show in menu"))
                    .font(.system(size: 11))
                    .foregroundColor(isShown ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .opacity(isBlocked ? 0.45 : 1)
        .help(isBlocked ? menuLimitMessage : fanBarFormat(
            "在菜单面板里为“%@”显示快捷按钮",
            "Show a shortcut button for %@ in the menu panel",
            preset.title
        ))
        .accessibilityLabel(fanBarFormat(
            "在菜单面板显示“%@”",
            "Show %@ in the menu panel",
            preset.title
        ))
        .accessibilityValue(isShown ? fanBarText("已勾选", "On") : fanBarText("未勾选", "Off"))
        .accessibilityAddTraits(.isButton)
    }

    private func toggleMenuShortcut(_ preset: FanCoolingPreset, isShown: Bool) {
        var selection = Set(menuPresets)
        if isShown {
            selection.remove(preset)
        } else {
            guard selection.count < Self.menuPresetLimit else {
                // Blocked pins stay tappable so the reason is always reachable.
                notice = menuLimitMessage
                return
            }
            selection.insert(preset)
        }
        notice = nil
        visiblePresetsRawValue = CoolingPresetPreferences.rawValue(for: selection)
    }
}

/// A tiny outline of a preset's curve across the full temperature range.
private struct PresetCurveThumbnail: Shape {
    let profile: FanCurveProfile

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        let lower = FanCurveProfile.minimumCelsius
        let span = FanCurveProfile.maximumCelsius - lower
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let fraction = Double(profile.fraction(at: lower + span * t))
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(t),
                y: rect.maxY - rect.height * CGFloat(fraction)
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct RunningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundColor(.green)
            configuration.title
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
