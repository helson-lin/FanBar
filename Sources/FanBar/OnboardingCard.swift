import AppKit
import FanBarShared
import SwiftUI

enum OnboardingPreferences {
    static let completionKey = "fanbar.onboarding.v1.completed"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completionKey)
    }

    static func complete() {
        UserDefaults.standard.set(true, forKey: completionKey)
    }
}

/// The first screen FanBar shows. It explains the unusual menu-bar-only app
/// model before handing the user directly into the real popover.
struct OnboardingCard: View {
    /// Fixed window height. Tall enough to hold the control-service notice on
    /// a genuine first launch (permission is almost never granted yet); when
    /// the notice doesn't apply, the footer spacer absorbs the extra room.
    static let height: CGFloat = 478

    @ObservedObject var controller: FanController
    let onOpenMenu: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 0) {
            statusBarIllustration
                .padding(.top, 34)

            VStack(spacing: 10) {
                Text(fanBarText("FanBar 已经在运行", "FanBar is running"))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))

                Text(fanBarText(
                    "它常驻在屏幕顶部的菜单栏，不会显示在程序坞中。",
                    "It lives in the menu bar at the top of your screen and does not appear in the Dock."
                ))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 390)
            }
            .padding(.top, 25)

            featuresCard
                .padding(.horizontal, 34)
                .padding(.top, 26)

            Spacer(minLength: 24)

            HStack {
                Button(fanBarText("稍后", "Not now"), action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: onOpenMenu) {
                    HStack(spacing: 7) {
                        Text(fanBarText("打开菜单栏面板", "Open menu bar panel"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(DefaultButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(Color.primary.opacity(0.035))
        }
        .frame(width: 520, height: Self.height)
        .background(Color(NSColor.windowBackgroundColor))
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    isVisible = true
                }
            }
        }
    }

    private var statusBarIllustration: some View {
        VStack(spacing: 11) {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.055))

                HStack(spacing: 13) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                    Image(systemName: "fan")
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.13))
                        )
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.trailing, 13)
            }
            .frame(width: 280, height: 46)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fanBarText(
                "屏幕顶部菜单栏中的 FanBar 风扇图标",
                "The FanBar fan icon in the menu bar at the top of the screen"
            ))

            HStack(spacing: 6) {
                Text(fanBarText("在这里找到", "Find it here"))
                Image(systemName: "arrow.up")
            }
            .font(.caption.weight(.medium))
            .foregroundColor(.accentColor)
        }
    }

    /// One grouped card instead of bare rows on the window background: the
    /// same inset-card language as the settings window and the menu panel's
    /// own gauge panel, so this first screen reads as FanBar rather than a
    /// generic system dialog.
    private var featuresCard: some View {
        SettingsChrome.settingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    onboardingFeature(
                        icon: "gauge.with.dots.needle.67percent",
                        title: fanBarText("查看实时状态", "Check live status"),
                        detail: fanBarText("温度、风扇转速与当前模式", "Temperature, fan speed, and current mode")
                    )

                    onboardingFeature(
                        icon: "slider.horizontal.3",
                        title: fanBarText("按需调整散热", "Adjust cooling"),
                        detail: fanBarText("日常使用可保持系统自动管理", "Keep automatic control for everyday use")
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if controller.helperState != .enabled {
                    SettingsChrome.rowDivider
                    controlServiceNotice
                }
            }
        }
    }

    /// Adjusting fans needs a one-time, Team-ID-scoped permission that a brand
    /// new install has not granted yet. Naming that up front — using the same
    /// per-state copy the menu panel and settings share (`HelperStateDisplay`)
    /// — means the first thing a user tries to control never silently no-ops.
    /// It shares the features card above it rather than floating its own
    /// separate colored panel; only the row tint carries the emphasis.
    private var controlServiceNotice: some View {
        let state = controller.helperState
        return HStack(alignment: .top, spacing: 10) {
            featureIcon(state.symbolName, tint: state.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(fanBarText("按需调整散热需要一次性授权", "Adjusting cooling needs one-time permission"))
                    .font(.system(size: 12, weight: .semibold))
                Text(state.noticeDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle = state.actionTitle {
                Button(actionTitle, action: controller.performHelperAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(state.tint.opacity(0.08))
        .accessibilityElement(children: .contain)
    }

    private func onboardingFeature(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            featureIcon(icon, tint: .accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tinted icon chip. Echoes the fan icon's own chip in the illustration
    /// above, so the card below reads as a continuation of it, not a
    /// separate, flatter block bolted onto the same window.
    private func featureIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.13))
            )
            .accessibilityHidden(true)
    }
}
