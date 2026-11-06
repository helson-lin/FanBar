import FanBarShared
import SwiftUI

/// General › Command Line & Automation: the CLI and Raycast rows, each only in
/// builds that ship it. Both are opt-in ways to drive FanBar from outside, so
/// they sit apart from the app basics; with neither shipped, the section hides.
struct ToolIntegrationsSection: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    var tool: CommandLineToolInstaller = .shared
    var raycast: RaycastScriptsInstaller = .shared

    var body: some View {
        let showsTool = tool.state != .unavailable
        let showsRaycast = raycast.state != .unavailable
        if showsTool || showsRaycast {
            SettingsSection(
                title: fanBarText("命令行与自动化", "Command Line & Automation"),
                footer: fanBarText(
                    "两者都通过 FanBar 控制风扇；FanBar 未运行时会在后台打开它。",
                    "Both control the fans through FanBar, and open it in the background when it is not running."
                )
            ) {
                if showsTool {
                    CommandLineToolRow(installer: tool)
                }
                if showsTool, showsRaycast {
                    SettingsChrome.rowDivider
                }
                if showsRaycast {
                    RaycastRow(installer: raycast)
                }
            }
            // The translation helpers read UserDefaults outside SwiftUI's
            // dependency tracking. Observe the preference here and rebuild the
            // rows too, even when their installer objects have not changed.
            .id(languageRawValue)
        }
    }
}

/// General › Command Line & Automation: hands the Raycast Script Commands to Raycast.
/// Raycast's own menu names stay in English: Raycast is not localized.
struct RaycastRow: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var installer: RaycastScriptsInstaller

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SettingsRowText(title: "Raycast", detail: detail)
                if installer.state == .copied {
                    Button(fanBarText("在 Finder 中显示", "Show in Finder"), action: installer.revealInFinder)
                        .buttonStyle(.link)
                        .font(.caption)
                }
                if let failure = installer.failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch installer.state {
            case .raycastMissing:
                Button(fanBarText("获取 Raycast…", "Get Raycast…")) {
                    NSWorkspace.shared.open(RaycastScriptsInstaller.downloadURL)
                }
            case .ready, .copied:
                Button(fanBarText("在 Raycast 中设置…", "Set Up in Raycast…"), action: installer.setUp)
            case .unavailable:
                EmptyView()
            }
        }
        .settingsRow()
        .onAppear(perform: installer.refresh)
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private var detail: String {
        switch installer.state {
        case .raycastMissing:
            fanBarText(
                "安装 Raycast 后，可以在 Raycast 中控制 FanBar。",
                "Install Raycast to control FanBar from it."
            )
        case .unavailable, .ready:
            fanBarText(
                "在 Raycast 中切换预设、固定转速、查看温度。",
                "Switch presets, set a fixed speed and see temperatures from Raycast."
            )
        case .copied:
            // One literal per language: the catalog scanner reads whole literals.
            // swiftlint:disable line_length
            fanBarText(
                "脚本已放在 FanBar 的 Raycast 文件夹。若 Raycast 中还没有：在其设置 › Extensions 点 + › Add Script Directory，按 ⌘⇧G 粘贴本按钮复制的路径。",
                "The scripts are in FanBar's Raycast folder. If Raycast does not list them yet: in its Settings › Extensions, click + › Add Script Directory, press ⌘⇧G and paste the path this button copies."
            )
            // swiftlint:enable line_length
        }
    }
}
