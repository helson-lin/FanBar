import XCTest
@testable import FanBar

@MainActor
final class UsageStatisticsTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? .distantPast
    }

    func testUTCISOWeekMatchesServerAtBoundaries() {
        let cases = [
            ("2026-11-22T23:59:59Z", "2026-W47"),
            ("2026-11-23T00:00:00Z", "2026-W48"),
            ("2026-12-31T12:00:00Z", "2026-W53"),
            ("2027-01-03T23:59:59Z", "2026-W53"),
            ("2027-01-04T00:00:00Z", "2027-W01")
        ]
        for (iso, week) in cases {
            XCTAssertEqual(UsageStatistics.isoWeek(for: date(iso)), week, iso)
        }
    }

    // MARK: Fixtures

    private var defaults = UserDefaults.standard
    private var now = Date()
    private var facts = UsageDeviceFacts(model: "Mac14,2", osMajor: 27, arch: "arm64")

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "UsageStatisticsTests.\(UUID().uuidString)") ?? .standard
        now = date("2026-11-18T10:00:00Z")
    }

    private func makeStatistics() -> UsageStatistics {
        UsageStatistics(defaults: defaults, now: { [weak self] in self?.now ?? Date() },
                        deviceFacts: { [weak self] in self?.facts ?? UsageDeviceFacts(model: "", osMajor: 0, arch: "") })
    }

    private func parameters(_ statistics: UsageStatistics) -> [String: String] {
        Dictionary(uniqueKeysWithValues: statistics.feedParameters().compactMap { pair in
            pair["key"].flatMap { key in pair["value"].map { (key, $0) } }
        })
    }

    // MARK: Preference and cohort

    func testSharingIsOffByDefault() {
        XCTAssertFalse(makeStatistics().isEnabled)
    }

    func testNewInstallRecordsCurrentUTCWeekAsCohort() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        XCTAssertEqual(statistics.cohort, "2026-W47")
    }

    func testUpgradingUserWhoFinishedOnboardingIsLegacy() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: true)
        XCTAssertEqual(statistics.cohort, "legacy")
    }

    func testCohortIsNeverOverwritten() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        now = date("2026-12-01T10:00:00Z")
        statistics.recordCohortIfNeeded(onboardingCompleted: true)
        XCTAssertEqual(statistics.cohort, "2026-W47")
    }

    // MARK: Feed parameters

    func testNoParametersWhileOptedOut() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        XCTAssertEqual(statistics.feedParameters().count, 0)
    }

    func testOptedInSendsExactlyTheFourFields() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        statistics.isEnabled = true
        XCTAssertEqual(parameters(statistics), [
            "fb_cohort": "2026-W47", "fb_model": "Mac14,2", "fb_os": "27", "fb_arch": "arm64"
        ])
    }

    func testOptedInWithoutCohortSendsNothing() {
        let statistics = makeStatistics()
        statistics.isEnabled = true
        XCTAssertEqual(statistics.feedParameters().count, 0)
    }

    // MARK: Weekly marker

    func testMarkerIsWrittenOnlyAfterAppcastLoads() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        statistics.isEnabled = true
        XCTAssertEqual(parameters(statistics).count, 4)
        // Not loaded yet: a second check in the same week still reports.
        XCTAssertEqual(parameters(statistics).count, 4)
        statistics.appcastDidLoad()
        XCTAssertEqual(statistics.feedParameters().count, 0)
    }

    func testFailedCheckRetriesInTheSameWeek() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        statistics.isEnabled = true
        _ = statistics.feedParameters()
        statistics.checkDidFail()
        statistics.appcastDidLoad()
        XCTAssertEqual(parameters(statistics).count, 4)
    }

    func testReportsAgainInTheNextUTCWeek() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        statistics.isEnabled = true
        _ = statistics.feedParameters()
        statistics.appcastDidLoad()
        now = date("2026-11-22T23:59:59Z")
        XCTAssertEqual(statistics.feedParameters().count, 0)
        now = date("2026-11-23T00:00:00Z")
        XCTAssertEqual(parameters(statistics)["fb_cohort"], "2026-W47")
        statistics.appcastDidLoad()
        XCTAssertEqual(statistics.lastReportedWeek, "2026-W48")
    }

    func testTurningSharingOffClearsPendingWeek() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        statistics.isEnabled = true
        _ = statistics.feedParameters()
        statistics.isEnabled = false
        statistics.appcastDidLoad()
        XCTAssertNil(statistics.lastReportedWeek)
    }

    func testMarkerSurvivesRelaunch() {
        let first = makeStatistics()
        first.recordCohortIfNeeded(onboardingCompleted: false)
        first.isEnabled = true
        _ = first.feedParameters()
        first.appcastDidLoad()
        XCTAssertEqual(makeStatistics().feedParameters().count, 0)
    }

    func testPendingReportOnlyWhileOptedInAndUnreported() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        XCTAssertFalse(statistics.hasPendingReport)
        statistics.isEnabled = true
        XCTAssertTrue(statistics.hasPendingReport)
        _ = statistics.feedParameters()
        statistics.appcastDidLoad()
        XCTAssertFalse(statistics.hasPendingReport)
        now = date("2026-11-23T00:00:00Z")
        XCTAssertTrue(statistics.hasPendingReport)
    }

    // MARK: Device facts

    func testRosettaStillReportsArm64() {
        XCTAssertEqual(UsageDeviceFacts.architecture(armCapability: 1), "arm64")
        XCTAssertEqual(UsageDeviceFacts.architecture(armCapability: 0), "x86_64")
        XCTAssertEqual(UsageDeviceFacts.architecture(armCapability: nil), "x86_64")
    }

    func testCurrentDeviceFactsLookLikeAMac() {
        let current = UsageDeviceFacts.current()
        XCTAssertTrue(current.model.contains(","), current.model)
        XCTAssertGreaterThanOrEqual(current.osMajor, 11)
        XCTAssertTrue(["arm64", "x86_64"].contains(current.arch))
    }

    // MARK: Upgrade question

    func testLegacyUserIsAskedOnceAndNotAfterAnswering() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: true)
        XCTAssertTrue(statistics.shouldAskLegacyUser)
        statistics.markAsked()
        XCTAssertFalse(statistics.shouldAskLegacyUser)
        XCTAssertFalse(makeStatistics().shouldAskLegacyUser)
    }

    func testNewInstallsAreNeverAskedAfterwards() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: false)
        XCTAssertFalse(statistics.shouldAskLegacyUser)
    }

    func testAlreadyOptedInLegacyUserIsNotAsked() {
        let statistics = makeStatistics()
        statistics.recordCohortIfNeeded(onboardingCompleted: true)
        statistics.isEnabled = true
        XCTAssertFalse(statistics.shouldAskLegacyUser)
    }
}
