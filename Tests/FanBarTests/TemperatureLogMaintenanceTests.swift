import FanBarShared
import Foundation
import XCTest
@testable import FanBar

final class TemperatureLogMaintenanceTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var savedDefaults: [String: Any] = [:]
    private static let touchedKeys = [
        TemperatureLogPreferences.enabledKey,
        TemperatureLogPreferences.intervalKey,
        TemperatureLogPreferences.directoryKey,
        TemperatureLogPreferences.newLogPolicyKey,
        TemperatureLogPreferences.retentionDaysKey,
        FanBarLanguage.preferenceKey
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemperatureLogMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        for key in Self.touchedKeys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defaults.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for key in Self.touchedKeys {
            if let value = savedDefaults[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ name: String, daysAgo: Double, bytes: Int64 = 1_000) -> TemperatureLogFile {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        return TemperatureLogFile(url: directory.appendingPathComponent(name), created: date, modified: date, bytes: bytes)
    }

    // MARK: Presets

    func testEachPresetIsFoundFromItsValues() {
        for preset in TemperatureLogPreset.allCases {
            XCTAssertEqual(
                TemperatureLogPreset.matching(intervalSeconds: preset.intervalSeconds, retentionDays: preset.retentionDays),
                preset
            )
        }
    }

    func testDefaultsMatchTheRecommendedEverydayPreset() {
        XCTAssertEqual(
            TemperatureLogPreset.matching(
                intervalSeconds: TemperatureLogPreferences.defaultIntervalSeconds,
                retentionDays: TemperatureLogPreferences.defaultRetentionDays
            ),
            .everyday
        )
    }

    func testValuesOutsideThePresetsReadAsCustom() {
        XCTAssertNil(TemperatureLogPreset.matching(intervalSeconds: 5, retentionDays: 30))
        let line = TemperatureLogText.presetLine(intervalSeconds: 5, retentionDays: 30, columnCount: 11)
        XCTAssertTrue(line.hasPrefix("Custom · Every 5 s · Keep 30 days · Uses up to about "), line)
    }

    func testPresetLineShowsOnlyTheUpperBound() {
        let line = TemperatureLogText.presetLine(intervalSeconds: 10, retentionDays: 30, columnCount: 11)
        XCTAssertTrue(line.hasPrefix("Uses up to about "), line)
    }

    func testKeepingForeverShowsTheDailyRateInstead() {
        let line = TemperatureLogText.presetLine(intervalSeconds: 10, retentionDays: 0, columnCount: 11)
        XCTAssertTrue(line.contains("a day, never cleaned up"), line)
        XCTAssertNil(TemperatureLogSizeEstimate.totalBytes(intervalSeconds: 10, columnCount: 11, retentionDays: 0))
    }

    func testFactsSayHowLongFilesAreKept() {
        XCTAssertEqual(TemperatureLogText.facts(intervalSeconds: 10, retentionDays: 30), "Every 10 s · Keep 30 days")
        XCTAssertEqual(TemperatureLogText.facts(intervalSeconds: 60, retentionDays: 0), "Every 60 s · Keep forever")
    }

    func testSizeEstimateScalesWithIntervalAndRetention() {
        let fine = TemperatureLogSizeEstimate.bytesPerDay(intervalSeconds: 2, columnCount: 11)
        let coarse = TemperatureLogSizeEstimate.bytesPerDay(intervalSeconds: 10, columnCount: 11)
        XCTAssertEqual(fine, coarse * 5, accuracy: 1)
        XCTAssertEqual(
            TemperatureLogSizeEstimate.totalBytes(intervalSeconds: 10, columnCount: 11, retentionDays: 30) ?? 0,
            coarse * 30, accuracy: 1
        )
        XCTAssertEqual(TemperatureLogSizeEstimate.bytesPerDay(intervalSeconds: 0, columnCount: 11), 0)
    }

    func testRetentionFallsBackToDefaultForUnofferedValues() throws {
        let suite = "TemperatureLogMaintenanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(TemperatureLogPreferences.retentionDays(defaults: defaults), 30)
        defaults.set(0, forKey: TemperatureLogPreferences.retentionDaysKey)
        XCTAssertEqual(TemperatureLogPreferences.retentionDays(defaults: defaults), 0)
        defaults.set(12, forKey: TemperatureLogPreferences.retentionDaysKey)
        XCTAssertEqual(TemperatureLogPreferences.retentionDays(defaults: defaults), 30)
    }

    // MARK: Retention

    func testOnlyFanBarFilesPastTheCutoffExpire() {
        let files = [
            file("FanBar Log 2026-01-01.csv", daysAgo: 40),
            file("FanBar Log 2026-02-01.csv", daysAgo: 10),
            file("FanBar Log 2026-01-02.csv", daysAgo: 31)
        ]
        let expired = TemperatureLogRetention.expired(files, now: now, retentionDays: 30, keeping: nil)
        XCTAssertEqual(expired.map(\.lastPathComponent), ["FanBar Log 2026-01-01.csv", "FanBar Log 2026-01-02.csv"])
    }

    func testFileBeingWrittenNeverExpires() {
        let files = [file("FanBar Log.csv", daysAgo: 400)]
        XCTAssertTrue(TemperatureLogRetention.expired(files, now: now, retentionDays: 7, keeping: "FanBar Log.csv").isEmpty)
    }

    func testKeepingForeverExpiresNothing() {
        let files = [file("FanBar Log 2020-01-01.csv", daysAgo: 2_000)]
        XCTAssertTrue(TemperatureLogRetention.expired(files, now: now, retentionDays: 0, keeping: nil).isEmpty)
    }

    func testListingSkipsFilesFanBarDidNotCreate() throws {
        for name in ["FanBar Log 2026-11-07.csv", "notes.csv", "FanBar Log.txt", "Budget.csv"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("FanBar Log folder.csv"), withIntermediateDirectories: true
        )
        let names = TemperatureLogRetention.files(in: directory).map(\.url.lastPathComponent)
        XCTAssertEqual(names, ["FanBar Log 2026-11-07.csv"])
        XCTAssertTrue(TemperatureLogRetention.files(in: directory.appendingPathComponent("missing")).isEmpty)
    }

    // MARK: Usage

    func testUsageCountsCalendarDaysAndSumsSizes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let files = [file("FanBar Log a.csv", daysAgo: 2, bytes: 3_000), file("FanBar Log b.csv", daysAgo: 0, bytes: 1_200)]
        let usage = try XCTUnwrap(TemperatureLogUsage.summarize(files, now: now, calendar: calendar))
        XCTAssertEqual(usage, TemperatureLogUsage(days: 3, bytes: 4_200))
        XCTAssertNil(TemperatureLogUsage.summarize([], now: now))
    }

    func testRecordedSummaryUsesSingularForOneDay() {
        let one = TemperatureLogText.recordedSummary(TemperatureLogUsage(days: 1, bytes: 0)) ?? ""
        XCTAssertTrue(one.hasPrefix("1 day recorded · "), one)
        let three = TemperatureLogText.recordedSummary(TemperatureLogUsage(days: 3, bytes: 0)) ?? ""
        XCTAssertTrue(three.hasPrefix("3 days recorded · "), three)
        XCTAssertNil(TemperatureLogText.recordedSummary(nil))
    }

    // MARK: Retry

    func testRetryWaitsLongerAfterEachFailure() {
        XCTAssertEqual(TemperatureLogRetry.delay(afterFailures: 1), 60)
        XCTAssertEqual(TemperatureLogRetry.delay(afterFailures: 2), 300)
        XCTAssertEqual(TemperatureLogRetry.delay(afterFailures: 3), 900)
        XCTAssertEqual(TemperatureLogRetry.delay(afterFailures: 9), 900)
    }

    func testFailureDetailCountsWholeMinutesUp() {
        XCTAssertEqual(TemperatureLogText.failureDetail(retryAt: now.addingTimeInterval(61), now: now),
                       "Can’t write. Retrying in 2 min")
        XCTAssertEqual(TemperatureLogText.failureDetail(retryAt: now.addingTimeInterval(5), now: now),
                       "Can’t write. Retrying in 1 min")
        XCTAssertEqual(TemperatureLogText.failureDetail(retryAt: now, now: now), "Can’t write. Retrying shortly")
        XCTAssertEqual(TemperatureLogText.failureDetail(retryAt: nil, now: now), "Can’t write. Retrying shortly")
    }

    func testGateHoldsWritesUntilTheDelayThenBacksOff() {
        var gate = TemperatureLogFailureGate()
        XCTAssertTrue(gate.allowsWrite(writerFailed: false, now: now))

        XCTAssertFalse(gate.allowsWrite(writerFailed: true, now: now), "the failing tick itself does not retry")
        XCTAssertEqual(gate.retryAt, now.addingTimeInterval(60))
        XCTAssertFalse(gate.allowsWrite(writerFailed: true, now: now.addingTimeInterval(59)))
        XCTAssertTrue(gate.allowsWrite(writerFailed: true, now: now.addingTimeInterval(60)))

        // The retry failed too: the next wait is five minutes.
        XCTAssertFalse(gate.allowsWrite(writerFailed: true, now: now.addingTimeInterval(62)))
        XCTAssertEqual(gate.retryAt, now.addingTimeInterval(362))

        XCTAssertTrue(gate.allowsWrite(writerFailed: false, now: now.addingTimeInterval(400)))
        XCTAssertEqual(gate.failures, 0, "a successful write forgets earlier failures")
    }

    func testRetryRequestSkipsTheWait() {
        var gate = TemperatureLogFailureGate()
        XCTAssertFalse(gate.allowsWrite(writerFailed: true, now: now))
        gate.requestRetry()
        XCTAssertTrue(gate.allowsWrite(writerFailed: true, now: now.addingTimeInterval(2)))
        XCTAssertNil(gate.retryAt)
    }

    // MARK: Recorder

    private func thermal(at date: Date) -> ThermalReading {
        ThermalReading(sampledAt: date, cpuCelsius: 60, gpuCelsius: 50)
    }

    @MainActor
    func testRecorderResumesByItselfOnceTheFolderComesBack() throws {
        let logFolder = directory.appendingPathComponent("logs", isDirectory: true)
        try Data().write(to: logFolder) // a file where the folder should be: every open fails
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: TemperatureLogPreferences.enabledKey)
        defaults.set(logFolder.path, forKey: TemperatureLogPreferences.directoryKey)
        defaults.set(TemperatureLogPreferences.NewLogPolicy.never.rawValue, forKey: TemperatureLogPreferences.newLogPolicyKey)
        defaults.set(2, forKey: TemperatureLogPreferences.intervalKey)

        let recorder = TemperatureLogRecorder(trashExpiredFiles: { _, _, _, _ in })
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        recorder.record(thermal: thermal(at: start), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(recorder.status, .failed)

        recorder.record(thermal: thermal(at: start.addingTimeInterval(2)), fans: [], mode: .automatic)
        XCTAssertEqual(recorder.retryAt, start.addingTimeInterval(62))

        try FileManager.default.removeItem(at: logFolder)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(30)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(recorder.status, .failed, "still waiting out the delay")

        recorder.record(thermal: thermal(at: start.addingTimeInterval(62)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(recorder.status, .recording(fileName: "FanBar Log.csv"))
        XCTAssertNil(recorder.retryAt)
    }

    @MainActor
    func testRecorderRetriesAtOnceWhenAsked() throws {
        let logFolder = directory.appendingPathComponent("logs", isDirectory: true)
        try Data().write(to: logFolder)
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: TemperatureLogPreferences.enabledKey)
        defaults.set(logFolder.path, forKey: TemperatureLogPreferences.directoryKey)
        defaults.set(2, forKey: TemperatureLogPreferences.intervalKey)

        let recorder = TemperatureLogRecorder(trashExpiredFiles: { _, _, _, _ in })
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        recorder.record(thermal: thermal(at: start), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        recorder.record(thermal: thermal(at: start.addingTimeInterval(2)), fans: [], mode: .automatic)

        try FileManager.default.removeItem(at: logFolder)
        recorder.retryNow()
        recorder.record(thermal: thermal(at: start.addingTimeInterval(4)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        guard case .recording = recorder.status else {
            return XCTFail("expected recording after Retry, got \(recorder.status)")
        }
    }

    @MainActor
    func testRecorderCleansUpOncePerDayWithTheRetentionSetting() throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: TemperatureLogPreferences.enabledKey)
        defaults.set(directory.path, forKey: TemperatureLogPreferences.directoryKey)
        defaults.set(TemperatureLogPreferences.NewLogPolicy.never.rawValue, forKey: TemperatureLogPreferences.newLogPolicyKey)
        defaults.set(7, forKey: TemperatureLogPreferences.retentionDaysKey)

        struct Call {
            let folder: URL
            let days: Int
            let current: String?
        }
        final class Calls: @unchecked Sendable {
            var values: [Call] = []
        }
        let calls = Calls()
        let recorder = TemperatureLogRecorder(trashExpiredFiles: { folder, _, days, current in
            calls.values.append(Call(folder: folder, days: days, current: current))
        })
        let start = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9)))
        recorder.record(thermal: thermal(at: start), fans: [], mode: .automatic)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(60)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(calls.values.count, 1, "once per day, not per write")
        XCTAssertEqual(calls.values.first?.folder.path, directory.path)
        XCTAssertEqual(calls.values.first?.days, 7)

        recorder.record(thermal: thermal(at: start.addingTimeInterval(86_400)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(calls.values.count, 2)
        XCTAssertEqual(calls.values.last?.current, "FanBar Log.csv", "the open file is passed so it is never trashed")

        recorder.requestCleanup()
        recorder.record(thermal: thermal(at: start.addingTimeInterval(86_500)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(calls.values.count, 3, "a retention change runs the cleanup again")
    }
}
