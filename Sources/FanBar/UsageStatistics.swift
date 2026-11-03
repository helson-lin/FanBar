import Darwin
import Foundation

/// The only hardware and system facts FanBar ever reports, and only when the
/// user has opted in. Nothing else (no IDs, language or memory) is read.
struct UsageDeviceFacts: Equatable {
    let model: String
    let osMajor: Int
    let arch: String

    static func current() -> UsageDeviceFacts {
        UsageDeviceFacts(
            model: sysctlString("hw.model") ?? "unknown",
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            arch: architecture(armCapability: sysctlInt("hw.optional.arm64"))
        )
    }

    /// `hw.optional.arm64` is 1 on Apple silicon even for a Rosetta process,
    /// so the answer is the chip, not the architecture FanBar was built for.
    static func architecture(armCapability: Int?) -> String {
        armCapability == 1 ? "arm64" : "x86_64"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// Decides what, if anything, one update check reports. Pure of Sparkle: the
/// clock, storage and device facts are injected so the rules are unit-tested.
@MainActor
final class UsageStatistics {
    static let shared = UsageStatistics()

    static let enabledKey = "fanbar.usageStatistics.enabled"
    static let cohortKey = "fanbar.usageStatistics.cohort"
    static let lastReportedWeekKey = "fanbar.usageStatistics.lastReportedWeek"
    static let askedKey = "fanbar.usageStatistics.asked"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let deviceFacts: () -> UsageDeviceFacts
    /// A week handed to Sparkle but not yet confirmed by a loaded appcast.
    private var pendingWeek: String?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        deviceFacts: @escaping () -> UsageDeviceFacts = UsageDeviceFacts.current
    ) {
        self.defaults = defaults
        self.now = now
        self.deviceFacts = deviceFacts
    }

    /// Same rule as the server (`services/update/src/fields.ts`): UTC, ISO-8601.
    static func isoWeek(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { pendingWeek = nil }
        }
    }

    var cohort: String? { defaults.string(forKey: Self.cohortKey) }
    var lastReportedWeek: String? { defaults.string(forKey: Self.lastReportedWeekKey) }

    /// Kept on this Mac. Existing users have no install week to recall, so
    /// they share `legacy`; it is set once and never changed.
    func recordCohortIfNeeded(onboardingCompleted: Bool) {
        guard cohort == nil else { return }
        defaults.set(onboardingCompleted ? "legacy" : Self.isoWeek(for: now()), forKey: Self.cohortKey)
    }

    /// Sparkle's `[[String: String]]` shape: one `key`/`value` pair per field.
    func feedParameters() -> [[String: String]] {
        let week = Self.isoWeek(for: now())
        guard isEnabled, let cohort, week != lastReportedWeek else { return [] }
        pendingWeek = week
        let facts = deviceFacts()
        return [
            ("fb_cohort", cohort),
            ("fb_model", facts.model),
            ("fb_os", String(facts.osMajor)),
            ("fb_arch", facts.arch)
        ].map { ["key": $0.0, "value": $0.1] }
    }

    /// The appcast loaded, so the server saw this week's report.
    func appcastDidLoad() {
        guard let pendingWeek else { return }
        defaults.set(pendingWeek, forKey: Self.lastReportedWeekKey)
        self.pendingWeek = nil
    }

    /// The check failed or was aborted: report again on the next one.
    func checkDidFail() {
        pendingWeek = nil
    }

    // MARK: One-time question for existing users

    var hasBeenAsked: Bool { defaults.bool(forKey: Self.askedKey) }

    var shouldAskLegacyUser: Bool {
        cohort == "legacy" && !hasBeenAsked && !isEnabled
    }

    func markAsked() {
        defaults.set(true, forKey: Self.askedKey)
    }
}
