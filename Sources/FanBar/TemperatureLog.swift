import Foundation

/// Preferences for the CSV temperature and fan log. Defaults follow
/// docs/design/temperature-logging.md.
enum TemperatureLogPreferences {
    static let enabledKey = "fanbar.temperatureLog.enabled"
    static let intervalKey = "fanbar.temperatureLog.intervalSeconds"
    static let directoryKey = "fanbar.temperatureLog.directoryPath"
    static let newLogPolicyKey = "fanbar.temperatureLog.newLogPolicy"
    static let logTemperaturesKey = "fanbar.temperatureLog.temperatures"
    static let logFanSpeedsKey = "fanbar.temperatureLog.fanSpeeds"
    /// Days to keep FanBar's log files; 0 keeps them forever. Kept out of
    /// `TemperatureLogSettings` so changing it never starts a new file.
    static let retentionDaysKey = "fanbar.temperatureLog.retentionDays"

    static let intervalOptions = [2, 5, 10, 30, 60]
    static let defaultIntervalSeconds = 10
    static let retentionOptions = [7, 30, 90, 0]
    static let defaultRetentionDays = 30

    static func retentionDays(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: retentionDaysKey) as? Int
        return retentionOptions.contains(stored ?? -1) ? stored ?? defaultRetentionDays : defaultRetentionDays
    }

    enum NewLogPolicy: String, CaseIterable, Identifiable {
        case never
        case onStartup
        case daily

        var id: String { rawValue }
    }

    /// One file per day pairs with the day-based retention, so whole days expire.
    static let defaultPolicy = NewLogPolicy.daily

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FanBar/Logs", isDirectory: true)
    }
}

/// A snapshot of the log preferences. Equal snapshots mean the open file can be reused.
struct TemperatureLogSettings: Equatable, Sendable {
    var enabled: Bool
    var intervalSeconds: Int
    var directory: URL
    var newLogPolicy: TemperatureLogPreferences.NewLogPolicy
    var logTemperatures: Bool
    var logFanSpeeds: Bool

    static func current(defaults: UserDefaults = .standard) -> Self {
        let storedInterval = defaults.object(forKey: TemperatureLogPreferences.intervalKey) as? Int
        let interval = TemperatureLogPreferences.intervalOptions.contains(storedInterval ?? -1)
            ? storedInterval ?? TemperatureLogPreferences.defaultIntervalSeconds
            : TemperatureLogPreferences.defaultIntervalSeconds
        // An empty stored path means "never chosen", so the default folder applies.
        let directory = defaults.string(forKey: TemperatureLogPreferences.directoryKey)
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) } ?? TemperatureLogPreferences.defaultDirectory
        let policy = defaults.string(forKey: TemperatureLogPreferences.newLogPolicyKey)
            .flatMap(TemperatureLogPreferences.NewLogPolicy.init(rawValue:)) ?? TemperatureLogPreferences.defaultPolicy
        return Self(
            enabled: defaults.bool(forKey: TemperatureLogPreferences.enabledKey),
            intervalSeconds: interval,
            directory: directory,
            newLogPolicy: policy,
            logTemperatures: defaults.object(forKey: TemperatureLogPreferences.logTemperaturesKey) as? Bool ?? true,
            logFanSpeeds: defaults.object(forKey: TemperatureLogPreferences.logFanSpeedsKey) as? Bool ?? true
        )
    }
}

/// One row of the log. Values are already rounded so the CSV stays numeric.
struct TemperatureLogSample: Equatable, Sendable {
    let date: Date
    let cpuCelsius: Int?
    let gpuCelsius: Int?
    let ssdCelsius: Int?
    let batteryCelsius: Int?
    /// Sensors at or above the high-temperature threshold, e.g. "CPU GPU". Empty when none are hot.
    let alert: String
    let mainFanRPM: Int?
    let averageFanRPM: Int?
    /// `automatic`, `curve`, or `fixedRPM`.
    let fanMode: String
    let fanTargetRPM: Int?

    init(
        date: Date,
        cpuCelsius: Double?,
        gpuCelsius: Double?,
        ssdCelsius: Double?,
        batteryCelsius: Double?,
        alert: String,
        mainFanRPM: Int?,
        averageFanRPM: Int?,
        fanMode: String,
        fanTargetRPM: Int?
    ) {
        self.date = date
        self.cpuCelsius = Self.rounded(cpuCelsius)
        self.gpuCelsius = Self.rounded(gpuCelsius)
        self.ssdCelsius = Self.rounded(ssdCelsius)
        self.batteryCelsius = Self.rounded(batteryCelsius)
        self.alert = alert
        self.mainFanRPM = mainFanRPM
        self.averageFanRPM = averageFanRPM
        self.fanMode = fanMode
        self.fanTargetRPM = fanTargetRPM
    }

    private static func rounded(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(value.rounded())
    }
}

enum TemperatureLogFormat {
    static let temperatureColumns = ["CPU Average (C)", "GPU Average (C)", "SSD (C)", "Battery (C)", "Alert"]
    static let fanColumns = ["Main Fan (RPM)", "Fan Average (RPM)", "Fan Mode", "Fan Target (RPM)"]

    static func columns(for settings: TemperatureLogSettings) -> [String] {
        ["Date", "Time"]
            + (settings.logTemperatures ? temperatureColumns : [])
            + (settings.logFanSpeeds ? fanColumns : [])
    }

    static func header(for settings: TemperatureLogSettings) -> String {
        columns(for: settings).map(escape).joined(separator: ",")
    }

    static func row(for sample: TemperatureLogSample, settings: TemperatureLogSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm:ss"

        var fields = [dateFormatter.string(from: sample.date), timeFormatter.string(from: sample.date)]
        if settings.logTemperatures {
            fields += [cell(sample.cpuCelsius), cell(sample.gpuCelsius), cell(sample.ssdCelsius),
                       cell(sample.batteryCelsius), escape(sample.alert)]
        }
        if settings.logFanSpeeds {
            fields += [cell(sample.mainFanRPM), cell(sample.averageFanRPM), escape(sample.fanMode),
                       cell(sample.fanTargetRPM)]
        }
        return fields.joined(separator: ",") + "\n"
    }

    /// RFC 4180: quote fields that contain a delimiter, quote, or line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func cell(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }
}

enum TemperatureLogSchedule {
    /// Ticks arrive every 2 seconds; the half-second slack keeps a 10-second interval from skipping a tick.
    static func shouldWrite(now: Date, lastWrittenAt: Date?, intervalSeconds: Int) -> Bool {
        guard let lastWrittenAt else { return true }
        return now.timeIntervalSince(lastWrittenAt) >= Double(intervalSeconds) - 0.5
    }
}

/// Appends rows to the CSV file. `reset` and `append` run only on the recorder's serial queue
/// (or a single test thread), so the file state needs no lock. The lock guards just the status,
/// which the main actor reads every tick; it is never held during file I/O, so a slow disk
/// cannot stall the main thread.
final class TemperatureLogWriter: @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case recording(fileName: String)
        case failed
    }

    private let lock = NSLock()
    private var statusValue: Status = .idle

    private var handle: FileHandle?
    private var openedBaseURL: URL?
    private var openedFileName: String?
    private var openedColumns: [String] = []
    private var sessionStamp: String?

    var status: Status {
        lock.lock()
        defer { lock.unlock() }
        return statusValue
    }

    private func setStatus(_ status: Status) {
        lock.lock()
        statusValue = status
        lock.unlock()
    }

    /// Closes the file and forgets the session, so the next write starts a new file when the policy asks for one.
    func reset() {
        closeFile()
        openedBaseURL = nil
        openedFileName = nil
        openedColumns = []
        sessionStamp = nil
        setStatus(.idle)
    }

    /// Any I/O error closes the file and marks the log failed; the recorder stops until settings change.
    func append(_ sample: TemperatureLogSample, settings: TemperatureLogSettings) {
        do {
            let columns = TemperatureLogFormat.columns(for: settings)
            let baseURL = baseURL(for: sample.date, settings: settings)
            if baseURL != openedBaseURL || columns != openedColumns {
                closeFile()
                openedFileName = try openFile(baseURL: baseURL, settings: settings, date: sample.date).lastPathComponent
                openedBaseURL = baseURL
                openedColumns = columns
            }
            guard let handle, let openedFileName else { throw CocoaError(.fileWriteUnknown) }
            try handle.write(contentsOf: Data(TemperatureLogFormat.row(for: sample, settings: settings).utf8))
            setStatus(.recording(fileName: openedFileName))
        } catch {
            closeFile()
            openedBaseURL = nil
            setStatus(.failed)
        }
    }

    private func baseURL(for date: Date, settings: TemperatureLogSettings) -> URL {
        let name: String
        switch settings.newLogPolicy {
        case .never:
            name = "FanBar Log.csv"
        case .onStartup:
            if sessionStamp == nil { sessionStamp = Self.stamp(date, format: "yyyy-MM-dd HH-mm-ss") }
            name = "FanBar Log \(sessionStamp ?? "").csv"
        case .daily:
            name = "FanBar Log \(Self.stamp(date, format: "yyyy-MM-dd")).csv"
        }
        return settings.directory.appendingPathComponent(name)
    }

    /// Opens `baseURL` for appending and returns the URL actually used.
    private func openFile(baseURL: URL, settings: TemperatureLogSettings, date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: settings.directory, withIntermediateDirectories: true)
        let header = TemperatureLogFormat.header(for: settings)
        var url = baseURL
        let name = baseURL.deletingPathExtension().lastPathComponent
        let stamp = Self.stamp(date, format: "yyyy-MM-dd HH-mm-ss")
        var collision = 0
        while FileManager.default.fileExists(atPath: url.path), Self.firstLine(of: url) != header {
            // Validate every candidate, including same-second fallback files.
            let suffix = collision == 0 ? "" : " (\(collision))"
            url = baseURL.deletingLastPathComponent()
                .appendingPathComponent("\(name) \(stamp)\(suffix).csv")
            collision += 1
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            let bytes = Data(("\u{FEFF}" + header + "\n").utf8)
            guard FileManager.default.createFile(atPath: url.path, contents: bytes) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return url
    }

    private func closeFile() {
        try? handle?.close()
        handle = nil
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func firstLine(of url: URL) -> String? {
        guard let reader = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? reader.close() }
        guard let data = try? reader.read(upToCount: 4096), let text = String(data: data, encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return line.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .newlines)
    }
}

/// Connects the fan refresh loop to the CSV writer. Preference checks stay on the main actor;
/// file I/O runs on a serial queue so a slow disk cannot delay fan control.
@MainActor
final class TemperatureLogRecorder {
    private let writer = TemperatureLogWriter()
    private let queue = DispatchQueue(label: "local.fanbar.temperature-log")
    private var lastSettings: TemperatureLogSettings?
    private var lastWrittenAt: Date?
    private var failureGate = TemperatureLogFailureGate()
    private var lastCleanupDay: Date?
    private let trashExpiredFiles: @Sendable (URL, Date, Int, String?) -> Void

    /// `trashExpiredFiles` is injectable so tests never touch the real Trash.
    init(trashExpiredFiles: @escaping @Sendable (URL, Date, Int, String?) -> Void = { directory, now, days, current in
        TemperatureLogRetention.moveExpiredToTrash(in: directory, now: now, retentionDays: days, keeping: current)
    }) {
        self.trashExpiredFiles = trashExpiredFiles
    }

    var status: TemperatureLogWriter.Status { writer.status }

    /// When a failed log tries again; nil unless the last write failed.
    var retryAt: Date? { failureGate.retryAt }

    /// "Retry" in Settings: the next due sample tries at once.
    func retryNow() {
        failureGate.requestRetry()
    }

    /// Runs the retention cleanup again on the next write, e.g. after the
    /// retention setting changed.
    func requestCleanup() {
        lastCleanupDay = nil
    }

    /// Blocks until queued file writes finish, so tests can read the file back.
    func waitForPendingWrites() {
        queue.sync {}
    }

    private func cleanUpOncePerDay(now: Date, directory: URL) {
        let day = Calendar.current.startOfDay(for: now)
        guard day != lastCleanupDay else { return }
        lastCleanupDay = day
        let retentionDays = TemperatureLogPreferences.retentionDays()
        queue.async { [writer, trashExpiredFiles] in
            var current: String?
            if case .recording(let fileName) = writer.status { current = fileName }
            trashExpiredFiles(directory, now, retentionDays, current)
        }
    }

    func record(thermal: ThermalReading, fans: [FanReading], mode: FanController.Mode) {
        let settings = TemperatureLogSettings.current()
        if settings != lastSettings {
            // Any preference change starts a fresh session so the header always matches the file.
            lastSettings = settings
            lastWrittenAt = nil
            failureGate.reset()
            lastCleanupDay = nil
            queue.async { [writer] in writer.reset() }
        }
        // A tick that read nothing would only add an empty row and use up the interval.
        let hasReading = !fans.isEmpty
            || [thermal.cpuCelsius, thermal.gpuCelsius, thermal.ssdCelsius, thermal.batteryCelsius].contains { $0 != nil }
        guard settings.enabled,
              hasReading,
              TemperatureLogSchedule.shouldWrite(
                  now: thermal.sampledAt, lastWrittenAt: lastWrittenAt, intervalSeconds: settings.intervalSeconds
              ),
              failureGate.allowsWrite(writerFailed: writer.status == .failed, now: thermal.sampledAt)
        else { return }
        lastWrittenAt = thermal.sampledAt
        cleanUpOncePerDay(now: thermal.sampledAt, directory: settings.directory)

        let threshold = ThermalAlertSettings.thresholdCelsius
        let hotSensors = ThermalSensor.allCases
            .filter { ($0.temperature(in: thermal) ?? -.infinity) >= threshold }
            .map(\.title)
            .joined(separator: " ")
        let rpms = fans.map(\.currentRPM)
        let fanMode: String
        let fanTarget: Int?
        switch mode {
        case .automatic:
            fanMode = "automatic"
            fanTarget = nil
        case .temperatureCurve:
            fanMode = "curve"
            fanTarget = nil
        case .fixed(let rpm):
            fanMode = "fixedRPM"
            fanTarget = rpm
        }
        let sample = TemperatureLogSample(
            date: thermal.sampledAt,
            cpuCelsius: thermal.cpuCelsius,
            gpuCelsius: thermal.gpuCelsius,
            ssdCelsius: thermal.ssdCelsius,
            batteryCelsius: thermal.batteryCelsius,
            alert: hotSensors,
            mainFanRPM: rpms.first,
            averageFanRPM: rpms.isEmpty ? nil : rpms.reduce(0, +) / rpms.count,
            fanMode: fanMode,
            fanTargetRPM: fanTarget
        )
        queue.async { [writer] in writer.append(sample, settings: settings) }
    }
}
