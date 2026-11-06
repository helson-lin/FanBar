import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// Switching the interface language must repaint every Settings tab in place.
/// `fanBarText` reads UserDefaults outside SwiftUI's dependency tracking, so a
/// child view whose inputs did not change can keep the previous language.
@MainActor
final class SettingsLanguageRefreshTests: XCTestCase {
    private func makeController() -> FanController {
        let source = FakeFanReadingSource()
        return FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source },
                             readUsage: { SystemUsage() }, refreshInterval: nil)
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testEveryTabRepaintsInTheNewLanguage() throws {
        let defaults = UserDefaults.standard
        let savedLanguage = defaults.object(forKey: FanBarLanguage.preferenceKey)
        let savedTab = defaults.object(forKey: SettingsTab.preferenceKey)
        defer {
            defaults.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
            defaults.set(savedTab, forKey: SettingsTab.preferenceKey)
        }
        let controller = makeController()
        var stale: [String] = []
        for tab in SettingsTab.allCases {
            defaults.set(tab.rawValue, forKey: SettingsTab.preferenceKey)
            defaults.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
            let host = NSHostingView(rootView: FanBarSettingsView(controller: controller).frame(width: 560, height: 1400))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 1400),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            let referenceWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 1400),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = host
            window.orderFront(nil)
            referenceWindow.orderBack(nil)
            defer {
                window.orderOut(nil)
                window.contentView = nil
                referenceWindow.orderOut(nil)
                referenceWindow.contentView = nil
            }
            for language in [FanBarLanguage.japanese, .english, .chinese, .traditionalChinese, .russian, .french] {
                defaults.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                host.layoutSubtreeIfNeeded()
                let actual = try snapshot(host)
                let fresh = NSHostingView(rootView: FanBarSettingsView(controller: controller).frame(width: 560, height: 1400))
                fresh.frame = host.frame
                referenceWindow.contentView = fresh
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                fresh.layoutSubtreeIfNeeded()
                let expected = try snapshot(fresh)
                referenceWindow.contentView = nil
                if actual != expected, try LanguageRefreshRendering.difference(actual, expected) >= 0.03 {
                    stale.append("\(tab.rawValue)→\(language.rawValue)")
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
            }
        }
        XCTAssertEqual(stale, [], "Tabs that kept the previous language")
    }
}
