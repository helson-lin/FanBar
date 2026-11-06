import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// The support request waits two weeks, steps aside for any other notice,
/// and stays away once dismissed. Set FANBAR_SUPPORT_RENDER_DIR to also
/// write light and dark PNGs of the row for review.
@MainActor
final class SupportPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let keys = [SupportPrompt.firstUseKey, SupportPrompt.dismissedKey, FanBarLanguage.preferenceKey]
    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        FanMenu.visibleScreenHeight = { 4_000 }
    }

    override func tearDown() async throws {
        for key in keys {
            UserDefaults.standard.set(saved[key], forKey: key)
        }
        FanMenu.visibleScreenHeight = { NSScreen.main?.visibleFrame.height ?? 800 }
    }

    private func firstUse(daysAgo days: Double) -> TimeInterval {
        now.timeIntervalSince1970 - days * 24 * 60 * 60
    }

    func testWaitsFourteenDaysFromFirstUse() {
        XCTAssertFalse(SupportPrompt.shouldShow(firstUse: firstUse(daysAgo: 13.9), dismissed: false, now: now,
                                                isShowingOtherNotice: false))
        XCTAssertTrue(SupportPrompt.shouldShow(firstUse: firstUse(daysAgo: 14), dismissed: false, now: now,
                                               isShowingOtherNotice: false))
    }

    func testNeverShowsBeforeFirstUseIsRecorded() {
        XCTAssertFalse(SupportPrompt.shouldShow(firstUse: 0, dismissed: false, now: now, isShowingOtherNotice: false))
    }

    func testStaysAwayOnceDismissed() {
        XCTAssertFalse(SupportPrompt.shouldShow(firstUse: firstUse(daysAgo: 60), dismissed: true, now: now,
                                                isShowingOtherNotice: false))
    }

    func testStepsAsideForOtherNotices() {
        XCTAssertFalse(SupportPrompt.shouldShow(firstUse: firstUse(daysAgo: 60), dismissed: false, now: now,
                                                isShowingOtherNotice: true))
    }

    /// Opening the panel starts the two-week clock, and a panel already
    /// showing the control-service notice does not add the request.
    func testPanelRecordsFirstUseAndHidesPromptBesideServiceNotice() {
        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: SupportPrompt.firstUseKey)
        defaults.set(false, forKey: SupportPrompt.dismissedKey)
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled,
                                       makeReadingSource: { FakeFanReadingSource() },
                                       readUsage: { SystemUsage() }, refreshInterval: nil)
        controller.refresh()
        let host = NSHostingView(rootView: FanMenu(controller: controller))
        host.frame = NSRect(x: 0, y: 0, width: FanMenu.panelWidth, height: 1_000)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(defaults.double(forKey: SupportPrompt.firstUseKey), 0)

        let heightWithoutPrompt = host.fittingSize.height
        defaults.set(Date().timeIntervalSince1970 - SupportPrompt.delay - 60, forKey: SupportPrompt.firstUseKey)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        XCTAssertNotEqual(controller.helperState, .enabled)
        XCTAssertEqual(host.fittingSize.height, heightWithoutPrompt)
    }

    func testRowFitsThePanelInEveryLanguage() throws {
        for language in [FanBarLanguage.chinese, .english, .japanese, .russian, .french] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: SupportPromptRow(onSupport: {}, onDismiss: {})
                    .environment(\.colorScheme, scheme)
                    .frame(width: FanMenu.panelWidth - FanMenu.padding * 2)
                    .fixedSize(horizontal: false, vertical: true))
                host.frame = NSRect(x: 0, y: 0, width: FanMenu.panelWidth - FanMenu.padding * 2, height: 200)
                host.layoutSubtreeIfNeeded()
                let height = host.fittingSize.height
                XCTAssertGreaterThan(height, 40, language.rawValue)
                XCTAssertLessThan(height, 120, language.rawValue)
                try writeReviewImage(host, name: "support-\(language.rawValue)-\(scheme == .dark ? "dark" : "light")")
            }
        }
    }

    private func writeReviewImage(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["FANBAR_SUPPORT_RENDER_DIR"] else { return }
        host.frame.size.height = host.fittingSize.height
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
