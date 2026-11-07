import FanBarShared
import XCTest
@testable import FanBar

@MainActor
final class GeneralStatusSummaryTests: XCTestCase {
    private var savedLanguage: Any?

    override func setUp() async throws {
        savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
    }

    func testEnabledServiceWithFansStatesTheCountAndTheSafetyNet() {
        let summary = GeneralStatusSummary.make(helperState: .enabled, fanCount: 2)
        XCTAssertEqual(summary.level, .normal)
        XCTAssertEqual(summary.title, "Control service enabled")
        XCTAssertEqual(summary.detail, "2 fans · Fans return to macOS on disconnect, sleep, or a failed write.")
        XCTAssertNil(summary.actionTitle)
    }

    func testSingleFanUsesTheSingularForm() {
        let summary = GeneralStatusSummary.make(helperState: .enabled, fanCount: 1)
        XCTAssertTrue(summary.detail.hasPrefix("1 fan · "), summary.detail)
    }

    func testFanCountNotYetSampledLeavesTheCountOutInsteadOfShowingZero() {
        let summary = GeneralStatusSummary.make(helperState: .enabled, fanCount: nil)
        XCTAssertEqual(summary.level, .normal)
        XCTAssertEqual(summary.detail, "Fans return to macOS on disconnect, sleep, or a failed write.")
        XCTAssertFalse(summary.detail.contains("0"))
    }

    func testNoFansReportedNeedsAttentionAndSaysSo() {
        let summary = GeneralStatusSummary.make(helperState: .enabled, fanCount: 0)
        XCTAssertEqual(summary.level, .attention)
        XCTAssertEqual(summary.title, "No fan data")
        XCTAssertNotEqual(summary.symbolName, FanController.HelperState.enabled.symbolName)
        XCTAssertNil(summary.actionTitle)
    }

    func testServiceAwaitingApprovalOffersToOpenSystemSettings() {
        let summary = GeneralStatusSummary.make(helperState: .requiresApproval, fanCount: 2)
        XCTAssertEqual(summary.level, .attention)
        XCTAssertEqual(summary.title, FanController.HelperState.requiresApproval.noticeTitle)
        XCTAssertEqual(summary.actionTitle, "Open System Settings")
    }

    func testServiceNotRegisteredOffersToEnableIt() {
        let summary = GeneralStatusSummary.make(helperState: .notRegistered, fanCount: nil)
        XCTAssertEqual(summary.level, .attention)
        XCTAssertEqual(summary.actionTitle, "Enable")
    }

    func testMissingServiceIsUnavailableWithNoAction() {
        let summary = GeneralStatusSummary.make(helperState: .unavailable, fanCount: 2)
        XCTAssertEqual(summary.level, .unavailable)
        XCTAssertNil(summary.actionTitle)
    }

    func testEveryStateHasItsOwnSymbol() {
        let symbols = [
            GeneralStatusSummary.make(helperState: .enabled, fanCount: 2),
            GeneralStatusSummary.make(helperState: .enabled, fanCount: 0),
            GeneralStatusSummary.make(helperState: .requiresApproval, fanCount: 2),
            GeneralStatusSummary.make(helperState: .notRegistered, fanCount: 2),
            GeneralStatusSummary.make(helperState: .unavailable, fanCount: 2),
        ].map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }
}
