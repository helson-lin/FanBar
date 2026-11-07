import FanBarShared
import SwiftUI

/// The opt-in switch with its plain-language explanation. Shared by Settings
/// and onboarding so both say the same thing. Off unless the user turns it on.
struct UsageStatisticsRow: View {
    /// Settings shows the note beside the automatic-update switch it explains;
    /// onboarding has no such switch, so it leaves the note out.
    var showsAutomaticChecksNote = true
    /// Read so the row repaints when the interface language changes.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    /// Follows the stored value, so an answer given in the menu panel shows here at once.
    @AppStorage(UsageStatistics.enabledKey)
    private var isEnabled = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fanBarText("共享匿名使用统计", "Share anonymous usage statistics"))
                Text(UsageStatisticsCopy.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsAutomaticChecksNote {
                    Text(UsageStatisticsCopy.automaticChecksNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link(destination: FanBarLinks.usageStatisticsPrivacy(for: .current)) {
                    HStack(spacing: 4) {
                        Text(UsageStatisticsCopy.learnMore)
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                }
                .help(fanBarText("在浏览器中打开收集内容说明", "Open the description of what is collected in a browser"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(fanBarText("共享匿名使用统计", "Share anonymous usage statistics"), isOn: Binding(
                get: { isEnabled },
                set: {
                    UsageStatistics.shared.isEnabled = $0
                    if $0 { SoftwareUpdateController.shared.reportUsageIfPending() }
                }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityHint(UsageStatisticsCopy.detail)
        }
    }
}

enum UsageStatisticsCopy {
    static var detail: String {
        fanBarText(
            "每周随一次更新检查附带安装周、Mac 型号、macOS 版本和芯片类型；服务还会根据网络位置记录所在国家或地区。",
            // swiftlint:disable:next line_length
            "Adds the install week, Mac model, macOS version and chip type to one update check per week. The service also records the country or region from your network location."
        )
    }

    static var automaticChecksNote: String {
        fanBarText(
            "关闭自动检查更新后，只有手动检查更新时才会计数；除非打开此开关，否则只按版本号计数。",
            "With automatic checks off, only a manual update check is counted. It is counted by version only, unless this switch is on."
        )
    }

    static var learnMore: String { fanBarText("收集了什么", "What is collected") }
}

/// A quiet one-time question in the menu panel for people who installed
/// FanBar before this option existed. Dismissing it answers "no".
struct UsageStatisticsPromptRow: View {
    let onShare: () -> Void
    let onDecline: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(fanBarText("共享匿名使用统计？", "Share anonymous usage statistics?"))
                .font(.system(size: 11, weight: .semibold))
            Text(UsageStatisticsCopy.detail)
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(fanBarText("之后可在设置的“通用”里更改。", "You can change this later in Settings, under General."))
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onShare) {
                    Text(fanBarText("共享", "Share"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
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

                Button(action: onDecline) {
                    Text(fanBarText("不共享", "No thanks"))
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelDimButtonStyle())
                .fixedSize()

                Spacer(minLength: 0)

                Link(destination: FanBarLinks.usageStatisticsPrivacy(for: .current)) {
                    Text(UsageStatisticsCopy.learnMore)
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                        .underline()
                }
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
