import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
final class DeviceCompatibilityLayoutTests: XCTestCase {
    func testCapabilityStatesFitScrollableNativeWindowWithoutChangingControl() {
        for scenario in 0..<3 {
            let source = FakeFanReadingSource(readings: scenario == 1 ? [] : [
                FanReading(index: 0, minimumRPM: 1200, currentRPM: 1850, maximumRPM: 6000, isManual: false),
            ])
            if scenario == 2 { source.error = SMCError.unavailable(-1) }
            let controller = FanController(
                notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source }
            )
            let host = NSHostingView(rootView: DeviceCompatibilityView(controller: controller))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 570)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.bounds.width, 560, accuracy: 0.5)
            XCTAssertEqual(host.bounds.height, 570, accuracy: 0.5)
            XCTAssertEqual(controller.mode, .automatic)
            XCTAssertNotNil(controller.compatibilitySnapshot)
        }
    }

    func testStandaloneWindowCanResizeAndRepeatedOpeningReusesIt() throws {
        _ = NSApplication.shared
        guard let visible = NSScreen.main?.visibleFrame, visible.width >= 640, visible.height >= 520 else {
            throw XCTSkip("Window resize validation requires an accessible display")
        }
        let target = NSSize(width: min(800, visible.width - 80), height: min(720, visible.height - 100))
        let presenter = CompatibilityWindowPresenter()
        let source = FakeFanReadingSource()
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source })
        let window = presenter.show(controller: controller)
        defer { presenter.close() }
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertNil(window.sheetParent)
        window.setContentSize(target)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentView?.bounds.width ?? 0, target.width, accuracy: 0.5)
        XCTAssertEqual(window.contentView?.bounds.height ?? 0, target.height, accuracy: 0.5)
        XCTAssertEqual(window.contentView?.subviews.first?.bounds.height ?? 0, target.height, accuracy: 0.5)
        XCTAssertTrue(presenter.show(controller: controller) === window)
        XCTAssertEqual(window.contentView?.bounds.width ?? 0, target.width, accuracy: 0.5)
        if let path = ProcessInfo.processInfo.environment["FANBAR_DESIGN_CAPTURE_PATH"] {
            let savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
            defer {
                if let savedLanguage {
                    UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
                }
            }
            for (name, appearance, size) in [
                ("light", NSAppearance.Name.aqua, NSSize(width: 740, height: 780)),
                ("dark", NSAppearance.Name.darkAqua, NSSize(width: 740, height: 780)),
                ("narrow", NSAppearance.Name.aqua, NSSize(width: 560, height: 640)),
                ("english", NSAppearance.Name.aqua, NSSize(width: 560, height: 640)),
            ] {
                if name == "english" {
                    UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
                    let host = window.contentView?.subviews.first as? NSHostingView<DeviceCompatibilityView>
                    host?.rootView = DeviceCompatibilityView(controller: controller)
                }
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(size)
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let view = try XCTUnwrap(window.contentView)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("compatibility-\(name).png"))
            }
        }
    }

    func testOnboardingFitsItsWindowInChineseEnglishAndKoreanWithoutChangingControl() {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
            }
        }
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { FakeFanReadingSource() }
        )
        for language in [FanBarLanguage.chinese, .english, .korean] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            // Measured before the window exists, as OnboardingWindowPresenter does.
            OnboardingCard.forgetMeasuredHeights()
            let expectedHeight = OnboardingCard.height(for: controller)
            let host = NSHostingView(rootView: OnboardingCard(controller: controller, onOpenMenu: {}, onDismiss: {}))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, OnboardingCard.width, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, expectedHeight, accuracy: 0.5)
            XCTAssertEqual(controller.mode, .automatic)
            XCTAssertFalse(controller.isTestingCompatibilityControl)
        }
    }

    /// Translations differ in length by several lines: in every language the window shows
    /// everything, including the permission notice, without scrolling or an empty band.
    func testOnboardingShowsEverythingWithoutScrollingInEveryLanguage() {
        let savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer { UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey) }
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { FakeFanReadingSource() }
        )
        XCTAssertNotEqual(controller.helperState, .enabled)
        for language in [FanBarLanguage.chinese, .english, .japanese, .russian, .french] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            let content = NSHostingView(rootView: OnboardingCard(
                controller: controller, onOpenMenu: {}, onDismiss: {}, showsContentOnly: true
            ))
            // On a screen too short for it (CI's virtual display), the window stops at the cap and scrolls.
            let needed = min(content.fittingSize.height + OnboardingCard.footerHeight, OnboardingCard.maximumHeight)
            OnboardingCard.forgetMeasuredHeights() // a height cached by an earlier test may be stale
            _ = OnboardingCard.height(for: controller) // as the presenter does before showing the window
            let window = NSHostingView(rootView: OnboardingCard(controller: controller, onOpenMenu: {}, onDismiss: {}))
            let height = window.fittingSize.height
            XCTAssertGreaterThanOrEqual(height + 0.5, needed, "\(language.rawValue) needs \(needed)")
            XCTAssertLessThan(height, needed + 2, "\(language.rawValue) leaves an empty band")
        }
    }

    func testOnboardingDesignCapture() throws {
        guard let path = ProcessInfo.processInfo.environment["FANBAR_ONBOARDING_CAPTURE_PATH"] else { return }
        _ = NSApplication.shared
        let savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer {
            if let savedLanguage {
                UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
            }
        }
        let controller = FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled,
                                       makeReadingSource: { FakeFanReadingSource() })
        for (name, appearance, language) in [
            ("light", NSAppearance.Name.aqua, FanBarLanguage.chinese),
            ("dark", NSAppearance.Name.darkAqua, FanBarLanguage.chinese),
            ("english", NSAppearance.Name.aqua, FanBarLanguage.english),
        ] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            let host = NSHostingView(rootView: OnboardingCard(controller: controller, onOpenMenu: {}, onDismiss: {}))
            let height = OnboardingCard.height(for: controller)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: OnboardingCard.width, height: height),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.appearance = NSAppearance(named: appearance)
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("onboarding-\(name).png"))
            window.close()
        }
    }

    func testReportPreviewFitsNativeSettingsWidth() throws {
        let source = FakeFanReadingSource()
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source }
        )
        let snapshot = try XCTUnwrap(controller.compatibilitySnapshot)
        let data = try CompatibilityReport(snapshot: snapshot).jsonData()
        let host = NSHostingView(rootView: CompatibilityReportPreview(data: data))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 510, accuracy: 0.5)
        XCTAssertLessThan(host.fittingSize.height, 600)
    }
}
