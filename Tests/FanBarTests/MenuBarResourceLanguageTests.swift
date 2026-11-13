import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
final class MenuBarResourceLanguageTests: XCTestCase {
    func testResourceSectionRepaintsWithoutNewReadings() throws {
        let defaults = UserDefaults.standard
        let keys = [FanBarLanguage.preferenceKey] + MenuBarResource.allCases.flatMap {
            [$0.preferenceKey, $0.stylePreferenceKey]
        }
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved {
            defaults.set(value, forKey: key)
        } }
        for resource in MenuBarResource.allCases {
            defaults.set(false, forKey: resource.preferenceKey)
            defaults.set(MenuBarResourceStyle.label.rawValue, forKey: resource.stylePreferenceKey)
        }
        defaults.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
        let source = FakeFanReadingSource()
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source },
            readUsage: { SystemUsage() }, refreshInterval: nil
        )
        let host = makeHost(controller)
        let window = makeWindow(host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        for language in [FanBarLanguage.japanese, .english, .chinese, .traditionalChinese, .russian, .french, .korean] {
            defaults.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            settle(host)
            let actual = try snapshot(host)
            let fresh = makeHost(controller)
            let reference = makeWindow(fresh)
            settle(fresh)
            let expected = try snapshot(fresh)
            reference.orderOut(nil)
            reference.contentView = nil
            XCTAssertLessThan(
                try LanguageRefreshRendering.difference(actual, expected), 0.03,
                "The resource section kept stale text after switching to \(language.rawValue)"
            )
        }
    }

    private func makeHost(_ controller: FanController) -> NSView {
        NSHostingView(rootView: MenuBarResourceSettings(controller: controller)
            .padding(24)
            .frame(width: 560, height: 400)
            .environment(\.colorScheme, .light)
            .transaction { $0.animation = nil }
            .environment(\.locale, Locale(identifier: "en_US_POSIX")))
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        window.orderBack(nil)
        return window
    }

    private func settle(_ view: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
