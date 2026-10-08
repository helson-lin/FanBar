import FanBarShared
import SwiftUI

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
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected
            ? fanBarFormat("已选择，第 %d 项，共 %d 项", "Selected, %d of %d", position, count)
            : fanBarFormat("第 %d 项，共 %d 项", "%d of %d", position, count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
