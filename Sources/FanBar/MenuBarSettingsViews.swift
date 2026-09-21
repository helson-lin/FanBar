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
        // Purely illustrative; each option row below carries the same sample.
        .accessibilityHidden(true)
    }
}

/// One selectable menu bar display style, with its own rendered sample.
struct MenuBarDisplayOptionRow: View {
    @ObservedObject var controller: FanController
    let mode: MenuBarDisplayMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)

                SettingsRowText(title: mode.title, detail: mode.detail)
                    .foregroundColor(.primary)

                MenuBarStatusLabel(controller: controller, displayMode: mode)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
            .padding(.vertical, SettingsChrome.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
