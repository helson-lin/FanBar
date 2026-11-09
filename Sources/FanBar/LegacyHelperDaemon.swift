import FanBarShared
import Foundation

/// How macOS 11 and 12, which have no `SMAppService`, install and check the
/// root helper through launchd. Kept free of side effects so the commands can
/// be tested; `FanBarServiceManager` runs them with administrator rights.
///
/// Legacy launchd checks neither the daemon's signature nor who can write it,
/// so everything root runs is a root-owned copy: the helper (with the Info.plist
/// it reads its build from and the Swift concurrency runtime macOS 11 lacks) is
/// copied out of the user-writable app, its signature is verified after the copy,
/// and the job plist is written by the root script itself.
enum LegacyHelperDaemon {
    /// The same label the `SMAppService` plist uses on macOS 13 and later.
    static let label = FanBarService.helperBundleID
    /// Early builds loaded the job under the plist's file name as its label.
    static let earlierLabel = FanBarService.helperPlistName
    /// launchd only bootstraps a system-domain plist owned by root and not
    /// writable by others, and only plists here survive a restart.
    static let installedPlistPath = "/Library/LaunchDaemons/\(FanBarService.helperPlistName)"
    /// Mirrors the app's layout so the helper's relative paths
    /// (`../../../Info.plist`, `../../Frameworks`) keep working.
    static let installedRootPath = "/Library/PrivilegedHelperTools/\(FanBarService.helperBundleID)"
    static let helperRelativePath = "Contents/Library/LaunchServices/\(FanBarService.helperBundleID)"
    static let concurrencyRuntimeRelativePath = "Contents/Frameworks/libswift_Concurrency.dylib"
    static var installedHelperPath: String { "\(installedRootPath)/\(helperRelativePath)" }

    /// Whether this macOS release registers the helper through launchd
    /// instead of `SMAppService`.
    static func isUsed(on os: OperatingSystemVersion) -> Bool {
        os.majorVersion < 13
    }

    /// After an upgrade from macOS 11 or 12 the legacy job still loads at boot
    /// under the label `SMAppService` registers, so it must go first.
    static func needsRemovalBeforeServiceManagement(on os: OperatingSystemVersion, legacyPlistExists: Bool) -> Bool {
        !isUsed(on: os) && legacyPlistExists
    }

    /// The team whose helper may be installed. Unsigned and ad-hoc builds have
    /// none; their helper would reject every client anyway, so nothing is installed.
    static func installableTeam(_ teamID: String?) -> String? {
        guard let teamID, !teamID.isEmpty else { return nil }
        return teamID
    }

    /// Only the FanBar helper signed by the app's own team may run as root.
    static func helperRequirement(teamID: String) -> String {
        "anchor apple generic and identifier \"\(FanBarService.helperBundleID)\" "
            + "and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    static func runtimeRequirement(teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    static func jobDefinition() -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [installedHelperPath],
            "MachServices": [FanBarService.helperBundleID: true],
            "ProcessType": "Interactive"
        ]
    }

    /// The job plist on one line. Every value is a constant without line
    /// breaks, so dropping the indentation keeps the property list intact and
    /// lets the root script write it with a single `printf`.
    static func jobPlistText() throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: jobDefinition(), format: .xml, options: 0)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
    }

    /// Unloads any loaded job, copies the helper out of the app into a fresh
    /// root-owned directory, verifies the copy's signature, writes the job plist
    /// as root:wheel 0644 and loads it. Any failed step stops the script.
    static func installCommand(appBundlePath: String, teamID: String, jobPlist: String) -> String {
        let source = appBundlePath.hasSuffix("/") ? String(appBundlePath.dropLast()) : appBundlePath
        let root = shellQuote(installedRootPath)
        let helper = shellQuote(installedHelperPath)
        let runtime = shellQuote("\(installedRootPath)/\(concurrencyRuntimeRelativePath)")
        let sourceRuntime = shellQuote("\(source)/\(concurrencyRuntimeRelativePath)")
        let plist = shellQuote(installedPlistPath)
        let steps = [
            "/bin/rm -rf \(root)",
            "/bin/mkdir -p \(shellQuote("\(installedRootPath)/Contents/Library/LaunchServices"))"
                + " \(shellQuote("\(installedRootPath)/Contents/Frameworks"))",
            "/usr/bin/ditto \(shellQuote("\(source)/Contents/Info.plist")) \(shellQuote("\(installedRootPath)/Contents/Info.plist"))",
            "/usr/bin/ditto \(shellQuote("\(source)/\(helperRelativePath)")) \(helper)",
            "{ [ ! -e \(sourceRuntime) ] || /usr/bin/ditto \(sourceRuntime) \(runtime); }",
            "/usr/sbin/chown -R root:wheel \(root)",
            "/bin/chmod -R go-w \(root)",
            "/usr/bin/codesign --verify --strict -R \(shellQuote("=" + helperRequirement(teamID: teamID))) \(helper)",
            "{ [ ! -e \(runtime) ] || /usr/bin/codesign --verify --strict"
                + " -R \(shellQuote("=" + runtimeRequirement(teamID: teamID))) \(runtime); }",
            "/usr/bin/printf '%s' \(shellQuote(jobPlist)) > \(plist)",
            "/usr/sbin/chown root:wheel \(plist)",
            "/bin/chmod 644 \(plist)",
            "/bin/launchctl enable system/\(label)",
            "/bin/launchctl bootstrap system \(plist)"
        ]
        return ["umask 022", unloadCommands, steps.joined(separator: " && ")].joined(separator: "; ")
    }

    /// Unloads the job (fine when it is not loaded) and deletes its plist and
    /// helper copy so nothing comes back after a restart.
    static func removeCommand() -> String {
        [
            unloadCommands,
            "/bin/rm -f \(shellQuote(installedPlistPath))",
            "/bin/rm -rf \(shellQuote(installedRootPath))"
        ].joined(separator: "; ")
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
