import AppKit
import XCTest
@testable import FanBar

@MainActor
final class MenuBarIconAnimatorTests: XCTestCase {
    /// Reduce Motion is fixed off so the host's accessibility settings,
    /// such as a CI runner's, cannot skip these tests. Without a rotor the
    /// animator swaps frames, as on Intel Macs.
    private func makeAnimator(reduceMotion: Bool = false) -> (MenuBarIconAnimator, NSButton) {
        (MenuBarIconAnimator(reduceMotion: { reduceMotion }, rotor: nil), NSButton())
    }

    private func runMainLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Regression: a steady reading used to spin only for a short burst and
    /// then leave the icon still while the fans kept running.
    func testSteadyRunningFansKeepSpinningPastBurst() {
        let (animator, button) = makeAnimator()
        let wait = MenuBarIconAnimator.burstDuration + 1.5
        var elapsed = 0.0
        while elapsed < wait {
            animator.update(rpm: 1_850, on: button, style: .defaultStyle, isManual: false)
            runMainLoop(for: 0.5)
            elapsed += 0.5
        }
        XCTAssertTrue(animator.isAnimating)
        animator.stop()
    }

    func testFirstRunningReadingStartsSpinning() {
        let (animator, button) = makeAnimator()
        animator.update(rpm: 1_850, on: button, style: .defaultStyle, isManual: false)
        XCTAssertTrue(animator.isAnimating)
        animator.stop()
    }

    func testStoppedFansStayStill() {
        let (animator, button) = makeAnimator()
        animator.update(rpm: 0, on: button, style: .defaultStyle, isManual: false)
        XCTAssertFalse(animator.isAnimating)
    }

    func testStoppingFansCoastToRestAndRunningFansResume() {
        let (animator, button) = makeAnimator()
        animator.update(rpm: 1_850, on: button, style: .defaultStyle, isManual: false)
        animator.update(rpm: 0, on: button, style: .defaultStyle, isManual: false)
        runMainLoop(for: 2)
        XCTAssertFalse(animator.isAnimating)

        animator.update(rpm: 1_850, on: button, style: .defaultStyle, isManual: false)
        XCTAssertTrue(animator.isAnimating)
        animator.stop()
    }

    func testReduceMotionKeepsRunningFansStill() {
        let (animator, button) = makeAnimator(reduceMotion: true)
        animator.update(rpm: 1_850, on: button, style: .defaultStyle, isManual: false)
        XCTAssertFalse(animator.isAnimating)
        animator.playSwitchBurst()
        XCTAssertFalse(animator.isAnimating)
    }

    /// A switch spins the icon even with the fans stopped, then it coasts
    /// to rest once the burst ends.
    func testSwitchBurstWithStoppedFansCoastsToRest() {
        let (animator, button) = makeAnimator()
        animator.update(rpm: 0, on: button, style: .defaultStyle, isManual: false)
        animator.playSwitchBurst()
        XCTAssertTrue(animator.isAnimating)
        runMainLoop(for: MenuBarIconAnimator.burstDuration + 1.5)
        XCTAssertFalse(animator.isAnimating)
    }

    func testSpeedFollowsTheFansUpToTheFrameRateCap() {
        let cap = MenuBarIconAnimator.frameQuantum * MenuBarIconAnimator.maximumFramesPerSecond
        XCTAssertEqual(cap, 120)
        XCTAssertEqual(MenuBarIconAnimator.perceptualVelocity(forRPM: 0, capped: true), 0)
        // Slow fans still visibly turn.
        XCTAssertEqual(MenuBarIconAnimator.perceptualVelocity(forRPM: 600, capped: true), 0.18 * 360, accuracy: 1e-9)
        XCTAssertLessThan(
            MenuBarIconAnimator.perceptualVelocity(forRPM: 1_000, capped: true),
            MenuBarIconAnimator.perceptualVelocity(forRPM: 1_600, capped: true)
        )
        // Above the cap, faster fans cost no more frames.
        XCTAssertEqual(MenuBarIconAnimator.perceptualVelocity(forRPM: 3_000, capped: true), cap)
        XCTAssertEqual(MenuBarIconAnimator.perceptualVelocity(forRPM: 6_000, capped: true), cap)
        // The rotor swaps nothing, so it keeps following faster fans.
        XCTAssertEqual(MenuBarIconAnimator.perceptualVelocity(forRPM: 3_000, capped: false), 0.6 * 360, accuracy: 1e-9)
    }

    /// Each frame swap re-snapshots the status item on every menu bar, so the
    /// swap rate is what costs CPU. Uncapped, 4,900 RPM swapped 10 frames a second.
    func testFastFansSwapAtMostFourFramesASecond() {
        let (animator, button) = makeAnimator()
        animator.update(rpm: 4_900, on: button, style: .defaultStyle, isManual: false)
        // Let the spin-up reach full speed before counting.
        runMainLoop(for: 1.5)
        var swaps = 0
        var shown = button.image
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            runMainLoop(for: 0.01)
            if button.image !== shown {
                swaps += 1
                shown = button.image
            }
        }
        animator.stop()
        XCTAssertGreaterThan(swaps, 0)
        XCTAssertLessThanOrEqual(swaps, 13, "4 frames a second over 3 s, plus one for timing slack")
    }

    /// The rotor turns the icon in the render server: the button keeps one
    /// still image, so no menu bar has to be re-snapshotted while it spins.
    func testRotorSpinsWithoutSwappingTheButtonImage() throws {
        try XCTSkipUnless(MenuBarIconRotor.isSupported, "Intel Macs swap frames instead")
        let rotor = MenuBarIconRotor()
        let animator = MenuBarIconAnimator(reduceMotion: { false }, rotor: rotor)
        let button = NSButton(title: "", target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 22)
        let window = NSWindow(contentRect: button.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = button
        defer { window.contentView = nil }

        animator.update(rpm: 3_000, on: button, style: .defaultStyle, isManual: false)
        runMainLoop(for: 0.3)
        let still = button.image
        XCTAssertNotNil(still)
        XCTAssertTrue(rotor.isAttached)
        var swaps = 0
        let end = Date().addingTimeInterval(1.5)
        while Date() < end {
            animator.update(rpm: 3_000, on: button, style: .defaultStyle, isManual: false)
            runMainLoop(for: 0.05)
            if button.image !== still { swaps += 1 }
        }
        XCTAssertEqual(swaps, 0)
        // Uncapped: 3,000 RPM is 0.6 turns a second once smoothing settles.
        XCTAssertEqual(rotor.turnsPerSecond, 0.6, accuracy: 0.05)

        animator.stop()
        XCTAssertFalse(rotor.isAttached)
    }
}
