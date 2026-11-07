import Foundation
import XCTest
@testable import FanBar

final class TemperatureLogTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var savedDefaults: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemperatureLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        savedDefaults = [:]
        for key in Self.touchedKeys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for key in Self.touchedKeys {
            if let value = savedDefaults[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func settings(
        policy: TemperatureLogPreferences.NewLogPolicy = .never,
        temperatures: Bool = true,
        fanSpeeds: Bool = true
    ) -> TemperatureLogSettings {
        TemperatureLogSettings(
            enabled: true,
            intervalSeconds: 10,
            directory: directory,
            newLogPolicy: policy,
            logTemperatures: temperatures,
            logFanSpeeds: fanSpeeds
        )
    }

    private func sample(at date: Date, cpu: Double? = 61.4, alert: String = "", fanMode: String = "automatic") -> TemperatureLogSample {
        TemperatureLogSample(
            date: date,
            cpuCelsius: cpu,
            gpuCelsius: 55.6,
            ssdCelsius: nil,
            batteryCelsius: nil,
            alert: alert,
            mainFanRPM: 1_257,
            averageFanRPM: 1_250,
            fanMode: fanMode,
            fanTargetRPM: fanMode == "fixedRPM" ? 3_500 : nil
        )
    }

    private func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\n").map(String.init)
    }

    private func csvFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Format

    func testHeaderFollowsEnabledColumnGroups() {
        XCTAssertEqual(
            TemperatureLogFormat.header(for: settings()),
            "Date,Time,CPU Average (C),GPU Average (C),SSD (C),Battery (C),Alert,Main Fan (RPM),Fan Average (RPM),Fan Mode,Fan Target (RPM)"
        )
        XCTAssertEqual(TemperatureLogFormat.header(for: settings(temperatures: false, fanSpeeds: false)), "Date,Time")
        XCTAssertEqual(
            TemperatureLogFormat.header(for: settings(temperatures: false)),
            "Date,Time,Main Fan (RPM),Fan Average (RPM),Fan Mode,Fan Target (RPM)"
        )
    }

    func testRowLeavesMissingValuesEmptyAndRoundsTemperatures() {
        let row = TemperatureLogFormat.row(for: sample(at: Date(), cpu: 61.4), settings: settings())
        let fields = row.dropLast().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(fields.count, 11)
        XCTAssertEqual(fields[2], "61")
        XCTAssertEqual(fields[3], "56")
        XCTAssertEqual(fields[4], "", "SSD was not reported")
        XCTAssertEqual(fields[6], "", "no sensor is above the threshold")
        XCTAssertEqual(fields[9], "automatic")
        XCTAssertEqual(fields[10], "")
    }

    func testFixedModeRowCarriesTarget() {
        let row = TemperatureLogFormat.row(for: sample(at: Date(), fanMode: "fixedRPM"), settings: settings())
        XCTAssertTrue(row.hasSuffix(",fixedRPM,3500\n"), row)
    }

    func testEscapeQuotesOnlyWhenNeeded() {
        XCTAssertEqual(TemperatureLogFormat.escape("CPU GPU"), "CPU GPU")
        XCTAssertEqual(TemperatureLogFormat.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(TemperatureLogFormat.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(TemperatureLogFormat.escape("line\nbreak"), "\"line\nbreak\"")
    }

    func testNonFiniteTemperaturesBecomeMissing() {
        XCTAssertNil(sample(at: Date(), cpu: .nan).cpuCelsius)
        XCTAssertNil(sample(at: Date(), cpu: .infinity).cpuCelsius)
    }

    // MARK: Schedule

    func testScheduleWritesFirstSampleThenWaitsForInterval() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(TemperatureLogSchedule.shouldWrite(now: start, lastWrittenAt: nil, intervalSeconds: 10))
        XCTAssertFalse(TemperatureLogSchedule.shouldWrite(now: start.addingTimeInterval(8), lastWrittenAt: start, intervalSeconds: 10))
        XCTAssertTrue(TemperatureLogSchedule.shouldWrite(now: start.addingTimeInterval(10), lastWrittenAt: start, intervalSeconds: 10))
        XCTAssertTrue(TemperatureLogSchedule.shouldWrite(now: start.addingTimeInterval(9.6), lastWrittenAt: start, intervalSeconds: 10),
                      "a tick that lands just early still counts")
    }

    // MARK: Writer

    func testNeverPolicyAppendsOneHeaderAndAllRows() throws {
        let writer = TemperatureLogWriter()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        writer.append(sample(at: start), settings: settings())
        writer.append(sample(at: start.addingTimeInterval(10)), settings: settings())

        let files = try csvFiles()
        XCTAssertEqual(files.map(\.lastPathComponent), ["FanBar Log.csv"])
        let text = try lines(of: files[0])
        XCTAssertEqual(text.count, 3)
        XCTAssertEqual(text[0], TemperatureLogFormat.header(for: settings()))
        XCTAssertEqual(writer.status, .recording(fileName: "FanBar Log.csv"))
    }

    func testChangingColumnsStartsAFileInsteadOfMixingHeaders() throws {
        let writer = TemperatureLogWriter()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        writer.append(sample(at: start), settings: settings())
        writer.append(sample(at: start.addingTimeInterval(10)), settings: settings(fanSpeeds: false))

        let files = try csvFiles()
        XCTAssertEqual(files.count, 2)
        for file in files {
            let text = try lines(of: file)
            XCTAssertEqual(text.count, 2, "each file keeps its own header and rows")
        }
        XCTAssertEqual(try lines(of: files[0]).count, 2)
    }

    func testDailyPolicyRollsOverToNextDayFile() throws {
        let writer = TemperatureLogWriter()
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 59, second: 50)))
        writer.append(sample(at: day), settings: settings(policy: .daily))
        writer.append(sample(at: day.addingTimeInterval(20)), settings: settings(policy: .daily))

        let names = try csvFiles().map(\.lastPathComponent)
        XCTAssertEqual(names, ["FanBar Log 2026-10-17.csv", "FanBar Log 2026-10-18.csv"])
    }

    func testOnStartupPolicyUsesOneFilePerSession() throws {
        let writer = TemperatureLogWriter()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        writer.append(sample(at: start), settings: settings(policy: .onStartup))
        writer.append(sample(at: start.addingTimeInterval(10)), settings: settings(policy: .onStartup))
        XCTAssertEqual(try csvFiles().count, 1)

        writer.reset()
        writer.append(sample(at: start.addingTimeInterval(3_600)), settings: settings(policy: .onStartup))
        XCTAssertEqual(try csvFiles().count, 2, "a new session after reset starts a new file")
    }

    func testWriteFailureMarksLogFailedWithoutThrowing() throws {
        // A regular file where the directory should be makes every open fail.
        let blocker = directory.appendingPathComponent("not-a-folder")
        try Data().write(to: blocker)
        let blocked = TemperatureLogSettings(
            enabled: true,
            intervalSeconds: 10,
            directory: blocker,
            newLogPolicy: .never,
            logTemperatures: true,
            logFanSpeeds: true
        )
        let writer = TemperatureLogWriter()
        writer.append(sample(at: Date()), settings: blocked)
        XCTAssertEqual(writer.status, .failed)

        writer.reset()
        XCTAssertEqual(writer.status, .idle, "changing settings clears the failure")
    }

    func testHeaderIsWrittenOnceWithByteOrderMarkAcrossRestarts() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        TemperatureLogWriter().append(sample(at: start), settings: settings())
        // A second writer stands in for the app relaunching against the same file.
        TemperatureLogWriter().append(sample(at: start.addingTimeInterval(10)), settings: settings())

        let file = try XCTUnwrap(try csvFiles().first)
        // String(contentsOf:) drops the BOM on read, so check the raw bytes.
        let bytes = try Data(contentsOf: file)
        XCTAssertEqual(Array(bytes.prefix(3)), [0xEF, 0xBB, 0xBF], "the BOM lets Excel detect UTF-8 for localized values")
        let text = try lines(of: file)
        XCTAssertEqual(text.count, 3, "one header and two rows, no repeated header after relaunch")
    }

    func testDailyPolicyWritesOneHeaderPerDayFile() throws {
        let writer = TemperatureLogWriter()
        let day = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9)))
        for offset in stride(from: 0.0, to: 60, by: 10) {
            writer.append(sample(at: day.addingTimeInterval(offset)), settings: settings(policy: .daily))
        }
        let file = try XCTUnwrap(try csvFiles().first)
        XCTAssertEqual(try lines(of: file).count, 7)
    }

    func testWriterRecoversOnceTheFolderIsFixed() throws {
        // A regular file occupies the log folder's path, so the first write fails.
        let logFolder = directory.appendingPathComponent("logs", isDirectory: true)
        try Data().write(to: logFolder)
        let blocked = TemperatureLogSettings(
            enabled: true, intervalSeconds: 10, directory: logFolder,
            newLogPolicy: .never, logTemperatures: true, logFanSpeeds: true
        )
        let writer = TemperatureLogWriter()
        writer.append(sample(at: Date()), settings: blocked)
        XCTAssertEqual(writer.status, .failed)

        try FileManager.default.removeItem(at: logFolder)
        writer.append(sample(at: Date()), settings: blocked)
        XCTAssertEqual(writer.status, .recording(fileName: "FanBar Log.csv"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFolder.appendingPathComponent("FanBar Log.csv").path))
    }

    func testAlertColumnIsEscapedInRow() {
        let row = TemperatureLogFormat.row(for: sample(at: Date(), alert: "CPU GPU"), settings: settings())
        XCTAssertTrue(row.contains(",CPU GPU,"), row)
    }

    func testAverageFanIsNilWhenNoFansReported() {
        let empty = TemperatureLogSample(
            date: Date(), cpuCelsius: 50, gpuCelsius: nil, ssdCelsius: nil, batteryCelsius: nil,
            alert: "", mainFanRPM: nil, averageFanRPM: nil, fanMode: "automatic", fanTargetRPM: nil
        )
        let row = TemperatureLogFormat.row(for: empty, settings: settings())
        XCTAssertTrue(row.hasSuffix(",,,automatic,\n"), row)
    }

    // MARK: Recorder

    @MainActor
    func testRecorderWritesOnlyWhenEnabledAndThrottlesToInterval() throws {
        let recorder = TemperatureLogRecorder()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let fans = [FanReading(index: 0, minimumRPM: 1_200, currentRPM: 1_250, maximumRPM: 6_000, isManual: false)]

        recorder.record(thermal: thermal(at: start), fans: fans, mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertTrue(try csvFiles().isEmpty, "disabled by default")

        enableLogging()
        recorder.record(thermal: thermal(at: start), fans: fans, mode: .automatic)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(2)), fans: fans, mode: .automatic)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(10)), fans: fans, mode: .automatic)
        recorder.waitForPendingWrites()

        let file = try XCTUnwrap(try csvFiles().first)
        XCTAssertEqual(try lines(of: file).count, 3, "header plus the first and the 10-second sample only")
        XCTAssertEqual(recorder.status, .recording(fileName: "FanBar Log.csv"))
    }

    @MainActor
    func testRecorderRecordsFixedTargetAlertAndAverageFan() throws {
        enableLogging()
        UserDefaults.standard.set(70.0, forKey: ThermalAlertSettings.thresholdKey)

        let recorder = TemperatureLogRecorder()
        let fans = [
            FanReading(index: 0, minimumRPM: 1_200, currentRPM: 2_000, maximumRPM: 6_000, isManual: true),
            FanReading(index: 1, minimumRPM: 1_200, currentRPM: 3_000, maximumRPM: 6_000, isManual: true)
        ]
        recorder.record(thermal: thermal(at: Date(), cpu: 75, gpu: 40), fans: fans, mode: .fixed(3_500))
        recorder.waitForPendingWrites()

        let file = try XCTUnwrap(try csvFiles().first)
        let row = try XCTUnwrap(try lines(of: file).last)
        XCTAssertTrue(row.contains(",CPU,"), "only CPU is at or above the 70 °C threshold: \(row)")
        XCTAssertTrue(row.hasSuffix(",2000,2500,fixedRPM,3500"), row)
    }

    @MainActor
    func testChangingLogOptionsStartsANewFile() throws {
        enableLogging()
        let recorder = TemperatureLogRecorder()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        recorder.record(thermal: thermal(at: start), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        UserDefaults.standard.set(false, forKey: TemperatureLogPreferences.logFanSpeedsKey)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(10)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        XCTAssertEqual(try csvFiles().count, 2, "a different column set must not share a file")
    }

    @MainActor
    func testFanlessMacLogsTemperaturesWithEmptyFanColumns() throws {
        enableLogging()
        let recorder = TemperatureLogRecorder()
        recorder.record(thermal: thermal(at: Date(), cpu: 48, gpu: 44), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        let row = try XCTUnwrap(try lines(of: XCTUnwrap(try csvFiles().first)).last)
        XCTAssertTrue(row.hasSuffix(",48,44,,,,,,automatic,"), row)
    }

    @MainActor
    func testTickThatReadNothingIsSkippedAndDoesNotUseTheInterval() throws {
        enableLogging()
        let recorder = TemperatureLogRecorder()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let empty = ThermalReading(sampledAt: start, cpuCelsius: nil, gpuCelsius: nil)
        recorder.record(thermal: empty, fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertTrue(try csvFiles().isEmpty)

        // The next real reading is written at once, not held back by the skipped tick.
        recorder.record(thermal: thermal(at: start.addingTimeInterval(2)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        XCTAssertEqual(try lines(of: XCTUnwrap(try csvFiles().first)).count, 2)
    }

    /// End to end through FanController: a Mac whose fan keys fail to read (fanless models)
    /// still gets temperature rows.
    @MainActor
    func testControllerLogsTemperaturesWhenFanReadFails() throws {
        enableLogging()
        let source = FakeFanReadingSource(cpuCelsius: 57)
        source.error = SMCError.unsupportedKey("FNum", -1)
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled) { source }
        controller.temperatureLog.waitForPendingWrites()

        XCTAssertFalse(controller.isAvailable)
        let row = try XCTUnwrap(try lines(of: XCTUnwrap(try csvFiles().first)).last)
        XCTAssertTrue(row.contains(",57,53,"), row)
        XCTAssertTrue(row.hasSuffix(",,,automatic,"), row)
    }

    @MainActor
    func testControllerLogsFanReadingsOnSuccessfulRefresh() throws {
        enableLogging()
        let source = FakeFanReadingSource()
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled) { source }
        controller.temperatureLog.waitForPendingWrites()

        XCTAssertTrue(controller.isAvailable)
        let row = try XCTUnwrap(try lines(of: XCTUnwrap(try csvFiles().first)).last)
        XCTAssertTrue(row.hasSuffix(",1850,1875,automatic,"), row)
    }

    /// Turns logging on into the test's temporary folder with one fixed file name.
    private func enableLogging() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: TemperatureLogPreferences.enabledKey)
        defaults.set(directory.path, forKey: TemperatureLogPreferences.directoryKey)
        defaults.set(TemperatureLogPreferences.NewLogPolicy.never.rawValue, forKey: TemperatureLogPreferences.newLogPolicyKey)
    }

    /// Recorder and controller tests use the process's standard defaults; these keys are
    /// cleared before each test and restored afterwards.
    private static let touchedKeys = [
        TemperatureLogPreferences.enabledKey,
        TemperatureLogPreferences.intervalKey,
        TemperatureLogPreferences.directoryKey,
        TemperatureLogPreferences.newLogPolicyKey,
        TemperatureLogPreferences.logTemperaturesKey,
        TemperatureLogPreferences.logFanSpeedsKey,
        ThermalAlertSettings.thresholdKey
    ]

    private func thermal(at date: Date, cpu: Double = 61, gpu: Double = 55) -> ThermalReading {
        ThermalReading(sampledAt: date, cpuCelsius: cpu, gpuCelsius: gpu)
    }

    // MARK: Preferences

    func testEmptyStoredDirectoryUsesDefaultFolder() throws {
        let suite = "TemperatureLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("", forKey: TemperatureLogPreferences.directoryKey)
        XCTAssertEqual(TemperatureLogSettings.current(defaults: defaults).directory, TemperatureLogPreferences.defaultDirectory)
    }

    func testStoredDirectoryAndTogglesAreRead() throws {
        let suite = "TemperatureLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(directory.path, forKey: TemperatureLogPreferences.directoryKey)
        defaults.set(false, forKey: TemperatureLogPreferences.logTemperaturesKey)
        defaults.set(30, forKey: TemperatureLogPreferences.intervalKey)
        defaults.set("daily", forKey: TemperatureLogPreferences.newLogPolicyKey)

        let current = TemperatureLogSettings.current(defaults: defaults)
        XCTAssertEqual(current.directory.path, directory.path)
        XCTAssertFalse(current.logTemperatures)
        XCTAssertEqual(current.intervalSeconds, 30)
        XCTAssertEqual(current.newLogPolicy, .daily)
    }

    func testUnknownPolicyFallsBackToDefault() throws {
        let suite = "TemperatureLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("hourly", forKey: TemperatureLogPreferences.newLogPolicyKey)
        XCTAssertEqual(TemperatureLogSettings.current(defaults: defaults).newLogPolicy, TemperatureLogPreferences.defaultPolicy)
    }

    func testPreferencesFallBackToDocumentedDefaults() throws {
        let suite = "TemperatureLogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let current = TemperatureLogSettings.current(defaults: defaults)
        XCTAssertFalse(current.enabled)
        XCTAssertEqual(current.intervalSeconds, 10)
        XCTAssertEqual(current.directory, TemperatureLogPreferences.defaultDirectory)
        XCTAssertEqual(current.newLogPolicy, .daily, "one file per day, so retention expires whole days")
        XCTAssertTrue(current.logTemperatures)
        XCTAssertTrue(current.logFanSpeeds)

        defaults.set(7, forKey: TemperatureLogPreferences.intervalKey)
        XCTAssertEqual(TemperatureLogSettings.current(defaults: defaults).intervalSeconds, 10,
                       "intervals outside the offered options are ignored")
    }
}

extension TemperatureLogTests {
    func testResetReopensSameFileForEveryPolicy() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for policy in TemperatureLogPreferences.NewLogPolicy.allCases {
            var options = settings(policy: policy)
            options.directory = directory.appendingPathComponent(policy.rawValue)
            let writer = TemperatureLogWriter()
            writer.append(sample(at: start), settings: options)
            writer.reset()
            // Even a same-second reset must reopen the handle, including onStartup.
            writer.append(sample(at: start), settings: options)
            let files = try FileManager.default.contentsOfDirectory(at: options.directory, includingPropertiesForKeys: nil)
            let file = try XCTUnwrap(files.first)
            XCTAssertEqual(writer.status, .recording(fileName: file.lastPathComponent), policy.rawValue)
            XCTAssertEqual(try lines(of: file).count, 3, policy.rawValue)
        }
    }

    func testSameSecondColumnChangesDoNotMixSchemas() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = TemperatureLogWriter()
        let options = [settings(), settings(fanSpeeds: false), settings(temperatures: false)]
        for option in options {
            writer.append(sample(at: start), settings: option)
        }
        // Reopening a compatible fallback should append to it, without another header.
        writer.reset()
        writer.append(sample(at: start), settings: options[1])

        let files = try csvFiles()
        XCTAssertEqual(files.count, 3)
        var rowCount = 0
        for file in files {
            let rows = try lines(of: file)
            let header = try XCTUnwrap(rows.first)
            let columnCount = header.split(separator: ",", omittingEmptySubsequences: false).count
            for row in rows.dropFirst() {
                XCTAssertEqual(row.split(separator: ",", omittingEmptySubsequences: false).count, columnCount)
                rowCount += 1
            }
        }
        XCTAssertEqual(rowCount, 4)
    }

    @MainActor
    func testRecorderKeepsWritingAfterIntervalChangeAndReenabling() throws {
        enableLogging()
        let recorder = TemperatureLogRecorder()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        recorder.record(thermal: thermal(at: start), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        UserDefaults.standard.set(2, forKey: TemperatureLogPreferences.intervalKey)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(2)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        UserDefaults.standard.set(false, forKey: TemperatureLogPreferences.enabledKey)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(4)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()
        UserDefaults.standard.set(true, forKey: TemperatureLogPreferences.enabledKey)
        recorder.record(thermal: thermal(at: start.addingTimeInterval(6)), fans: [], mode: .automatic)
        recorder.waitForPendingWrites()

        let file = try XCTUnwrap(try csvFiles().first)
        XCTAssertEqual(try lines(of: file).count, 4)
        XCTAssertEqual(recorder.status, .recording(fileName: file.lastPathComponent))
    }
}
