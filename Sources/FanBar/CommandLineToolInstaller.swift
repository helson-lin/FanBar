import AppKit
import FanBarShared
import Foundation

/// Links `/usr/local/bin/fanbar` to the CLI inside this app, like VS Code's
/// "Install 'code' command". The link points into the bundle, so Sparkle
/// updates the tool with the app and nothing is ever copied out.
///
/// Only links FanBar made are replaced or removed: a `fanbar` that is a
/// regular file, or a link into something other than a FanBar bundle, belongs
/// to someone else and is left alone.
@MainActor
final class CommandLineToolInstaller: ObservableObject {
    enum State: Equatable {
        /// This build has no `Contents/Helpers/fanbar` (e.g. `swift run`).
        case unavailable
        /// Running from a read-only disk image or a translocated copy; a link
        /// would dangle once the image is ejected or the copy is cleaned up.
        case needsMove
        case notInstalled
        case installed
        /// Links to another FanBar copy, e.g. one that was moved or replaced.
        case linkedElsewhere
        /// The path is taken by something FanBar did not create.
        case blocked
    }

    static let shared = CommandLineToolInstaller()
    nonisolated static let linkURL = URL(fileURLWithPath: "/usr/local/bin/fanbar")
    nonisolated static let toolRelativePath = "Contents/Helpers/fanbar"

    @Published private(set) var state: State = .unavailable
    @Published private var failureText: (() -> String)?
    var failure: String? { failureText?() }
    @Published private(set) var isWorking = false
    /// Which `fanbar` the user's shell runs once the link is installed. nil
    /// until the login shell has been read, or when not installed.
    @Published private(set) var pathResolution: LoginShellPath.Resolution?

    private let appURL: URL
    private let linkURL: URL
    /// Reads the login shell's PATH; injectable so tests never spawn a shell.
    private let readSearchPath: @Sendable () -> String?
    /// The shell is started once per app run; later checks only rescan the
    /// directories, so deleting a shadowing file shows up on the next refresh.
    private var cachedSearchPath: String?
    private var resolutionTask: Task<Void, Never>?

    init(
        appURL: URL = Bundle.main.bundleURL,
        linkURL: URL = CommandLineToolInstaller.linkURL,
        readSearchPath: @escaping @Sendable () -> String? = { LoginShellPath.read() }
    ) {
        self.appURL = appURL
        self.linkURL = linkURL
        self.readSearchPath = readSearchPath
        refresh()
    }

    private var toolURL: URL { appURL.appendingPathComponent(Self.toolRelativePath) }

    func refresh() {
        let readOnly = (try? toolURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        state = Self.state(toolURL: toolURL, linkURL: linkURL, isOnReadOnlyVolume: readOnly)
        refreshPathResolution()
    }

    private func refreshPathResolution() {
        resolutionTask?.cancel()
        guard state == .installed else {
            pathResolution = nil
            return
        }
        let tool = toolURL
        let cached = cachedSearchPath
        let readSearchPath = readSearchPath
        resolutionTask = Task { [weak self] in
            let searchPath = await Task.detached { cached ?? readSearchPath() }.value
            guard !Task.isCancelled, let self else { return }
            guard let searchPath else {
                // The shell could not be read; say nothing rather than guess.
                self.pathResolution = nil
                return
            }
            self.cachedSearchPath = searchPath
            self.pathResolution = LoginShellPath.resolution(of: "fanbar", in: searchPath, toolURL: tool)
        }
    }

    /// Waits for the PATH check started by the latest refresh (tests).
    func settlePathResolution() async {
        await resolutionTask?.value
    }

    func install() {
        guard [.notInstalled, .linkedElsewhere].contains(state) else { return }
        perform(
            shell: "/bin/mkdir -p \(Self.quoted(linkURL.deletingLastPathComponent().path)) && " +
                "/bin/ln -sfn \(Self.quoted(toolURL.path)) \(Self.quoted(linkURL.path))",
            prompt: fanBarText(
                "FanBar 想在 /usr/local/bin 中安装 fanbar 命令。",
                "FanBar wants to install the fanbar command in /usr/local/bin."
            ),
            failure: { fanBarFormat("无法安装命令行工具：%@", "Could not install the command-line tool: %@", $0) },
            directly: { [linkURL, toolURL] in
                let manager = FileManager.default
                try manager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? manager.destinationOfSymbolicLink(atPath: linkURL.path)) != nil {
                    try manager.removeItem(at: linkURL)
                }
                try manager.createSymbolicLink(at: linkURL, withDestinationURL: toolURL)
            }
        )
    }

    func uninstall() {
        // Refuse anything that is not one of our links, even if the UI is stale.
        refresh()
        guard [.installed, .linkedElsewhere].contains(state) else { return }
        perform(
            shell: "/bin/rm -f \(Self.quoted(linkURL.path))",
            prompt: fanBarText(
                "FanBar 想从 /usr/local/bin 中移除 fanbar 命令。",
                "FanBar wants to remove the fanbar command from /usr/local/bin."
            ),
            failure: { fanBarFormat("无法移除命令行工具：%@", "Could not remove the command-line tool: %@", $0) },
            directly: { [linkURL] in try FileManager.default.removeItem(at: linkURL) }
        )
    }

    /// Tries without privileges first: Intel Homebrew leaves `/usr/local/bin`
    /// owned by the user. Otherwise asks once for an administrator password.
    private func perform(
        shell: String,
        prompt: String,
        failure failureMessage: @escaping (String) -> String,
        directly: @escaping () throws -> Void
    ) {
        failureText = nil
        isWorking = true
        // Let the button show its working state before the password sheet blocks.
        DispatchQueue.main.async { [self] in
            defer {
                isWorking = false
                refresh()
            }
            if (try? directly()) != nil { return }
            let source = "do shell script \(Self.appleScriptString(shell)) " +
                "with prompt \(Self.appleScriptString(prompt)) with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard let error else { return }
            // -128: the user cancelled the password prompt; nothing to report.
            if error[NSAppleScript.errorNumber] as? Int == -128 { return }
            let detail = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            failureText = { failureMessage(detail) }
        }
    }

    // MARK: - Pure helpers

    nonisolated static func state(
        toolURL: URL,
        linkURL: URL,
        isOnReadOnlyVolume: Bool = false,
        fileManager: FileManager = .default
    ) -> State {
        guard fileManager.isExecutableFile(atPath: toolURL.path) else { return .unavailable }
        // A path under /Volumes is not enough: an Applications folder on an
        // external disk is a fine home. Disk images mount read-only.
        if isOnReadOnlyVolume || toolURL.path.contains("/AppTranslocation/") {
            return .needsMove
        }
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else {
            // No link: free unless a regular file or directory sits there.
            return fileManager.fileExists(atPath: linkURL.path) ? .blocked : .notInstalled
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: linkURL.deletingLastPathComponent())
            .standardizedFileURL.path
        if resolved == toolURL.standardizedFileURL.path { return .installed }
        return resolved.hasSuffix(".app/\(toolRelativePath)") ? .linkedElsewhere : .blocked
    }

    nonisolated static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
