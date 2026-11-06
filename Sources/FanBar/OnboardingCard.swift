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
/// model, shows the real status item to look for and a live preview of the
/// real panel, then hands the user directly into the real popover.
struct OnboardingCard: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    static let width: CGFloat = 580

    /// The permission notice only appears before the helper is approved; without it the
    /// window is shorter rather than ending in an empty band.
    static func height(for helperState: FanController.HelperState) -> CGFloat {
        helperState == .enabled ? 548 : 626
    }

    @ObservedObject var controller: FanController
    let onOpenMenu: () -> Void
    let onDismiss: () -> Void

    @AppStorage(MenuBarDisplayMode.preferenceKey)
    private var displayModeRawValue = MenuBarDisplayMode.defaultMode.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    private var palette: PanelPalette { PanelPalette(colorScheme: colorScheme) }

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRawValue) ?? .defaultMode
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewStage

                    VStack(alignment: .leading, spacing: 6) {
                        Text(fanBarText("FanBar 已经在运行", "FanBar is running"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(fanBarText(
                            "它常驻在屏幕顶部的菜单栏，不会出现在程序坞中。",
                            "It lives in the menu bar at the top of your screen and does not appear in the Dock."
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    featuresCard

                    if controller.helperState != .enabled {
                        controlServiceNotice
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            Divider()

            HStack {
                Button(fanBarText("稍后", "Not now"), action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(palette.secondaryText)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: onOpenMenu) {
                    HStack(spacing: 6) {
                        Text(fanBarText("打开菜单栏面板", "Open menu bar panel"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.surface)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PanelDimButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: Self.width, height: Self.height(for: controller.helperState))
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
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    // MARK: Preview

    /// The real status item to look for beside a live, scaled-down copy of the real panel.
    /// Both are the shipping views, so the preview can never drift from what the user gets.
    private var previewStage: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fanBarText("在菜单栏找这个图标", "Look for this in the menu bar"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    MenuBarStatusLabel(controller: controller, displayMode: displayMode)
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.12)))
                    Text(fanBarText("样子跟随“外观”里的设置。", "It follows your Appearance settings."))
                        .font(.system(size: 11))
                        .foregroundColor(palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fanBarText("点开就是这个面板", "Click it to open this panel"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(fanBarText("右侧是这台 Mac 此刻的真实读数。", "On the right: this Mac’s live readings."))
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Let the copy column give way so the stage never overflows the scroll
            // view's width (it would shift sideways, more so with a visible scroller).
            .frame(maxWidth: 172, alignment: .leading)
            .padding(20)

            Spacer(minLength: 0)

            FanMenu(controller: controller)
                .frame(width: FanMenu.panelWidth, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.8)
                )
                .scaleEffect(0.8, anchor: .topLeading)
                .frame(width: FanMenu.panelWidth * 0.8, height: 190, alignment: .topLeading)
                .clipped()
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .padding(.top, 20)
                .padding(.trailing, 20)
                .allowsHitTesting(false)
                // A picture of the panel, not a second set of controls: keep its buttons out of
                // the key-view loop so the window never opens with a focus ring inside it.
                .disabled(true)
                .accessibilityHidden(true)
        }
        .frame(height: 210)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.track)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Features

    private var featuresCard: some View {
        SettingsChrome.settingsCard {
            VStack(alignment: .leading, spacing: 0) {
                onboardingFeature(
                    icon: FanBarSymbols.gauge,
                    title: fanBarText("一眼看风扇是否正常", "See at a glance whether the fans are fine"),
                    detail: fanBarText(
                        "标题直接写出状态和由谁控制；温度过高时会提醒。",
                        "The panel says how the fans are and who controls them, and warns you when it gets too hot."
                    )
                )
                SettingsChrome.rowDivider
                onboardingFeature(
                    icon: "arrow.triangle.2.circlepath",
                    title: fanBarText("需要时再接管", "Take over only when you need to"),
                    detail: fanBarText(
                        "日常保持自动；可切到均衡、极速或固定，随时切回。",
                        "Stay on Auto day to day; switch to a preset or a fixed speed, and back, at any time."
                    )
                )
            }
        }
    }

    /// Same quiet notice as the panel's: neutral, and the action is secondary to opening the panel.
    private var controlServiceNotice: some View {
        let state = controller.helperState
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(state == .unavailable ? palette.hot : palette.secondaryText)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(fanBarText("切换模式需要一次性授权", "Switching modes needs one-time permission"))
                    .font(.system(size: 12, weight: .semibold))
                Text(fanBarText("不授权也能查看温度和转速。", "Temperatures and fan speeds work without it."))
                    .font(.system(size: 11))
                    .foregroundColor(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle = state.actionTitle {
                Button(actionTitle, action: controller.performHelperAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.track)
        )
        .accessibilityElement(children: .contain)
    }

    private func onboardingFeature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(palette.secondaryText)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
