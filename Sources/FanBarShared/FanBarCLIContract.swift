import Foundation

/// Wire contract between the `fanbar` command-line tool and the running app.
///
/// The CLI never talks to the root helper: the helper only trusts the signed
/// app, restores macOS control as soon as its last client disconnects, and has
/// no notion of curves. The app owns all of that, so the CLI sends one JSON
/// request per connection over a per-user Unix socket and the app replies with
/// one JSON response.
public enum FanBarCLIContract {
    public static let version = 1
    /// Requests are a handful of fields; anything larger is not ours.
    public static let maximumMessageBytes = 64 * 1_024
    public static let socketDirectoryName = "FanBar"
    public static let socketFileName = "cli.sock"

    public static let fallbackSocketFileName = "local.fanbar.cli.sock"

    /// The most the app may spend on one request: waiting out a switch already
    /// in flight, then its own switch, at the helper's worst-case write time.
    public static let commandTimeout = FanControlTiming.writeReplyTimeout(
        fanCount: FanControlTiming.maximumFanCount,
        base: 10
    )
    /// The CLI waits longer than the app can take, so a slow switch is never
    /// reported as a lost connection while it is still being applied.
    public static let replyTimeout = commandTimeout + 15

    /// `~/Library/Application Support/FanBar/cli.sock`, or, when that does not
    /// fit in `sockaddr_un` (long user names, relocated homes), a socket in the
    /// per-user temporary directory. Both are private to the user and both sides
    /// compute the same choice, so a socket owned by another account is never
    /// even looked at.
    public static func socketURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        userTemporaryDirectory: URL? = FanBarCLIContract.userTemporaryDirectory()
    ) -> URL {
        let preferred = home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(socketDirectoryName, isDirectory: true)
            .appendingPathComponent(socketFileName, isDirectory: false)
        guard FanBarCLISocket.address(for: preferred.path) == nil,
              let temporary = userTemporaryDirectory?.appendingPathComponent(fallbackSocketFileName),
              FanBarCLISocket.address(for: temporary.path) != nil else { return preferred }
        return temporary
    }

    /// `/var/folders/…/T/`: owned by the user, mode 0700, and the same for every
    /// process of that user (unlike `NSTemporaryDirectory()` in a sandbox).
    public static func userTemporaryDirectory() -> URL? {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: bytes, encoding: .utf8), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct FanBarCLIRequest: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case status
        case listPresets
        case setPreset
        case automatic
        case curve
        case fixed
    }

    public var version: Int
    public var action: Action
    /// Preset name, built-in key (`silent`, `balanced`, …) or token (`builtin:2`).
    public var preset: String?
    public var rpm: Int?
    /// Keep the new mode until changed, instead of the Settings restore timer.
    public var hold: Bool

    public init(action: Action, preset: String? = nil, rpm: Int? = nil, hold: Bool = false) {
        version = FanBarCLIContract.version
        self.action = action
        self.preset = preset
        self.rpm = rpm
        self.hold = hold
    }
}

public struct FanBarCLIResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String
    public var status: FanBarCLIStatus?
    public var presets: [FanBarCLIPreset]?
    /// Bundle path of the app that answered, so a `fanbar` can tell when a
    /// different FanBar copy than the one it ships in is serving the socket.
    /// Optional: replies from builds before it simply lack the key.
    public var appPath: String?

    public init(
        ok: Bool,
        message: String,
        status: FanBarCLIStatus? = nil,
        presets: [FanBarCLIPreset]? = nil,
        appPath: String? = nil
    ) {
        self.ok = ok
        self.message = message
        self.status = status
        self.presets = presets
        self.appPath = appPath
    }
}

public struct FanBarCLIStatus: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case automatic
        case curve
        case fixed
    }

    public struct Fan: Codable, Equatable, Sendable {
        public var index: Int
        public var currentRPM: Int
        public var minimumRPM: Int
        public var maximumRPM: Int

        public init(index: Int, currentRPM: Int, minimumRPM: Int, maximumRPM: Int) {
            self.index = index
            self.currentRPM = currentRPM
            self.minimumRPM = minimumRPM
            self.maximumRPM = maximumRPM
        }
    }

    public var mode: Mode
    /// Token of the preset whose curve is selected (active only in `curve`).
    public var preset: String
    public var presetName: String
    public var fixedRPM: Int?
    public var curveOutputPercent: Double?
    /// When macOS control comes back; nil in `automatic` or when held.
    public var restoresAt: Date?
    public var helperEnabled: Bool
    public var fans: [Fan]
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var ssdCelsius: Double?

    public init(
        mode: Mode,
        preset: String,
        presetName: String,
        fixedRPM: Int?,
        curveOutputPercent: Double?,
        restoresAt: Date?,
        helperEnabled: Bool,
        fans: [Fan],
        cpuCelsius: Double?,
        gpuCelsius: Double?,
        ssdCelsius: Double?
    ) {
        self.mode = mode
        self.preset = preset
        self.presetName = presetName
        self.fixedRPM = fixedRPM
        self.curveOutputPercent = curveOutputPercent
        self.restoresAt = restoresAt
        self.helperEnabled = helperEnabled
        self.fans = fans
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.ssdCelsius = ssdCelsius
    }
}

public struct FanBarCLIPreset: Codable, Equatable, Sendable {
    public var id: String
    /// Stable English key for built-ins (`performance`), the user's name otherwise.
    public var key: String
    public var name: String
    public var builtIn: Bool
    public var selected: Bool

    public init(id: String, key: String, name: String, builtIn: Bool, selected: Bool) {
        self.id = id
        self.key = key
        self.name = name
        self.builtIn = builtIn
        self.selected = selected
    }
}

/// Socket I/O shared by both ends: one newline-terminated JSON message each way.
public enum FanBarCLISocket {
    /// Reads until a newline, EOF, or the size limit. Returns nil on error or overflow.
    public static func readMessage(from descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return count == 0 && !data.isEmpty ? data : nil }
            let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n"))
            data.append(contentsOf: buffer[0..<(newline ?? count)])
            guard data.count <= FanBarCLIContract.maximumMessageBytes else { return nil }
            if newline != nil { return data }
        }
    }

    public static func writeMessage(_ data: Data, to descriptor: Int32) -> Bool {
        var payload = data
        payload.append(UInt8(ascii: "\n"))
        return payload.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return false }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(descriptor, pointer, remaining)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                pointer += written
                remaining -= written
            }
            return true
        }
    }

    /// Fills a `sockaddr_un` for `path`; nil when the path does not fit.
    public static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
