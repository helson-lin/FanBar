import AppKit
import FanBarShared
import Foundation
import ServiceManagement

enum FanBarServiceStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case unavailable
}

/// Provides one service-management API for modern SMAppService and Big Sur's
/// launchd fallback. The helper protocol remains identical on every release.
@MainActor
final class FanBarServiceManager {
    private(set) var status: FanBarServiceStatus = .notRegistered
    private var hasReportedStatus = false

    func refresh() {
        let previous = status
        defer {
            if !hasReportedStatus || previous != status {
                hasReportedStatus = true
                let outcome: RuntimeDiagnosticEvent.Outcome
                switch status {
                case .enabled: outcome = .enabled
                case .requiresApproval: outcome = .requiresApproval
                case .notRegistered: outcome = .notRegistered
                case .unavailable: outcome = .unavailable
                }
                RuntimeDiagnostics.shared.record(.service, .status, outcome)
            }
        }
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: FanBarService.helperPlistName)
            switch service.status {
            case .enabled:
                status = .enabled
            case .requiresApproval:
                status = .requiresApproval
            case .notRegistered, .notFound:
                status = .notRegistered
            @unknown default:
                status = .unavailable
            }
        } else {
            status = LegacyHelperDaemon.status(jobIsLoaded: LegacyLaunchd.jobIsLoaded(label: LegacyHelperDaemon.label))
        }
    }

    func register() throws {
        RuntimeDiagnostics.shared.record(.service, .register, .started)
        do {
            try registerService()
            RuntimeDiagnostics.shared.record(.service, .register, .succeeded)
        } catch {
            RuntimeDiagnostics.shared.record(.service, .register, .failed, code: (error as NSError).code)
            throw error
        }
    }

    private func registerService() throws {
        if #available(macOS 13.0, *) {
            if LegacyHelperDaemon.needsRemovalBeforeServiceManagement(
                on: ProcessInfo.processInfo.operatingSystemVersion,
                legacyPlistExists: FileManager.default.fileExists(atPath: LegacyHelperDaemon.installedPlistPath)
            ) {
                try LegacyLaunchd.removeHelper()
            }
            try SMAppService.daemon(plistName: FanBarService.helperPlistName).register()
        } else {
            try LegacyLaunchd.installHelper()
        }
        refresh()
    }

    func unregister() async throws {
        RuntimeDiagnostics.shared.record(.service, .unregister, .started)
        do {
            try await unregisterService()
            RuntimeDiagnostics.shared.record(.service, .unregister, .succeeded)
        } catch {
            RuntimeDiagnostics.shared.record(.service, .unregister, .failed, code: (error as NSError).code)
            throw error
        }
    }

    private func unregisterService() async throws {
        if #available(macOS 13.0, *) {
            try await SMAppService.daemon(plistName: FanBarService.helperPlistName).unregister()
        } else {
            try LegacyLaunchd.removeHelper()
        }
        refresh()
    }

    func openSettings() {
        RuntimeDiagnostics.shared.record(.service, .openSettings, .started)
        Self.openLoginItemsSettings()
    }

    static func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        // Big Sur's Login Items pane uses the older preference-pane URL.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.users?path=LoginItems",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ]
        for rawURL in urls {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

@MainActor
final class FanBarLoginItemManager {
    enum Status: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
    }

    private(set) var status: Status = .notRegistered

    func refresh() {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                status = .enabled
            case .requiresApproval:
                status = .requiresApproval
            case .notRegistered, .notFound:
                status = .notRegistered
            @unknown default:
                status = .notRegistered
            }
        } else {
            status = FileManager.default.fileExists(atPath: Self.legacyLaunchAgentURL.path)
                ? .enabled
                : .notRegistered
        }
    }

    func register() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
        } else {
            try LegacyLaunchd.installLoginItem(at: Self.legacyLaunchAgentURL)
        }
        refresh()
    }

    func unregister() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
        } else {
            try LegacyLaunchd.removeLoginItem(at: Self.legacyLaunchAgentURL)
        }
        refresh()
    }

    private static var legacyLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.fanbar.app.plist")
    }
}

private enum LegacyLaunchd {
    static func installHelper() throws {
        guard let teamID = LegacyHelperDaemon.installableTeam(OwnCodeSignature.teamIdentifier()) else {
            throw LegacyLaunchdError.unsignedBuild
        }
        let command = try LegacyHelperDaemon.installCommand(
            appBundlePath: Bundle.main.bundleURL.path,
            teamID: teamID,
            jobPlist: LegacyHelperDaemon.jobPlistText()
        )
        try runAsAdministrator(command, describedAs: "launchctl bootstrap system \(LegacyHelperDaemon.installedPlistPath)")
    }

    static func removeHelper() throws {
        try runAsAdministrator(
            LegacyHelperDaemon.removeCommand(),
            describedAs: "launchctl bootout system/\(LegacyHelperDaemon.label)"
        )
    }

    static func jobIsLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func installLoginItem(at url: URL) throws {
        let executablePath = Bundle.main.executableURL?.path ?? ""
        let plist: [String: Any] = [
            "Label": "local.fanbar.app",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        try write(plist, to: url)
        try runLaunchctl(["load", "-w", url.path])
    }

    static func removeLoginItem(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try runLaunchctl(["unload", "-w", url.path])
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func write(_ plist: [String: Any], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    private static func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LegacyLaunchdError.commandFailed(arguments.joined(separator: " "))
        }
    }

    private static func runAsAdministrator(_ command: String, describedAs description: String) throws {
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LegacyLaunchdError.commandFailed(description)
        }
    }

    private static func appleScriptQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private enum LegacyLaunchdError: LocalizedError {
    case commandFailed(String)
    case unsignedBuild

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command): fanBarFormat(
            "无法执行系统服务命令：%@",
            "Unable to run the system service command: %@",
            command
        )
        case .unsignedBuild: fanBarText(
            "未签名的 FanBar 无法安装控制服务",
            "An unsigned FanBar build can't install the control service"
        )
        }
    }
}
