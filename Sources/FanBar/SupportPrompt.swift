import FanBarShared
import SwiftUI

/// The one-time request to support development, shown in the menu panel
/// after two weeks and never alongside a warning or failure notice.
enum SupportPrompt {
    /// When the panel first opened, as seconds since 1970; 0 until then.
    static let firstUseKey = "supportPrompt.firstUse"
    static let dismissedKey = "supportPrompt.dismissed"
    static let delay: TimeInterval = 14 * 24 * 60 * 60

    static func shouldShow(firstUse: TimeInterval, dismissed: Bool, now: Date, isShowingOtherNotice: Bool) -> Bool {
        guard !dismissed, !isShowingOtherNotice, firstUse > 0 else { return false }
        return now.timeIntervalSince1970 - firstUse >= delay
    }
}

/// A quiet notice row: one sentence, a filled Support button and a text dismissal.
struct SupportPromptRow: View {
    let onSupport: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(fanBarText(
                "FanBar 免费开源。如果它帮到了你，可以支持一下开发。",
                "FanBar is free and open source. If it helps you, consider supporting its development."
            ))
            .font(.system(size: 11))
            .foregroundColor(palette.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onSupport) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .accessibilityHidden(true)
                        Text(fanBarText("支持开发", "Support"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.surface)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PanelDimButtonStyle())
                .fixedSize()

                Button(action: onDismiss) {
                    Text(fanBarText("不再显示", "Don’t show again"))
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelDimButtonStyle())
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.track)
        )
        .accessibilityElement(children: .contain)
    }
}
