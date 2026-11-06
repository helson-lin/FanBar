import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// Lays the panel out in each notice and failure state. Set
/// FANBAR_NOTICE_RENDER_DIR to also write light and dark PNGs for review.
@MainActor
final class ControlNoticeRenderingTests: XCTestCase {
    private var savedLanguage: Any?

    override func setUp() async throws {
        savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        UserDefaults.standard.set(FanBarLanguage.chinese.rawValue, forKey: FanBarLanguage.preferenceKey)
        // CI runners have short displays that would cap the panel's height.
        FanMenu.visibleScreenHeight = { 4_000 }
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
        FanMenu.visibleScreenHeight = { NSScreen.main?.visibleFrame.height ?? 800 }
    }

    private func makeHost(_ controller: FanController, scheme: ColorScheme = .light) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: FanMenu(controller: controller)
            .environment(\.colorScheme, scheme)
            .transaction { $0.disablesAnimations = true })
        host.frame = NSRect(x: 0, y: 0, width: FanMenu.panelWidth, height: 1_000)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func settle(_ host: NSView) -> CGFloat {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private func makeController() -> FanController {
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled,
                                       makeReadingSource: { FakeFanReadingSource() },
                                       readUsage: { SystemUsage() }, refreshInterval: nil)
        controller.refresh()
        return controller
    }

    private static let risk = FanController.ModeActionFeedback(
        kind: .failure,
        localizedMessage: LocalizedControlText { "Restore failed: SMC operation F0Md failed (-536870206)" },
        title: LocalizedControlText { fanBarText("没能交回 macOS", "Couldn't hand back to macOS") },
        safety: LocalizedControlText { fanBarFormat("风扇仍保持 %@ RPM", "Fans are still held at %@ RPM", "2,400") },
        isRisk: true,
        recovery: .retry(.restore),
        detail: "SMC operation F0Md failed (-536870206)"
    )

    func testFailureBannerKeepsThePanelHeight() {
        let controller = makeController()
        let host = makeHost(controller)
        // Warm the first ObservableObject rebuild, as the progress test does.
        controller.setControlStateForTesting(notice: nil, feedback: FanController.ModeActionFeedback(kind: .inProgress, message: "warm-up"))
        controller.setControlStateForTesting(notice: nil)
        let resting = settle(host)

        controller.setControlStateForTesting(notice: nil, feedback: Self.risk)
        XCTAssertEqual(settle(host), resting, accuracy: 0.5)
    }

    func testHandBackNoticeAddsOneRowUnderTheStrip() {
        let controller = makeController()
        let host = makeHost(controller)
        controller.setControlStateForTesting(notice: nil, feedback: FanController.ModeActionFeedback(kind: .inProgress, message: "warm-up"))
        controller.setControlStateForTesting(notice: nil)
        let resting = settle(host)

        controller.setControlStateForTesting(notice: .handedBack(
            mode: .preset(.builtIn(.silent)), reason: .timer, duration: .thirtyMinutes, at: Date()
        ))
        let withNotice = settle(host)
        XCTAssertGreaterThan(withNotice, resting + 30)
        XCTAssertLessThan(withNotice, resting + 60)

        // A failure covers the strip and hides the notice instead of stacking.
        controller.setControlStateForTesting(
            notice: .handedBack(mode: .preset(.builtIn(.silent)), reason: .timer, duration: .thirtyMinutes, at: Date()),
            feedback: Self.risk
        )
        XCTAssertEqual(settle(host), resting, accuracy: 0.5)
    }

    func testRendersEveryStateForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["FANBAR_NOTICE_RENDER_DIR"] else {
            throw XCTSkip("Set FANBAR_NOTICE_RENDER_DIR to write PNGs")
        }
        let states: [ReviewState] = [
            ReviewState(name: "soon", notice: .handBackSoon(mode: .preset(.builtIn(.silent)), duration: .thirtyMinutes,
                                                            deadline: Date().addingTimeInterval(42))),
            ReviewState(name: "timer", notice: .handedBack(mode: .preset(.builtIn(.silent)), reason: .timer,
                                                           duration: .thirtyMinutes, at: Date())),
            ReviewState(name: "sensor", notice: .handedBack(mode: .preset(.builtIn(.balanced)), reason: .missingTemperature(.cpu),
                                                            duration: .thirtyMinutes, at: Date())),
            ReviewState(name: "risk", feedback: Self.risk),
            ReviewState(name: "switch", feedback: FanController.ModeActionFeedback(
                kind: .failure,
                localizedMessage: LocalizedControlText { "Unable to enable Silent curve" },
                title: LocalizedControlText { fanBarFormat("风扇没有响应，%@未开启", "The fans didn't respond; %@ didn't start", "静音") },
                safety: LocalizedControlText { fanBarText("风扇仍由 macOS 控制", "macOS is still controlling the fans") },
                recovery: .retry(.preset(.builtIn(.silent))),
                detail: "SMC operation F0Md failed (-536870206)"
            )),
            ReviewState(name: "unsupported", unsupported: true),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for state in states {
                let controller = makeController()
                controller.setControlStateForTesting(notice: state.notice, feedback: state.feedback, unsupported: state.unsupported)
                let host = makeHost(controller, scheme: scheme)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame.size.height = settle(host)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let file = "\(state.name)-\(scheme == .dark ? "dark" : "light").png"
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(file))
                window.contentView = nil
            }
        }
    }
}

/// One panel state for the review renders.
private struct ReviewState {
    let name: String
    var notice: ControlNotice?
    var feedback: FanController.ModeActionFeedback?
    var unsupported = false
}
