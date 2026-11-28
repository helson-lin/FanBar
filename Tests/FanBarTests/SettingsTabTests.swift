import AppKit
import FanBarShared
import XCTest
@testable import FanBar

final class SettingsTabTests: XCTestCase {
    func testMenuBarKeepsSavedSelectionAndTabsFollowDisplayedOrder() {
        XCTAssertEqual(SettingsTab(rawValue: "menuBar"), .appearance)
        XCTAssertEqual(SettingsTab.allCases, [.general, .cooling, .appearance, .panel, .log])
        XCTAssertEqual(SettingsTab(rawValue: "cooling"), .cooling)
        XCTAssertEqual(SettingsTab(rawValue: "panel"), .panel)
        XCTAssertEqual(SettingsTab.panel.symbol, "rectangle.grid.1x2")
    }

    @MainActor
    func testToolbarUsesLocalizedFanSpeedAndPanelsLabels() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: FanBarLanguage.preferenceKey)
        defer { defaults.set(saved, forKey: FanBarLanguage.preferenceKey) }

        let presenter = SettingsWindowPresenter.shared
        let toolbar = NSToolbar(identifier: "settings-test")
        for (language, expected) in [
            (FanBarLanguage.english, ["General", "Fan Speed", "Menu Bar", "Panels", "History"]),
            (.chinese, ["通用", "风扇转速", "菜单栏", "面板", "记录"]),
        ] {
            defaults.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            let items = try presenter.toolbarDefaultItemIdentifiers(toolbar).map { identifier in
                try XCTUnwrap(presenter.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true))
            }
            XCTAssertEqual(items.map(\.label), expected)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
                    XCTAssertTrue(items.allSatisfy { $0.image?.tiffRepresentation != nil })
                }
            }
        }
    }
}
