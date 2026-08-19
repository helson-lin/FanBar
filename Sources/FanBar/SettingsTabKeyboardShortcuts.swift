import SwiftUI

/// Hosts keyboard equivalents for the native title-bar navigation without
/// adding another visible control to the settings content.
struct SettingsTabKeyboardShortcuts: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            shortcutButton(for: .menuBar, key: "1")
            shortcutButton(for: .cooling, key: "2")
            shortcutButton(for: .general, key: "3")
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
