import AppKit
import FanBarShared
import SwiftUI

/// Shared chrome for the settings window — system-settings style section headers,
/// inset cards, footers, and row dividers. Keeps Menu Bar / Cooling / General in sync.
enum SettingsChrome {
    static let contentWidth: CGFloat = 460
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 20
    static let headerToCardSpacing: CGFloat = 6
    static let cardCornerRadius: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 9

    static func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    static func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    static func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    static var cardBackground: some View {
        if #available(macOS 12.0, *) {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    static var rowDivider: some View {
        Divider().padding(.leading, rowHorizontalPadding)
    }

    /// Standard leading-aligned content row padding.
    static func rowPadding<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
    }

    /// Request the settings window to re-fit after disclosure or content height changes.
    @MainActor
    static func requestWindowRefit() {
        SettingsWindowPresenter.shared.resizeToFitContentSoon()
    }
}

/// Vertically stacks a section header, card, and optional footer with system spacing.
struct SettingsSection<Card: View>: View {
    let title: String
    var trailing: String?
    var footer: String?
    @ViewBuilder var card: () -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            SettingsChrome.sectionHeader(title, trailing: trailing)
            SettingsChrome.settingsCard(content: card)
            if let footer {
                SettingsChrome.sectionFooter(footer)
            }
        }
    }
}
