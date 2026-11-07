import AppKit
import FanBarShared
import SwiftUI

/// The General tab's opening answer to "can FanBar control the fans here?"
/// Kept free of SwiftUI so every state can be tested.
struct GeneralStatusSummary: Equatable {
    enum Level: Equatable {
        case normal
        case attention
        case unavailable
    }

    let level: Level
    let symbolName: String
    let title: String
    let detail: String
    /// The one action that moves the service toward enabled; nil when none applies.
    let actionTitle: String?

    /// `fanCount` is nil while no sample has been taken, and 0 when macOS
    /// reported no fans; the two say different things.
    static func make(helperState: FanController.HelperState, fanCount: Int?) -> Self {
        guard helperState == .enabled else {
            return Self(
                level: helperState == .unavailable ? .unavailable : .attention,
                symbolName: helperState.symbolName,
                title: helperState.noticeTitle,
                detail: helperState.noticeDetail,
                actionTitle: helperState.actionTitle
            )
        }
        if fanCount == 0 {
            return Self(
                level: .attention,
                // Distinct from `.unavailable`'s triangle: the readings are
                // missing, not the service.
                symbolName: "questionmark.circle",
                title: fanBarText("读不到风扇数据", "No fan data"),
                detail: fanBarText(
                    "这台 Mac 可能没有风扇，或 macOS 没有提供风扇读数。",
                    "This Mac may have no fans, or macOS doesn't report them."
                ),
                actionTitle: nil
            )
        }
        let safetyNet = fanBarText(
            "断开、睡眠或写入失败时，风扇会交回 macOS。",
            "Fans return to macOS on disconnect, sleep, or a failed write."
        )
        return Self(
            level: .normal,
            symbolName: helperState.symbolName,
            title: helperState.noticeTitle,
            detail: fanCount.map { "\(fanCountText($0)) · \(safetyNet)" } ?? safetyNet,
            actionTitle: nil
        )
    }

    static func fanCountText(_ count: Int) -> String {
        count == 1
            ? fanBarText("1 个风扇", "1 fan")
            : fanBarFormat("%d 个风扇", "%d fans", count)
    }
}

/// First block of the General tab: service status, fan count, the safety
/// net, and the way into the compatibility details. Replaces the former
/// "Control service" row and the "Device Compatibility" section.
struct GeneralStatusHeader: View {
    /// Repaints the copy when the interface language changes.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @ObservedObject var controller: FanController
    @Environment(\.colorScheme) private var colorScheme

    private var summary: GeneralStatusSummary {
        GeneralStatusSummary.make(
            helperState: controller.helperState,
            fanCount: controller.compatibilitySnapshot?.fanCount
        )
    }

    private func tint(for level: GeneralStatusSummary.Level) -> Color {
        let palette = PanelPalette(colorScheme: colorScheme)
        switch level {
        case .normal: return palette.accent
        case .attention: return palette.warm
        case .unavailable: return palette.hot
        }
    }

    var body: some View {
        let summary = summary
        HStack(alignment: .top, spacing: 12) {
            // A distinct symbol per state, so status never relies on color alone.
            Image(systemName: summary.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(tint(for: summary.level))
                .frame(width: 26, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    CompatibilityWindowPresenter.shared.show(controller: controller)
                } label: {
                    HStack(spacing: 2) {
                        Text(fanBarText("本机能力与兼容性", "This Mac’s capabilities and compatibility"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle = summary.actionTitle {
                Button(actionTitle, action: controller.performHelperAction)
            }
        }
        .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .id(languageRawValue)
    }
}
