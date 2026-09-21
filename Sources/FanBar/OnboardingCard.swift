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

            Divider()
                .padding(.horizontal, 34)
                .padding(.top, 28)

            HStack(alignment: .top, spacing: 24) {
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
            .padding(.horizontal, 34)
            .padding(.top, 22)

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
        .frame(width: 520, height: 430)
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

    private func onboardingFeature(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

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
}
