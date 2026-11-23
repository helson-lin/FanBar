import XCTest
@testable import FanBar

final class MenuBarStatusCompositionTests: XCTestCase {
    func testGlyphKeepsTheIconAndDropsIconOnlyText() {
        let iconOnly = MenuBarStatusComposition.make(style: .fan, displayMode: .iconOnly, reading: nil)
        XCTAssertTrue(iconOnly.showsGlyph)
        XCTAssertNil(iconOnly.text)

        let temperature = MenuBarStatusComposition.make(style: .outline, displayMode: .cpuTemperature, reading: "54°")
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

    func testReadingTextMatchesEachDisplayMode() {
        let temperature = "54°"
        let fanSpeed = "1,800"

        XCTAssertNil(
            MenuBarStatusReadout.make(
                displayMode: .iconOnly,
                temperature: temperature,
                fanSpeed: fanSpeed
            )
        )
        XCTAssertEqual(
            MenuBarStatusReadout.make(
                displayMode: .cpuTemperature,
                temperature: temperature,
                fanSpeed: fanSpeed
            ),
            "54°"
        )
        XCTAssertEqual(
            MenuBarStatusReadout.make(
                displayMode: .fanSpeed,
                temperature: temperature,
                fanSpeed: fanSpeed
            ),
            "1,800"
        )
        XCTAssertEqual(
            MenuBarStatusReadout.make(
                displayMode: .temperatureAndFanSpeed,
                temperature: temperature,
                fanSpeed: fanSpeed
            ),
            "54° · 1,800"
        )
        XCTAssertEqual(
            MenuBarStatusReadout.make(
                displayMode: .temperatureOverFanSpeed,
                temperature: temperature,
                fanSpeed: fanSpeed
            ),
            "54°\n1,800"
        )
    }
}
