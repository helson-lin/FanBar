import FanBarShared
import UserNotifications
import XCTest
@testable import FanBar

@MainActor
final class ControlNoticeTests: XCTestCase {
    private var savedLanguage: Any?

    override func setUp() async throws {
        savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
    }

    private func makeController(_ source: FakeFanReadingSource = FakeFanReadingSource()) -> FanController {
        FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled,
                      makeReadingSource: { source }, readUsage: { SystemUsage() }, refreshInterval: nil)
    }

    // MARK: Warning timing

    func testWarningGoesOutOneMinuteBeforeTheDeadline() {
        XCTAssertEqual(HandBackWarning.delay(untilDeadline: 1_800), 1_740)
        XCTAssertEqual(HandBackWarning.delay(untilDeadline: 60), 0)
    }

    func testWarningWithLessThanAMinuteLeftGoesOutAtOnce() {
        // Waking with 45 s left still warns, right away.
        XCTAssertEqual(HandBackWarning.delay(untilDeadline: 45), 0)
        XCTAssertEqual(HandBackWarning.delay(untilDeadline: 10), 0)
    }

    func testNoWarningWhenTheHandBackIsSecondsAway() {
        XCTAssertNil(HandBackWarning.delay(untilDeadline: 9))
        XCTAssertNil(HandBackWarning.delay(untilDeadline: 0))
    }

    // MARK: Notice lifetime

    func testWarningNoticeEndsAtTheDeadline() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        let notice = ControlNotice.handBackSoon(mode: .fixed(2_400), duration: .thirtyMinutes, deadline: deadline)
        XCTAssertFalse(notice.isExpired(at: deadline.addingTimeInterval(-1)))
        XCTAssertTrue(notice.isExpired(at: deadline))
    }

    func testHandBackNoticeLastsAnHour() {
        let at = Date(timeIntervalSince1970: 1_000)
        let notice = ControlNotice.handedBack(
            mode: .preset(.builtIn(.silent)), reason: .timer, duration: .thirtyMinutes, at: at
        )
        XCTAssertFalse(notice.isExpired(at: at.addingTimeInterval(3_599)))
        XCTAssertTrue(notice.isExpired(at: at.addingTimeInterval(3_600)))
    }

    // MARK: Copy

    func testPanelMessagesNameTheModeAndTheReason() {
        let controller = makeController()
        let silent = ResumableMode.preset(.builtIn(.silent))
        let silentTitle = controller.presetTitle(for: .builtIn(.silent))

        XCTAssertEqual(
            ControlNoticeText.panelMessage(
                .handBackSoon(mode: silent, duration: .thirtyMinutes, deadline: Date()),
                controller: controller, countdown: "0:42"
            ),
            "\(silentTitle) hands back to macOS in 0:42"
        )
        XCTAssertEqual(
            ControlNoticeText.panelMessage(
                .handedBack(mode: silent, reason: .timer, duration: .thirtyMinutes, at: Date()),
                controller: controller, countdown: ""
            ),
            "After 30 minutes, \(silentTitle) handed back to macOS"
        )
        XCTAssertEqual(
            ControlNoticeText.panelMessage(
                .handedBack(mode: .fixed(2_400), reason: .missingTemperature(.maxChip), duration: .oneHour, at: Date()),
                controller: controller, countdown: ""
            ),
            "Couldn't read the CPU/GPU temperature; Fixed speed handed back to macOS"
        )
    }

    func testNotificationsCarryTheirCategoryAndThread() {
        let controller = makeController()
        let silent = ResumableMode.preset(.builtIn(.silent))

        let soon = ControlNoticeText.notificationContent(
            for: .handBackSoon(mode: silent, duration: .thirtyMinutes, deadline: Date()), controller: controller
        )
        XCTAssertEqual(soon.categoryIdentifier, HandBackNotification.soonCategory)
        XCTAssertEqual(soon.threadIdentifier, HandBackNotification.threadIdentifier)
        XCTAssertTrue(soon.title.hasSuffix("hands back to macOS in 1 minute"))
        XCTAssertEqual(soon.body, "The timer you set for 30 minutes is almost up.")

        let ended = ControlNoticeText.notificationContent(
            for: .handedBack(mode: silent, reason: .timer, duration: .thirtyMinutes, at: Date()), controller: controller
        )
        XCTAssertEqual(ended.categoryIdentifier, HandBackNotification.endedCategory)

        let lost = ControlNoticeText.notificationContent(
            for: .handedBack(mode: silent, reason: .missingTemperature(.cpu), duration: .thirtyMinutes, at: Date()),
            controller: controller
        )
        XCTAssertEqual(lost.categoryIdentifier, HandBackNotification.missingTemperatureCategory)
        XCTAssertEqual(lost.body, "For safety, macOS now controls the fans.")
    }

    func testSMCLockoutNoticeAsksForARestartAndOffersARetry() throws {
        let controller = makeController()
        let silent = ResumableMode.preset(.builtIn(.silent))
        let silentTitle = controller.presetTitle(for: .builtIn(.silent))
        let notice = ControlNotice.handedBack(mode: silent, reason: .smcRejectingWrites, duration: .never, at: Date())

        XCTAssertEqual(
            ControlNoticeText.panelMessage(notice, controller: controller, countdown: ""),
            "The SMC keeps refusing fan writes, so \(silentTitle) stopped. Restart your Mac to fix it"
        )
        let content = ControlNoticeText.notificationContent(for: notice, controller: controller)
        XCTAssertEqual(content.categoryIdentifier, HandBackNotification.smcRejectingWritesCategory)
        XCTAssertTrue(content.body.contains("only a restart clears it"))

        let category = try XCTUnwrap(HandBackNotification.categories(sessionDuration: .never)
            .first { $0.identifier == HandBackNotification.smcRejectingWritesCategory })
        XCTAssertEqual(category.actions.map(\.identifier), [HandBackNotification.turnOnAgainAction])
    }

    // MARK: SMC write lockout (issue 114)

    private func helperError(_ failure: HelperControlFailure) -> HelperClientError {
        HelperClientError(message: failure.encodedReply())
    }

    func testUnlockTimeoutAndBadCommandIndicateALockedOutSMC() {
        XCTAssertTrue(helperError(HelperControlFailure(code: .unlockTimeout, fanIndex: 0, message: "")).indicatesSMCWriteLockout)
        XCTAssertTrue(helperError(HelperControlFailure(
            code: .smcOperationFailed, smcKey: "F0Md", resultCode: 65_666, message: ""
        )).indicatesSMCWriteLockout)

        XCTAssertFalse(helperError(HelperControlFailure(
            code: .smcOperationFailed, smcKey: "F0Tg", resultCode: 0x1_0084, message: ""
        )).indicatesSMCWriteLockout)
        XCTAssertFalse(helperError(HelperControlFailure(code: .systemSleeping, message: "")).indicatesSMCWriteLockout)
        XCTAssertFalse(HelperClientError(message: "timeout", isTimeout: true).indicatesSMCWriteLockout)
    }

    func testBreakerTripsOnlyOnAnUnbrokenRunOfRefusals() {
        let refused = helperError(HelperControlFailure(code: .unlockTimeout, fanIndex: 0, message: ""))
        let other = HelperClientError(message: "connection", isConnectionFailure: true)
        var breaker = SMCWriteLockoutBreaker()

        for _ in 1..<SMCWriteLockoutBreaker.threshold {
            XCTAssertFalse(breaker.recordFailure(refused))
        }
        XCTAssertFalse(breaker.recordFailure(other), "A different failure breaks the run")
        XCTAssertEqual(breaker.consecutiveRefusals, 0)

        for _ in 1..<SMCWriteLockoutBreaker.threshold {
            XCTAssertFalse(breaker.recordFailure(refused))
        }
        breaker.reset()
        XCTAssertEqual(breaker.consecutiveRefusals, 0, "A successful write resets the run")

        for _ in 1..<SMCWriteLockoutBreaker.threshold {
            XCTAssertFalse(breaker.recordFailure(refused))
        }
        XCTAssertTrue(breaker.recordFailure(refused))
    }

    func testWarningOffersTheSessionLengthAgain() throws {
        let categories = HandBackNotification.categories(sessionDuration: .oneHour)
        let soon = try XCTUnwrap(categories.first { $0.identifier == HandBackNotification.soonCategory })
        XCTAssertEqual(soon.actions.map(\.identifier), [HandBackNotification.keepSameAction, HandBackNotification.keepOnAction])
        XCTAssertEqual(soon.actions.first?.title, "Keep 1 hour more")
    }

    // MARK: Failures

    func testMissingFanModeKeyIsRecognizedFromTheStructuredCode() {
        let missing = HelperControlFailure(code: .modeKeyMissing, message: "No fan mode key")
        XCTAssertTrue(HelperClientError(message: missing.encodedReply()).indicatesMissingFanModeKey)
        // The code decides, whatever the localized message says.
        let other = HelperControlFailure(code: .smcOperationFailed, smcKey: "F0Md", resultCode: -1, message: "F0Md/F0md")
        XCTAssertFalse(HelperClientError(message: other.encodedReply()).indicatesMissingFanModeKey)
    }

    /// Helpers that predate structured failures only send the message.
    func testMissingFanModeKeyIsRecognizedInEveryLanguage() {
        XCTAssertTrue(HelperClientError(
            message: "This Mac's SMC has no fan mode key (F0Md/F0md/FS!), so manual fan control is unavailable"
        ).indicatesMissingFanModeKey)
        XCTAssertTrue(HelperClientError(
            message: "此 Mac 的 SMC 未提供风扇模式键（F0Md/F0md），无法手动控制风扇"
        ).indicatesMissingFanModeKey)
        XCTAssertFalse(HelperClientError(message: "SMC operation F0Md failed (-536870206)").indicatesMissingFanModeKey)
    }

    func testLegacyFeedbackKeepsItsMessageAsTheTitle() {
        let feedback = FanController.ModeActionFeedback(kind: .failure, message: "Unable", offersHelperSettings: true)
        XCTAssertEqual(feedback.title, "Unable")
        XCTAssertNil(feedback.safety)
        XCTAssertEqual(feedback.recovery, .openHelperSettings)
        XCTAssertTrue(feedback.offersHelperSettings)
    }

    func testOutOfRangeSpeedNamesTheRangeAndKeepsTheFans() throws {
        let controller = makeController()
        controller.setCustomFixedRPM(-1)
        let feedback = try XCTUnwrap(controller.modeActionFeedback)
        // The common range of both fake fans: highest minimum to lowest maximum.
        XCTAssertEqual(feedback.title, "Choose 1,300–6,000 RPM")
        XCTAssertEqual(feedback.safety, "Fans keep their current speed")
        // The CLI still prints the complete sentence.
        XCTAssertEqual(feedback.message, "That RPM is outside the fans' supported range")
        XCTAssertNil(feedback.recovery)
    }

    func testSwitchWithoutTheServiceSaysMacOSStillDrives() throws {
        let controller = makeController()
        guard controller.helperState != .enabled else { throw XCTSkip("Requires an unregistered test helper") }
        controller.setFixedRPM(3_000)
        let feedback = try XCTUnwrap(controller.modeActionFeedback)
        XCTAssertEqual(feedback.title, "The control service is off")
        XCTAssertEqual(feedback.safety, "macOS is still controlling the fans")
        XCTAssertFalse(feedback.isRisk)
        switch controller.helperState {
        case .notRegistered: XCTAssertEqual(feedback.recovery, .enableHelper)
        case .requiresApproval: XCTAssertEqual(feedback.recovery, .openHelperSettings)
        case .enabled, .unavailable: XCTAssertNil(feedback.recovery)
        }
        XCTAssertEqual(feedback.message, "Enable and approve the control service first")
    }

    // MARK: Notification responses

    func testClickingAHandBackNotificationOpensThePanel() {
        let controller = makeController()
        var opened = 0
        controller.showPanel = { opened += 1 }
        controller.handleNotificationResponse(
            action: UNNotificationDefaultActionIdentifier, request: HandBackNotification.endedIdentifier
        )
        XCTAssertEqual(opened, 1)
        // Other FanBar notifications keep their own behavior.
        controller.handleNotificationResponse(
            action: UNNotificationDefaultActionIdentifier, request: "\(ThermalAlertSettings.notificationIdentifierPrefix).x"
        )
        XCTAssertEqual(opened, 1)
    }

    func testStaleButtonsDoNothingOnceTheUserHasMovedOn() {
        let controller = makeController()
        // Already in Automatic with no notice: neither button may start a session.
        controller.handleNotificationResponse(
            action: HandBackNotification.keepOnAction, request: HandBackNotification.soonIdentifier
        )
        controller.handleNotificationResponse(
            action: HandBackNotification.turnOnAgainAction, request: HandBackNotification.endedIdentifier
        )
        XCTAssertEqual(controller.mode, .automatic)
        XCTAssertNil(controller.automaticRestoreDeadline)
        XCTAssertNil(controller.modeActionFeedback)
    }
}
