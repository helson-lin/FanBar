import XCTest
@testable import FanBar

final class SettingsTabTests: XCTestCase {
    func testMenuBarKeepsSavedSelectionAndTabsFollowDisplayedOrder() {
        XCTAssertEqual(SettingsTab(rawValue: "menuBar"), .appearance)
        XCTAssertEqual(SettingsTab.allCases, [.cooling, .appearance, .panel, .general, .log])
    }
}
