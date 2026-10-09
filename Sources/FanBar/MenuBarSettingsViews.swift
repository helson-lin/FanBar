import FanBarShared
import SwiftUI

/// A stylized menu bar with FanBar's live status label between the system
/// items, so the display choice is judged in context.
struct MenuBarPreviewStrip: View {
    @ObservedObject var controller: FanController
    let displayMode: MenuBarDisplayMode
    @Environment(\.colorScheme) private var colorScheme

    private var wallpaper: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.23, green: 0.30, blue: 0.42), Color(red: 0.34, green: 0.25, blue: 0.43)]
            : [Color(red: 0.62, green: 0.71, blue: 0.84), Color(red: 0.79, green: 0.72, blue: 0.85)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            MenuBarStatusLabel(controller: controller, displayMode: displayMode)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.14)))
            Text(Date(), style: .time)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(wallpaper)
        // Purely illustrative; each option row below carries the same sample,
        // so VoiceOver users lose nothing by skipping it.
        .accessibilityHidden(true)
    }
}

/// One selectable menu bar display style, with its own rendered sample.
struct MenuBarDisplayOptionRow: View {
    @ObservedObject var controller: FanController
    let mode: MenuBarDisplayMode
    let isSelected: Bool
    /// 1-based place in the option list, read out by VoiceOver because
    /// these rows are custom buttons rather than a native radio group.
    let position: Int
    let count: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                // Weight joins the filled radio, so selection never rests on tint alone.
                SettingsRowText(
                    title: mode.title,
                    detail: mode.detail,
                    titleWeight: isSelected ? .medium : .regular
                )
                .foregroundColor(.primary)

                MenuBarStatusLabel(controller: controller, displayMode: mode)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            // With the group's inset, the radio lines up with other rows' text.
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding - SettingsChrome.choiceInset)
            .padding(.vertical, SettingsChrome.rowVerticalPadding)
            .background(SettingsChrome.choiceHighlight(isSelected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected
            ? fanBarFormat("已选择，第 %d 项，共 %d 项", "Selected, %d of %d", position, count)
            : fanBarFormat("第 %d 项，共 %d 项", "%d of %d", position, count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The icon row of the Menu Bar card. A pop-up menu scales to any number of
/// glyphs; each item shows its glyph beside the name, and the display rows
/// below preview the chosen one at real size.
struct MenuBarIconStylePicker: View {
    @ObservedObject var controller: FanController
    @AppStorage(MenuBarIconStyle.preferenceKey)
    private var selectedRawValue = MenuBarIconStyle.defaultStyle.rawValue

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowText(
                title: fanBarText("图标", "Icon"),
                detail: fanBarText(
                    "由 FanBar 控制风扇时，图标中心变为实心。",
                    "The hub turns solid while FanBar controls the fans."
                )
            )
            Picker(fanBarText("菜单栏图标", "Menu bar icon"), selection: $selectedRawValue) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    HStack {
                        Image(nsImage: style.image(isManual: controller.isManualStatus))
                            .renderingMode(.template)
                        Text(style.title)
                    }
                    .tag(style.rawValue)
                }
            }
            .labelsHidden()
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
    }
}
