import FanBarShared
import Foundation

/// How macOS 11 and 12, which have no `SMAppService`, install and check the
/// root helper through launchd. Kept free of side effects so the commands can
/// be tested; `FanBarServiceManager` runs them with administrator rights.
enum LegacyHelperDaemon {
    /// The same label the `SMAppService` plist uses on macOS 13 and later.
    static let label = FanBarService.helperBundleID
    /// Early builds loaded the job under the plist's file name as its label.
    static let earlierLabel = FanBarService.helperPlistName
    /// launchd only bootstraps a system-domain plist owned by root and not
    /// writable by others, and only plists here survive a restart.
    static let installedPlistPath = "/Library/LaunchDaemons/\(FanBarService.helperPlistName)"

    /// Whether this macOS release registers the helper through launchd
    /// instead of `SMAppService`.
    static func isUsed(on os: OperatingSystemVersion) -> Bool {
        os.majorVersion < 13
    }

    static func helperExecutablePath(inAppAt bundleURL: URL) -> String {
        bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(FanBarService.helperBundleID)").path
    }

    static func jobDefinition(helperExecutablePath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [helperExecutablePath],
            "MachServices": [FanBarService.helperBundleID: true],
            "ProcessType": "Interactive"
        ]
    }

    /// Copies the user-owned staged plist into place as root:wheel 0644 and
    /// loads it from there. An already loaded job is removed first so an
    /// update or a moved app replaces it.
    static func installCommand(stagedPlistPath: String) -> String {
        let installed = shellQuote(installedPlistPath)
        return [
            unloadCommands,
            "/usr/bin/install -m 644 -o root -g wheel \(shellQuote(stagedPlistPath)) \(installed)"
                + " && /bin/launchctl enable system/\(label)"
                + " && /bin/launchctl bootstrap system \(installed)"
        ].joined(separator: "; ")
    }

    /// Unloads the job (fine when it is not loaded) and deletes its plist so
    /// it does not come back after a restart.
    static func removeCommand() -> String {
        [unloadCommands, "/bin/rm -f \(shellQuote(installedPlistPath))"].joined(separator: "; ")
    }

    static func status(jobIsLoaded: Bool) -> FanBarServiceStatus {
        jobIsLoaded ? .enabled : .notRegistered
    }

    private static var unloadCommands: String {
        [label, earlierLabel]
            .map { "/bin/launchctl bootout system/\($0) 2>/dev/null" }
            .joined(separator: "; ")
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
