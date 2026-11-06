import FanBarShared
import SwiftUI

/// General › Command Line & Automation: installs or removes the `fanbar` link on PATH.
/// The row stays out of builds that do not ship the tool.
struct CommandLineToolRow: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var installer: CommandLineToolInstaller

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SettingsRowText(title: fanBarText("命令行工具", "Command-line tool"), detail: detail)
                if let pathWarning {
                    Text(pathWarning)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = installer.failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let action {
                Button(action.title, action: action.perform)
                    .disabled(installer.isWorking)
            }
        }
        .settingsRow()
        .onAppear(perform: installer.refresh)
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private var detail: String {
        switch installer.state {
        case .unavailable, .notInstalled:
            fanBarText(
                "安装后可在终端用 fanbar 命令切换模式、查看状态。",
                "Lets Terminal and scripts switch modes and read status with the fanbar command."
            )
        case .needsMove:
            fanBarText(
                "请先将 FanBar 移到“应用程序”文件夹，再安装命令行工具。",
                "Move FanBar to the Applications folder before installing the command-line tool."
            )
        case .installed:
            fanBarText("已安装到 /usr/local/bin/fanbar。", "Installed at /usr/local/bin/fanbar.")
        case .linkedElsewhere:
            fanBarText(
                "/usr/local/bin/fanbar 指向另一份 FanBar，更新后将指向当前这份。",
                "/usr/local/bin/fanbar points to another copy of FanBar. Update it to use this one."
            )
        case .blocked:
            fanBarText(
                "/usr/local/bin/fanbar 已被其他文件占用，FanBar 不会覆盖它。",
                "/usr/local/bin/fanbar is used by another file, which FanBar will not replace."
            )
        }
    }

    /// Installed is not enough: the terminal must also reach this link.
    private var pathWarning: String? {
        switch installer.pathResolution {
        case .shadowed(let other):
            fanBarFormat(
                "终端会先找到 %@，不会用到这里安装的命令。请删除它或调整 PATH 顺序。",
                "Your shell finds %@ first, so it does not run this command. Remove it or reorder PATH.",
                other
            )
        case .notOnPath:
            fanBarText(
                "/usr/local/bin 不在终端的 PATH 中，终端找不到 fanbar。",
                "/usr/local/bin is not on your shell's PATH, so the shell cannot find fanbar."
            )
        case .resolvesToTool, nil:
            nil
        }
    }

    private var action: (title: String, perform: () -> Void)? {
        switch installer.state {
        case .notInstalled: (fanBarText("安装…", "Install…"), installer.install)
        case .linkedElsewhere: (fanBarText("更新链接…", "Update Link…"), installer.install)
        case .installed: (fanBarText("卸载…", "Uninstall…"), installer.uninstall)
        case .unavailable, .needsMove, .blocked: nil
        }
    }
}
