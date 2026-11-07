import FanBarShared
import Foundation

/// The three purpose presets on the History tab. Each is an interval plus how
/// long files are kept, so users choose by purpose instead of by parameter.
enum TemperatureLogPreset: String, CaseIterable, Identifiable {
    case everyday
    case troubleshooting
    case longTerm

    var id: String { rawValue }

    var intervalSeconds: Int {
        switch self {
        case .everyday: 10
        case .troubleshooting: 2
        case .longTerm: 60
        }
    }

    var retentionDays: Int {
        switch self {
        case .everyday: 30
        case .troubleshooting: 7
        case .longTerm: 90
        }
    }

    var title: String {
        switch self {
        case .everyday: fanBarText("日常", "Everyday")
        case .troubleshooting: fanBarText("排查问题", "Troubleshooting")
        case .longTerm: fanBarText("长期观察", "Long term")
        }
    }

    var useCase: String {
        switch self {
        case .everyday: fanBarText("平时开着，随时回看", "Leave it on and look back anytime")
        case .troubleshooting: fanBarText("风扇很响或机器发烫时", "When fans get loud or your Mac runs hot")
        case .longTerm: fanBarText("比较几个月的变化", "Compare changes over months")
        }
    }

    var symbolName: String {
        switch self {
        case .everyday: "calendar"
        case .troubleshooting: "magnifyingglass"
        case .longTerm: "clock"
        }
    }

    /// nil when the advanced settings no longer match any preset ("Custom").
    static func matching(intervalSeconds: Int, retentionDays: Int) -> Self? {
        allCases.first { $0.intervalSeconds == intervalSeconds && $0.retentionDays == retentionDays }
    }
}

/// One FanBar CSV file in the log folder.
struct TemperatureLogFile: Equatable {
    let url: URL
    let created: Date
    let modified: Date
    let bytes: Int64
}

/// Lists FanBar's own log files and picks the ones past the retention period.
/// Only files FanBar names ("FanBar Log….csv") are ever touched.
enum TemperatureLogRetention {
    static func isFanBarLog(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "csv" && url.lastPathComponent.hasPrefix("FanBar Log")
    }

    static func files(in directory: URL, fileManager: FileManager = .default) -> [TemperatureLogFile] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        return urls.filter(isFanBarLog).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            return TemperatureLogFile(
                url: url,
                created: values.creationDate ?? modified,
                modified: modified,
                bytes: Int64(values.fileSize ?? 0)
            )
        }
    }

    /// Files last written before the cutoff. `retentionDays` 0 keeps everything,
    /// and the file being written now is never returned.
    static func expired(
        _ files: [TemperatureLogFile],
        now: Date,
        retentionDays: Int,
        keeping currentFileName: String?
    ) -> [URL] {
        guard retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return files
            .filter { $0.modified < cutoff && $0.url.lastPathComponent != currentFileName }
            .map(\.url)
    }

    /// Moves expired files to the Trash so a mistaken setting can be undone.
    @discardableResult
    static func moveExpiredToTrash(
        in directory: URL,
        now: Date,
        retentionDays: Int,
        keeping currentFileName: String?,
        fileManager: FileManager = .default
    ) -> Int {
        let targets = expired(files(in: directory, fileManager: fileManager),
                              now: now, retentionDays: retentionDays, keeping: currentFileName)
        return targets.reduce(0) { count, url in
            (try? fileManager.trashItem(at: url, resultingItemURL: nil)) == nil ? count : count + 1
        }
    }
}

/// "3 days recorded · 4.2 MB" for the status line.
struct TemperatureLogUsage: Equatable {
    let days: Int
    let bytes: Int64

    /// Counts calendar days from the oldest kept file through today, so a log
    /// started this morning reads "1 day".
    static func summarize(_ files: [TemperatureLogFile], now: Date, calendar: Calendar = .current) -> Self? {
        guard let earliest = files.map(\.created).min() else { return nil }
        let start = calendar.startOfDay(for: min(earliest, now))
        let elapsed = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        return Self(days: elapsed + 1, bytes: files.reduce(0) { $0 + $1.bytes })
    }
}

/// Waits after a failed write before trying again, longer each time.
enum TemperatureLogRetry {
    static let delays: [TimeInterval] = [60, 300, 900]

    static func delay(afterFailures count: Int) -> TimeInterval {
        delays[min(max(count, 1), delays.count) - 1]
    }

    /// Whole minutes left, never below 1, for "Retrying in N min".
    static func minutesLeft(until retryAt: Date, now: Date) -> Int {
        max(1, Int((retryAt.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

/// Holds writes back after a failure until the retry delay has passed, so a
/// folder that comes back (an external disk, restored permissions) resumes
/// logging without the user changing a setting.
struct TemperatureLogFailureGate: Equatable {
    private(set) var failures = 0
    private(set) var failedSince: Date?
    private var retryRequested = false

    /// When the next attempt is due; nil while not failed.
    var retryAt: Date? {
        failedSince.map { $0.addingTimeInterval(TemperatureLogRetry.delay(afterFailures: failures)) }
    }

    mutating func reset() {
        self = Self()
    }

    /// "Retry" in Settings: the next due sample tries at once.
    mutating func requestRetry() {
        retryRequested = true
    }

    /// Call only for a sample that is otherwise due, so a retry is never
    /// spent on a tick that would not have written anyway.
    mutating func allowsWrite(writerFailed: Bool, now: Date) -> Bool {
        guard writerFailed else {
            failures = 0
            return true
        }
        if failedSince == nil {
            failures += 1
            failedSince = now
        }
        guard retryRequested || now >= (retryAt ?? now) else { return false }
        retryRequested = false
        failedSince = nil
        return true
    }
}

/// Copy for the History tab, kept out of the views so each state is testable.
enum TemperatureLogText {
    static func size(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes.rounded()), countStyle: .file)
    }

    static func recordedSummary(_ usage: TemperatureLogUsage?) -> String? {
        guard let usage else { return nil }
        let days = usage.days == 1
            ? fanBarText("已记录 1 天", "1 day recorded")
            : fanBarFormat("已记录 %d 天", "%d days recorded", usage.days)
        return "\(days) · \(size(Double(usage.bytes)))"
    }

    static func failureDetail(retryAt: Date?, now: Date) -> String {
        guard let retryAt, retryAt > now else {
            return fanBarText("无法写入，即将重试", "Can’t write. Retrying shortly")
        }
        return fanBarFormat(
            "无法写入，%d 分钟后重试",
            "Can’t write. Retrying in %d min",
            TemperatureLogRetry.minutesLeft(until: retryAt, now: now)
        )
    }

    static func interval(_ seconds: Int) -> String {
        fanBarFormat("每 %d 秒", "Every %d s", seconds)
    }

    static func retention(_ days: Int) -> String {
        days == 0
            ? fanBarText("永久保留", "Keep forever")
            : fanBarFormat("保留 %d 天", "Keep %d days", days)
    }

    static func facts(intervalSeconds: Int, retentionDays: Int) -> String {
        "\(interval(intervalSeconds)) · \(retention(retentionDays))"
    }

    /// The upper bound users worry about, or the daily rate when nothing is cleaned up.
    static func usage(intervalSeconds: Int, retentionDays: Int, columnCount: Int) -> String {
        if let total = TemperatureLogSizeEstimate.totalBytes(
            intervalSeconds: intervalSeconds, columnCount: columnCount, retentionDays: retentionDays
        ) {
            return fanBarFormat("最多占用约 %@", "Uses up to about %@", size(total))
        }
        let perDay = TemperatureLogSizeEstimate.bytesPerDay(intervalSeconds: intervalSeconds, columnCount: columnCount)
        return fanBarFormat("每天约 %@，不会自动清理", "About %@ a day, never cleaned up", size(perDay))
    }

    /// Below the preset cards: the usage, prefixed with the values when no preset matches.
    static func presetLine(intervalSeconds: Int, retentionDays: Int, columnCount: Int) -> String {
        let usage = usage(intervalSeconds: intervalSeconds, retentionDays: retentionDays, columnCount: columnCount)
        guard TemperatureLogPreset.matching(intervalSeconds: intervalSeconds, retentionDays: retentionDays) == nil else {
            return usage
        }
        let facts = facts(intervalSeconds: intervalSeconds, retentionDays: retentionDays)
        return "\(fanBarText("自定义", "Custom")) · \(facts) · \(usage)"
    }

    static func policy(_ policy: TemperatureLogPreferences.NewLogPolicy) -> String {
        switch policy {
        case .daily: fanBarText("每天", "Daily")
        case .onStartup: fanBarText("每次启动 FanBar", "Each time FanBar starts")
        case .never: fanBarText("从不", "Never")
        }
    }
}

/// Rough disk use for the preset line. A row is the date and time plus about
/// five bytes per value column; the estimate only has to be honest to the MB.
enum TemperatureLogSizeEstimate {
    static func bytesPerDay(intervalSeconds: Int, columnCount: Int) -> Double {
        guard intervalSeconds > 0 else { return 0 }
        return 86_400 / Double(intervalSeconds) * Double(20 + max(0, columnCount - 2) * 5)
    }

    /// nil when files are kept forever, so there is no upper bound to show.
    static func totalBytes(intervalSeconds: Int, columnCount: Int, retentionDays: Int) -> Double? {
        guard retentionDays > 0 else { return nil }
        return bytesPerDay(intervalSeconds: intervalSeconds, columnCount: columnCount) * Double(retentionDays)
    }
}
