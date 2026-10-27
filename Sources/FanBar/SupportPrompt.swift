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

/// A quiet notice row: one sentence, a raised Support button and a text dismissal.
struct SupportPromptRow: View {
    let onSupport: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            // swiftlint:disable line_length
            Text(fanBarText(
                "FanBar 免费开源，由我业余开发，签名证书也是自费。如果它帮到了你，可以随意支持一下。",
                "FanBar is free and open source. I build it in my spare time and pay for its signing certificate myself. If it helps you, chip in any amount."
            ))
            .font(.system(size: 11))
            .foregroundColor(palette.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            // swiftlint:enable line_length

            HStack(spacing: 8) {
                Button(action: onSupport) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .accessibilityHidden(true)
                        Text(fanBarText("支持开发", "Support"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    // A raised secondary button: filled black buttons are kept for
                    // actions that fix something, such as authorizing the helper.
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.raised)
                            .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.hairline, lineWidth: 0.5)
                    )
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
