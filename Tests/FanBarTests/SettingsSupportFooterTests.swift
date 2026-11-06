import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// The General tab's footer stays one line in every language.
final class SettingsSupportFooterTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
        super.tearDown()
    }

    @MainActor
    func testFooterFitsOneLineInEveryLanguage() throws {
        // The settings page insets its sections from the window edges.
        let availableWidth = SettingsChrome.contentWidth - 48
        for language in [FanBarLanguage.chinese, .traditionalChinese, .english, .japanese, .russian, .french] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            let host = NSHostingView(rootView: SettingsSupportFooter().fixedSize())
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            XCTAssertLessThan(size.width, availableWidth, language.rawValue)
            XCTAssertLessThan(size.height, 40, language.rawValue)
            try writeReviewImage(host, name: "footer-\(language.rawValue)")
        }
    }

    @MainActor
    private func writeReviewImage(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["FANBAR_SUPPORT_RENDER_DIR"] else { return }
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
