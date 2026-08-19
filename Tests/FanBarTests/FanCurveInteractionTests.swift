import CoreGraphics
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

final class FanCurveInteractionTests: XCTestCase {
    /// A transient progress state must not resize the menu-bar popover. AppKit
    /// follows the hosting view's fitting size, so any delta is visible jitter.
    @MainActor
    func testModeProgressDoesNotChangeMenuHeight() {
        let onboardingKey = "fanbar.onboarding.v1.completed"
        let originalValue = UserDefaults.standard.object(forKey: onboardingKey)
        defer {
            if let originalValue {
                UserDefaults.standard.set(originalValue, forKey: onboardingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: onboardingKey)
            }
        }
        UserDefaults.standard.set(true, forKey: onboardingKey)

        let controller = FanController(notificationCenter: nil)
        controller.refresh()
        XCTAssertTrue(controller.isAvailable)

        let host = NSHostingView(rootView: FanMenu(controller: controller))
        host.frame = NSRect(x: 0, y: 0, width: 384, height: 1_000)
        // Let AppStorage and the first ObservableObject delivery settle before
        // taking the baseline; the assertion should measure only feedback.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        // Warm the first ObservableObject-driven SwiftUI rebuild; otherwise
        // NSHostingView's initial fitting-size cache contributes an unrelated
        // four-point delta to the feedback measurement.
        controller.beginModeAction("warm-up")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.clearModeActionFeedback()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let restingHeight = host.fittingSize.height

        controller.beginModeAction("正在切换到静音温控…")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.fittingSize.height, restingHeight, accuracy: 0.5)

        controller.failModeAction("静音温控开启失败")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.fittingSize.height, restingHeight, accuracy: 0.5)
    }

    /// Moving the app must invalidate the launchd registration even when the
    /// embedded helper's build number is unchanged.
    func testHelperMigrationRunsWhenAppMovesAtSameBuildVersion() {
        XCTAssertTrue(HelperMigrationPolicy.requiresMigration(
            currentBuildVersion: "8",
            currentBundlePath: "/Applications/FanBar.app",
            savedBuildVersion: "8",
            savedBundlePath: "/Users/test/Downloads/FanBar.app"
        ))
        XCTAssertFalse(HelperMigrationPolicy.requiresMigration(
            currentBuildVersion: "8",
            currentBundlePath: "/Applications/FanBar.app",
            savedBuildVersion: "8",
            savedBundlePath: "/Applications/FanBar.app"
        ))
    }

    /// Grabbing away from the visual center must not make the handle jump on
    /// the first drag frame; the same offset should survive pointer movement.
    func testDragPreservesGrabOffset() {
        let originalCenter = CGPoint(x: 180, y: 92)
        let pointerDown = CGPoint(x: 189, y: 86)
        let grabOffset = FanCurveDragGeometry.grabOffset(
            pointer: pointerDown,
            handleCenter: originalCenter
        )

        XCTAssertEqual(grabOffset.width, 9)
        XCTAssertEqual(grabOffset.height, -6)
        XCTAssertEqual(
            FanCurveDragGeometry.handleCenter(
                pointer: CGPoint(x: 229, y: 106),
                grabOffset: grabOffset
            ),
            CGPoint(x: 220, y: 112)
        )
    }

    /// A center grab is the common path and should remain exactly 1:1 with
    /// pointer movement in the named canvas coordinate space.
    func testCenterGrabTracksPointerOneToOne() {
        let center = CGPoint(x: 75, y: 140)
        let grabOffset = FanCurveDragGeometry.grabOffset(
            pointer: center,
            handleCenter: center
        )

        XCTAssertEqual(grabOffset, .zero)
        XCTAssertEqual(
            FanCurveDragGeometry.handleCenter(
                pointer: CGPoint(x: 101, y: 124),
                grabOffset: grabOffset
            ),
            CGPoint(x: 101, y: 124)
        )
    }

    /// Reset is intentionally limited to the visible curve and sensor; expert
    /// tuning stays intact so Undo restores only what the command replaced.
    func testFactoryResetPreservesAdvancedTuning() {
        let customized = FanCurveProfile(
            sensor: .ssd,
            points: [
                FanCurvePoint(celsius: 40, fraction: 0.10),
                FanCurvePoint(celsius: 80, fraction: 0.90)
            ],
            hysteresisCelsius: 4,
            maxFractionStepPerUpdate: 0.12
        )

        let restored = customized.resettingCurveToFactory(for: .performance)
        let factory = FanCoolingPreset.performance.factoryCurve.sanitized()

        XCTAssertTrue(restored.hasFactoryCurve(for: .performance))
        XCTAssertEqual(restored.sensor, factory.sensor)
        XCTAssertEqual(restored.points.map(\.celsius), factory.points.map(\.celsius))
        XCTAssertEqual(restored.points.map(\.fraction), factory.points.map(\.fraction))
        XCTAssertEqual(restored.hysteresisCelsius, 4)
        XCTAssertEqual(restored.maxFractionStepPerUpdate, 0.12)
    }

    func testFactoryDetectionIgnoresAnchorIdentityButDetectsShapeChanges() {
        var restored = FanCoolingPreset.silent.factoryCurve
            .resettingCurveToFactory(for: .silent)

        XCTAssertTrue(restored.hasFactoryCurve(for: .silent))

        restored.points[0].fraction = 0.01
        XCTAssertFalse(restored.hasFactoryCurve(for: .silent))
    }

    /// Automatic persistence must still participate in the native macOS
    /// Undo/Redo chain so a factory reset is forgiving rather than destructive.
    @MainActor
    func testCurveReplacementSupportsUndoAndRedo() {
        let controller = FanController(notificationCenter: nil)
        let preset = controller.curveCoolingPreset
        let original = controller.curveProfile
        var edited = original
        edited.points[0].fraction = min(
            edited.points[0].fraction + 0.01,
            FanCurveProfile.maximumFraction
        )
        edited = edited.sanitized()

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        controller.replaceCurveProfile(
            edited,
            for: preset,
            registeringUndoWith: undoManager,
            actionName: "Reset Default Curve"
        )
        undoManager.endUndoGrouping()

        XCTAssertEqual(controller.curveProfile, edited)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(controller.curveProfile, original.sanitized())
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(controller.curveProfile, edited)

        // Leave the isolated test preference domain in its original state.
        controller.setCurveProfile(original, for: preset)
    }

    @MainActor
    func testModeActionFeedbackReplacesProgressWithFailureAndDismisses() {
        let controller = FanController(notificationCenter: nil)

        controller.beginModeAction("Switching to Silent curve…")
        XCTAssertEqual(
            controller.modeActionFeedback,
            FanController.ModeActionFeedback(
                kind: .inProgress,
                message: "Switching to Silent curve…"
            )
        )

        controller.failModeAction("Unable to enable Silent curve")
        XCTAssertEqual(
            controller.modeActionFeedback,
            FanController.ModeActionFeedback(
                kind: .failure,
                message: "Unable to enable Silent curve"
            )
        )

        controller.failModeAction(
            "The fan control service did not respond",
            offersHelperSettings: true
        )
        XCTAssertEqual(controller.modeActionFeedback?.offersHelperSettings, true)

        controller.clearModeActionFeedback()
        XCTAssertNil(controller.modeActionFeedback)
    }

    /// An XPC daemon can accept a connection without ever invoking its reply
    /// block. The client must release the waiting continuation in that case.
    func testHelperReplyGateTimesOutAndIgnoresLateReply() {
        let gate = ReplyGate()
        let timeoutFired = expectation(description: "request timeout")
        gate.scheduleTimeout(after: 0.01) {
            timeoutFired.fulfill()
        }

        wait(for: [timeoutFired], timeout: 1)

        let lateReply = expectation(description: "late XPC reply is ignored")
        lateReply.isInverted = true
        gate.once {
            lateReply.fulfill()
        }
        wait(for: [lateReply], timeout: 0.05)
    }

    /// A normal reply wins the same gate and cancels the pending timeout.
    func testHelperReplyGateCancelsTimeoutAfterReply() {
        let gate = ReplyGate()
        let timeoutFired = expectation(description: "cancelled timeout")
        timeoutFired.isInverted = true
        gate.scheduleTimeout(after: 0.01) {
            timeoutFired.fulfill()
        }

        gate.once {}
        wait(for: [timeoutFired], timeout: 0.05)
    }

    /// A delayed invalidation callback belongs to the connection generation
    /// that installed it and must not clear a later retry connection.
    func testStaleConnectionGenerationCannotClearReplacement() {
        var generations = HelperConnectionGenerations()
        let first = generations.issue()
        let replacement = generations.issue()

        XCTAssertFalse(generations.isCurrent(first))
        XCTAssertTrue(generations.isCurrent(replacement))
    }

    /// A failed hardware activation must leave the visible preset and its
    /// active curve untouched so the UI never claims a mode the Mac did not enter.
    @MainActor
    func testFailedCurveActivationDoesNotCommitPresetSelection() {
        let controller = FanController(notificationCenter: nil)
        let originalPreset = controller.curveCoolingPreset
        let originalProfile = controller.curveProfile
        let targetPreset = FanCoolingPreset.allCases.first { $0 != originalPreset }!

        controller.completeCurveActivation(
            preset: targetPreset,
            profile: targetPreset.factoryCurve,
            succeeded: false
        )

        XCTAssertEqual(controller.curveCoolingPreset, originalPreset)
        XCTAssertEqual(controller.curveProfile, originalProfile)
    }

    /// Falling hysteresis is an output state, not a one-sample edge. Repeated
    /// readings at the same cooler temperature must continue holding RPM.
    func testFallingHysteresisPersistsAcrossEqualTemperatureSamples() {
        let profile = FanCurveProfile(
            sensor: .cpu,
            points: [
                FanCurvePoint(celsius: 50, fraction: 0.40),
                FanCurvePoint(celsius: 60, fraction: 0.60),
                FanCurvePoint(celsius: 70, fraction: 0.80)
            ],
            hysteresisCelsius: 2,
            maxFractionStepPerUpdate: 0.20
        )

        let firstCoolSample = FanCurveControlTarget.fraction(
            profile: profile,
            temperature: 58,
            previousFraction: 0.60,
            force: false
        )
        let equalCoolSample = FanCurveControlTarget.fraction(
            profile: profile,
            temperature: 58,
            previousFraction: firstCoolSample,
            force: false
        )

        XCTAssertEqual(firstCoolSample, 0.60, accuracy: 0.001)
        XCTAssertEqual(equalCoolSample, 0.60, accuracy: 0.001)
    }

    func testFallingHysteresisNeverRaisesOutputWhileCooling() {
        let profile = FanCurveProfile(
            sensor: .cpu,
            points: [
                FanCurvePoint(celsius: 50, fraction: 0.40),
                FanCurvePoint(celsius: 60, fraction: 0.60),
                FanCurvePoint(celsius: 70, fraction: 0.80)
            ],
            hysteresisCelsius: 2,
            maxFractionStepPerUpdate: 0.20
        )

        let target = FanCurveControlTarget.fraction(
            profile: profile,
            temperature: 59,
            previousFraction: 0.60,
            force: false
        )

        XCTAssertEqual(target, 0.60, accuracy: 0.001)
    }

    func testSettingsWindowHeightIsClampedToVisibleScreen() {
        let contentSize = SettingsWindowSizing.contentSize(
            fittingSize: NSSize(width: 460, height: 1_200),
            visibleScreenSize: NSSize(width: 1_440, height: 800)
        )

        XCTAssertEqual(contentSize.width, 460)
        XCTAssertLessThanOrEqual(contentSize.height, 720)
    }
}
