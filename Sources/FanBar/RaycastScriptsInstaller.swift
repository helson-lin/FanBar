import AppKit
import CryptoKit
import Darwin
import FanBarShared
import Foundation

/// Hands the bundled Raycast Script Commands to Raycast with as few steps as
/// Raycast allows. Raycast has no way for another app to add a script
/// directory, so FanBar copies the scripts to a stable folder, puts that path
/// on the clipboard and opens Raycast; the user adds the folder once.
///
/// The folder lives outside the bundle so it survives app updates, and is
/// refreshed from the bundle at every launch once set up, so scripts update
/// with the app.
@MainActor
final class RaycastScriptsInstaller: ObservableObject {
    enum State: Equatable {
        /// This build has no bundled scripts (e.g. `swift run`).
        case unavailable
        case raycastMissing
        case ready
        /// Scripts were copied; Raycast still needs the folder once.
        case copied
    }

    static let shared = RaycastScriptsInstaller()
    nonisolated static let raycastBundleID = "com.raycast.macos"
    nonisolated static let downloadURL = URL(string: "https://www.raycast.com")!

    @Published private(set) var state: State = .unavailable
    @Published private var failureText: (() -> String)?
    var failure: String? { failureText?() }

    let destinationURL: URL
    private let sourceURL: URL?
    private let isRaycastInstalled: () -> Bool
    private let copyToPasteboard: (String) -> Void
    private let openRaycast: () -> Void

    init(
        sourceURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Raycast", isDirectory: true),
        destinationURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FanBar/Raycast", isDirectory: true),
        isRaycastInstalled: @escaping () -> Bool = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: RaycastScriptsInstaller.raycastBundleID) != nil
        },
        copyToPasteboard: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        openRaycast: @escaping () -> Void = {
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: RaycastScriptsInstaller.raycastBundleID
            ) else { return }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.isRaycastInstalled = isRaycastInstalled
        self.copyToPasteboard = copyToPasteboard
        self.openRaycast = openRaycast
        refresh()
    }

    private var bundledScripts: [URL] {
        guard let sourceURL else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func refresh() {
        if bundledScripts.isEmpty {
            state = .unavailable
        } else if !isRaycastInstalled() {
            state = .raycastMissing
        } else {
            state = FileManager.default.fileExists(atPath: destinationURL.path) ? .copied : .ready
        }
    }

    /// Copies the scripts, puts the folder path on the clipboard, opens Raycast.
    func setUp() {
        failureText = nil
        do {
            try copyScripts()
        } catch {
            let detail = error.localizedDescription
            failureText = {
                fanBarFormat(
                    "无法准备 Raycast 脚本：%@",
                    "Could not prepare the Raycast scripts: %@",
                    detail
                )
            }
            refresh()
            return
        }
        copyToPasteboard(destinationURL.path)
        openRaycast()
        refresh()
    }

    /// At launch: once the user has set up Raycast, keep the copy in step with
    /// this app version. Does nothing before the first setup.
    func syncIfSetUp() {
        guard FileManager.default.fileExists(atPath: destinationURL.path), !bundledScripts.isEmpty else { return }
        try? copyScripts()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    /// Name of the record of what FanBar last wrote, kept beside the scripts.
    nonisolated static let manifestName = ".fanbar-scripts.json"

    /// Writes the bundled scripts, but never over a user's edits: a script
    /// whose contents differ from what FanBar last wrote there belongs to the
    /// user now, and stays until they delete it. Retired scripts go only if
    /// unedited, and files FanBar never wrote are not touched at all.
    private func copyScripts() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let manifestURL = destinationURL.appendingPathComponent(Self.manifestName)
        let written = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        var manifest: [String: String] = [:]

        let bundled = bundledScripts
        for script in bundled {
            let name = script.lastPathComponent
            let target = destinationURL.appendingPathComponent(name)
            let contents = try Data(contentsOf: script)
            let bundledDigest = Self.digest(contents)
            if let current = try? Data(contentsOf: target) {
                let currentDigest = Self.digest(current)
                // Unknown to the manifest yet identical, or exactly what we wrote: ours.
                let isOurs = currentDigest == bundledDigest || currentDigest == written[name]
                guard isOurs else { continue }
                try manager.removeItem(at: target)
            }
            try contents.write(to: target)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            // A downloaded app's files can carry quarantine; Raycast runs these directly.
            removexattr(target.path, "com.apple.quarantine", 0)
            manifest[name] = bundledDigest
        }

        // Scripts dropped from a newer build must not linger as dead commands.
        let bundledNames = Set(bundled.map(\.lastPathComponent))
        for (name, digest) in written where !bundledNames.contains(name) {
            let target = destinationURL.appendingPathComponent(name)
            guard let current = try? Data(contentsOf: target) else { continue }
            if Self.digest(current) == digest {
                try manager.removeItem(at: target)
            }
        }

        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
