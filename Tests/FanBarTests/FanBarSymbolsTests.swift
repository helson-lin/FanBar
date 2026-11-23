import AppKit
import XCTest
@testable import FanBar

final class FanBarSymbolsTests: XCTestCase {
    private func macOS(_ major: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
    }

    func testOlderSystemsGetSymbolsThatExistOnMacOS11() {
        let bigSur = macOS(11)
        XCTAssertEqual(FanBarSymbols.fan(on: bigSur), "wind")
        XCTAssertEqual(FanBarSymbols.fanFill(on: bigSur), "wind")
        XCTAssertEqual(FanBarSymbols.fanBlades(on: bigSur), "wind")
        XCTAssertEqual(FanBarSymbols.fanSlash(on: bigSur), "exclamationmark.triangle")
        XCTAssertEqual(FanBarSymbols.balanced(on: bigSur), "circle.lefthalf.fill")
        XCTAssertEqual(FanBarSymbols.gauge(on: bigSur), "speedometer")
    }

    func testEachSymbolSwitchesAtTheReleaseThatIntroducedIt() {
        XCTAssertEqual(FanBarSymbols.fanFill(on: macOS(12)), "fanblades.fill")
        XCTAssertEqual(FanBarSymbols.fanFill(on: macOS(13)), "fanblades.fill")
        XCTAssertEqual(FanBarSymbols.fanBlades(on: macOS(12)), "fanblades")
        XCTAssertEqual(FanBarSymbols.balanced(on: macOS(12)), "circle.lefthalf.filled")
        XCTAssertEqual(FanBarSymbols.fan(on: macOS(13)), "fanblades")
        XCTAssertEqual(FanBarSymbols.gauge(on: macOS(13)), "speedometer")
        XCTAssertEqual(FanBarSymbols.fanSlash(on: macOS(13)), "exclamationmark.triangle")
        XCTAssertEqual(FanBarSymbols.fan(on: macOS(14)), "fan")
        XCTAssertEqual(FanBarSymbols.fanFill(on: macOS(14)), "fan.fill")
        XCTAssertEqual(FanBarSymbols.fanSlash(on: macOS(14)), "fan.slash")
        XCTAssertEqual(FanBarSymbols.gauge(on: macOS(14)), "gauge.with.dots.needle.67percent")
    }

    func testEveryChosenAndFallbackNameResolvesOnThisSystem() {
        let names = [
            FanBarSymbols.fan, FanBarSymbols.fanFill,
            FanBarSymbols.fanBlades, FanBarSymbols.fanSlash,
            FanBarSymbols.balanced, FanBarSymbols.gauge
        ] + [11, 12, 13].flatMap { major in
            [
                FanBarSymbols.fan(on: macOS(major)), FanBarSymbols.fanFill(on: macOS(major)),
                FanBarSymbols.fanSlash(on: macOS(major)),
                FanBarSymbols.balanced(on: macOS(major)), FanBarSymbols.gauge(on: macOS(major))
            ]
        }
        for name in Set(names) {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }
}
