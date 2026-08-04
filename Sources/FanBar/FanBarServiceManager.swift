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
    static let helperLabel = FanBarService.helperPlistName

    private(set) var status: FanBarServiceStatus = .notRegistered

    func refresh() {
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
            status = legacyServiceIsRunning() ? .enabled : .notRegistered
        }
    }

    func register() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.daemon(plistName: FanBarService.helperPlistName).register()
        } else {
            try LegacyLaunchd.installHelper()
        }
        refresh()
    }

    func unregister() async throws {
        if #available(macOS 13.0, *) {
            try await SMAppService.daemon(plistName: FanBarService.helperPlistName).unregister()
        } else {
            try LegacyLaunchd.removeHelper()
        }
        refresh()
    }

    func openSettings() {
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

    private func legacyServiceIsRunning() -> Bool {
        LegacyLaunchd.jobIsLoaded(label: FanBarService.helperPlistName)
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
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local.fanbar.helper.\(ProcessInfo.processInfo.processIdentifier).plist")
        let helperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/FanBarHelper").path
        let plist: [String: Any] = [
            "Label": FanBarService.helperPlistName,
            "ProgramArguments": [helperPath],
            "MachServices": [FanBarService.helperBundleID: true],
            "ProcessType": "Interactive"
        ]
        try write(plist, to: plistURL)
        defer { try? FileManager.default.removeItem(at: plistURL) }
        try runAsAdministrator("/bin/launchctl bootstrap system \(shellQuote(plistURL.path))")
    }

    static func removeHelper() throws {
        try runAsAdministrator("/bin/launchctl bootout system/\(FanBarService.helperPlistName)")
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

    private static func runAsAdministrator(_ command: String) throws {
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LegacyLaunchdError.commandFailed(command)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command): fanBarFormat(
            "无法执行系统服务命令：%@",
            "Unable to run the system service command: %@",
            command
        )
        }
    }
}
