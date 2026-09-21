import SwiftUI

/// Hosts keyboard equivalents for the native title-bar navigation without
/// adding another visible control to the settings content.
struct SettingsTabKeyboardShortcuts: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            // ⌘1…⌘3 follow the order of the toolbar items.
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element.id) { index, tab in
                shortcutButton(for: tab, key: Character(String(index + 1)))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func shortcutButton(for tab: SettingsTab, key: Character) -> some View {
        Button(tab.title) {
            selection = tab.rawValue
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
    }
}
