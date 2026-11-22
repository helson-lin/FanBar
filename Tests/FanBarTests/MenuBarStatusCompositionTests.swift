import XCTest
@testable import FanBar

final class MenuBarStatusCompositionTests: XCTestCase {
    func testGlyphKeepsTheIconAndDropsIconOnlyText() {
        let iconOnly = MenuBarStatusComposition.make(style: .swirl, displayMode: .iconOnly, reading: nil)
        XCTAssertTrue(iconOnly.showsGlyph)
        XCTAssertNil(iconOnly.text)

        let temperature = MenuBarStatusComposition.make(style: .ringed, displayMode: .cpuTemperature, reading: "54°")
        XCTAssertTrue(temperature.showsGlyph)
        XCTAssertEqual(temperature.text, "54°")
    }

    func testNoneShowsTheReadingWithoutAGlyph() {
        let stacked = MenuBarStatusComposition.make(
            style: .none,
            displayMode: .temperatureOverFanSpeed,
            reading: "54°\n1,800"
        )
        XCTAssertFalse(stacked.showsGlyph)
        XCTAssertEqual(stacked.text, "54°\n1,800")
    }

    func testNoneWithNoReadingKeepsAVisibleTitle() {
        let iconOnly = MenuBarStatusComposition.make(style: .none, displayMode: .iconOnly, reading: nil)
        XCTAssertFalse(iconOnly.showsGlyph)
        XCTAssertEqual(iconOnly.text, MenuBarStatusComposition.fallbackTitle)

        let missing = MenuBarStatusComposition.make(style: .none, displayMode: .fanSpeed, reading: nil)
        XCTAssertEqual(missing.text, MenuBarStatusComposition.fallbackTitle)
    }
}
