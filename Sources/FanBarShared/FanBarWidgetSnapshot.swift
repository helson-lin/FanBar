import Foundation

/// Errors surfaced while persisting or loading the shared widget snapshot.
public enum FanBarWidgetSnapshotError: Error, Equatable, Sendable {
    /// The App Group container could not be resolved. On macOS this usually
    /// means the running binary was not signed with the
    /// `com.apple.security.application-groups` entitlement (and, for a
    /// Developer ID build, an embedded provisioning profile granting it).
    case containerUnavailable
    /// The snapshot could not be encoded to JSON.
    case encodingFailed
    /// The snapshot file could not be written to disk. Carries the underlying
    /// error's description: when a shipped build cannot publish, that text is
    /// the only clue the log will contain about why.
    case writeFailed(reason: String)
}

/// The read-only telemetry snapshot shared by FanBar and its desktop widget.
///
/// FanBar is not sandboxed (it installs a privileged launch daemon) while the
/// widget extension is sandboxed. On macOS those two processes do NOT see the
/// same `UserDefaults(suiteName:)` storage: the non-sandboxed app writes to
/// `~/Library/Preferences/<group>.plist`, while the sandboxed extension reads
/// `~/Library/Group Containers/<group>/Library/Preferences/<group>.plist`.
/// Sharing therefore goes through a JSON file inside the App Group container,
/// which both sides resolve identically via `FileManager.containerURL`.
public struct FanBarWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Fan: Codable, Equatable, Sendable, Identifiable {
        public let index: Int
        public let currentRPM: Int
        public let minimumRPM: Int
        public let maximumRPM: Int
        public let isManual: Bool

        public var id: Int { index }

        public init(
            index: Int,
            currentRPM: Int,
            minimumRPM: Int,
            maximumRPM: Int,
            isManual: Bool
        ) {
            self.index = index
            self.currentRPM = currentRPM
            self.minimumRPM = minimumRPM
            self.maximumRPM = maximumRPM
            self.isManual = isManual
        }
    }

    public enum Mode: String, Codable, Equatable, Sendable {
        case automatic
        case temperatureCurve
        case fixed
    }

    public static let appGroupIdentifier = "64S5F787T9.local.fanbar.app"
    public static let kind = "local.fanbar.widget.v2"

    /// Relative path, inside the App Group container, of the shared snapshot file.
    private static let relativeStoragePath = "Library/Application Support/fanbar-widget-snapshot.json"

    public let updatedAt: Date
    public let fans: [Fan]
    public let cpuCelsius: Double?
    public let mode: Mode
    public let isAvailable: Bool
    public let isEnglish: Bool

    public init(
        updatedAt: Date = Date(),
        fans: [Fan],
        cpuCelsius: Double?,
        mode: Mode,
        isAvailable: Bool,
        isEnglish: Bool
    ) {
        self.updatedAt = updatedAt
        self.fans = fans
        self.cpuCelsius = cpuCelsius
        self.mode = mode
        self.isAvailable = isAvailable
        self.isEnglish = isEnglish
    }

    /// Resolves the shared snapshot file location inside the App Group container.
    ///
    /// - Parameter containerDirectory: Overrides the App Group container
    ///   directory. Tests inject a temporary directory here; production
    ///   callers should leave this `nil` so the real App Group container is used.
    private static func storageURL(
        containerDirectory: URL? = nil
    ) throws -> URL {
        let container: URL
        if let containerDirectory {
            container = containerDirectory
        } else if let resolved = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            container = resolved
        } else {
            throw FanBarWidgetSnapshotError.containerUnavailable
        }
        return container.appendingPathComponent(relativeStoragePath, isDirectory: false)
    }

    /// Persists the snapshot to the shared App Group container, atomically.
    ///
    /// - Parameter containerDirectory: Overrides the App Group container
    ///   directory (for tests). Production callers should omit this.
    /// - Throws: `FanBarWidgetSnapshotError` if the container cannot be
    ///   resolved, the snapshot cannot be encoded, or the write fails. This
    ///   never falls back to `UserDefaults.standard` -- a failure must be
    ///   observable to the caller rather than silently swallowed.
    @discardableResult
    public func save(containerDirectory: URL? = nil) throws -> URL {
        let url = try Self.storageURL(containerDirectory: containerDirectory)
        let data: Data
        do {
            data = try JSONEncoder().encode(self)
        } catch {
            throw FanBarWidgetSnapshotError.encodingFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw FanBarWidgetSnapshotError.writeFailed(
                reason: "\(url.path): \(error.localizedDescription)"
            )
        }
        return url
    }

    /// Loads the most recently saved snapshot, or `nil` if none exists yet or
    /// it could not be read/decoded. Missing-file and decode-failure cases
    /// are distinguished internally (see `LoadResult`) but collapse to `nil`
    /// here to keep the existing call-site contract.
    public static func load(containerDirectory: URL? = nil) -> Self? {
        switch loadResult(containerDirectory: containerDirectory) {
        case .success(let snapshot):
            return snapshot
        case .missing, .failure:
            return nil
        }
    }

    /// Fine-grained load result, distinguishing "no file yet" from a
    /// corrupt/undecodable file, for callers (and tests) that care.
    public enum LoadResult: Equatable, Sendable {
        case success(FanBarWidgetSnapshot)
        case missing
        case failure
    }

    public static func loadResult(containerDirectory: URL? = nil) -> LoadResult {
        guard let url = try? storageURL(containerDirectory: containerDirectory) else {
            return .failure
        }
        // Only an absent file is `.missing`. A read that fails for any other
        // reason -- most importantly a sandbox denial on the widget side --
        // is a real failure, and reporting it as `.missing` would disguise a
        // broken App Group grant as "the app has not published yet".
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure
        }
        guard let snapshot = try? JSONDecoder().decode(Self.self, from: data) else {
            return .failure
        }
        return .success(snapshot)
    }
}
