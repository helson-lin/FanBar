import FanBarShared
import XCTest
@testable import FanBar

final class SMCPowerDecoderTests: XCTestCase {
    private func floatBytes(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    func testAppleSiliconFloat() {
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "flt ", bytes: floatBytes(38.5)), 38.5)
        XCTAssertNil(SMCPowerDecoder.watts(dataType: "flt ", bytes: [0x00, 0x00]))
    }

    func testIntelSignedFixedPoint() {
        // sp96: 38.5 W × 64 = 0x09A0.
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "sp96", bytes: [0x09, 0xA0]), 38.5)
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "sp96", bytes: [0xFF, 0xC0]), -1)
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "sp78", bytes: [0x2A, 0x80]), 42.5)
    }

    func testIntelUnsignedFixedPoint() {
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "fpe2", bytes: [0x01, 0x90]), 100)
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "fp88", bytes: [0x14, 0x40]), 20.25)
    }

    func testIntegersAndIOFixed() {
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "ui8 ", bytes: [7]), 7)
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "ui16", bytes: [0x00, 0x2A]), 42)
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "ui32", bytes: [0, 0, 1, 0]), 256)
        XCTAssertNil(SMCPowerDecoder.watts(dataType: "ui32", bytes: [0, 1]))
        let ioft = withUnsafeBytes(of: UInt64(40 * 65536)) { Array($0) }
        XCTAssertEqual(SMCPowerDecoder.watts(dataType: "ioft", bytes: ioft), 40)
        XCTAssertNil(SMCPowerDecoder.watts(dataType: "ioft", bytes: [0, 0, 0, 0]))
    }

    func testUnknownTypesAreNotGuessed() {
        for type in ["ch8*", "flag", "sp99", "fp99", "spzz", "sp9", "{fds", ""] {
            XCTAssertNil(SMCPowerDecoder.watts(dataType: type, bytes: [0x09, 0xA0, 0, 0]), type)
        }
        XCTAssertNil(SMCPowerDecoder.watts(dataType: "sp96", bytes: [0x09]))
    }

    func testTypeName() {
        XCTAssertEqual(SMCPowerDecoder.typeName(0x666C_7420), "flt ")
        XCTAssertEqual(SMCPowerDecoder.typeName(0x7370_3936), "sp96")
    }
}

final class SystemPowerReadoutTests: XCTestCase {
    func testOnlyPlausibleReadingsAreShown() {
        XCTAssertEqual(SystemPowerReadout(watts: 38.4)?.watts, 38)
        XCTAssertEqual(SystemPowerReadout(watts: 500)?.watts, 500)
        XCTAssertEqual(SystemPowerReadout(watts: 0.6)?.watts, 1)
        for watts in [nil, 0, 0.4, -5, 500.5, .nan, .infinity] as [Double?] {
            XCTAssertNil(SystemPowerReadout(watts: watts), String(describing: watts))
        }
    }

    func testThermalReadingDropsImplausiblePower() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(ThermalReading(sampledAt: date, cpuCelsius: 50, gpuCelsius: nil, systemWatts: .nan).systemWatts)
        XCTAssertEqual(ThermalReading(sampledAt: date, cpuCelsius: 50, gpuCelsius: nil, systemWatts: 21).systemWatts, 21)
        // A NaN would make the whole history unencodable.
        let encoded = try JSONEncoder().encode([
            ThermalReading(sampledAt: date, cpuCelsius: 50, gpuCelsius: nil, systemWatts: .infinity),
        ])
        XCTAssertFalse(try XCTUnwrap(String(bytes: encoded, encoding: .utf8)).contains("systemWatts"))
    }

    func testHistoryWithoutPowerStillDecodes() throws {
        let json = #"[{"sampledAt":0,"cpuCelsius":50}]"#
        let decoded = try JSONDecoder().decode([ThermalReading].self, from: Data(json.utf8))
        XCTAssertNil(decoded.first?.systemWatts)
        XCTAssertEqual(decoded.first?.cpuCelsius, 50)
    }

    func testOnlyAFreshSampleCounts() {
        let now = Date(timeIntervalSince1970: 10_000)
        func sample(_ age: TimeInterval, watts: Double?) -> ThermalReading {
            ThermalReading(sampledAt: now.addingTimeInterval(-age), cpuCelsius: 50, gpuCelsius: nil, systemWatts: watts)
        }
        XCTAssertNil(SystemPowerReadout.current(from: [], now: now))
        XCTAssertEqual(SystemPowerReadout.current(from: [sample(2, watts: 18)], now: now)?.watts, 18)
        XCTAssertNil(SystemPowerReadout.current(from: [sample(60, watts: 18)], now: now))
        // An older reading does not stand in for a newest sample without power.
        XCTAssertNil(SystemPowerReadout.current(from: [sample(4, watts: 18), sample(2, watts: nil)], now: now))
    }
}

final class SMCOptionalKeyPacerTests: XCTestCase {
    func testMissingKeyIsRetriedAfterTheInterval() {
        let start = Date(timeIntervalSince1970: 0)
        var pacer = SMCOptionalKeyPacer(retryInterval: 30)
        XCTAssertTrue(pacer.shouldRead(at: start))
        pacer.record(found: false, at: start)
        XCTAssertFalse(pacer.shouldRead(at: start.addingTimeInterval(29)))
        XCTAssertTrue(pacer.shouldRead(at: start.addingTimeInterval(30)))
        pacer.record(found: true, at: start.addingTimeInterval(30))
        XCTAssertTrue(pacer.shouldRead(at: start.addingTimeInterval(31)))
    }
}

final class TemperatureHeadingLayoutTests: XCTestCase {
    private let languages: [FanBarLanguage] = [.english, .chinese, .traditionalChinese, .japanese, .russian, .french]

    override func invokeTest() {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
            }
        }
        super.invokeTest()
    }

    @MainActor
    private func use(_ language: FanBarLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    @MainActor
    private func headingFits(_ watts: Int) -> (showsTitle: Bool, valueFits: Bool) {
        let readout = SystemPowerReadout(watts: Double(watts))
        let valueText = readout?.valueText ?? ""
        let heading = fanBarText("温度", "Temperature")
        let ranges = TemperatureChartRange.allCases.map(\.title)
        let shows = TemperatureHeadingLayout.showsPowerTitle(
            heading: heading, rangeTitles: ranges, powerTitle: SystemPowerReadout.title, valueText: valueText
        )
        let fits = TemperatureHeadingLayout.valueWidth(valueText)
            <= TemperatureHeadingLayout.room(heading: heading, rangeTitles: ranges)
        return (shows, fits)
    }

    @MainActor
    func testTheValueAlwaysFitsAndTheTitleUsuallyDoes() {
        for language in languages {
            use(language)
            XCTAssertTrue(headingFits(500).valueFits, "\(language) cannot fit \"500 W\"")
            XCTAssertTrue(headingFits(38).showsTitle, "\(language) drops the title for a two-digit reading")
        }
        for language in [FanBarLanguage.english, .chinese, .traditionalChinese, .japanese] {
            use(language)
            XCTAssertTrue(headingFits(128).showsTitle, "\(language) drops the title for a three-digit reading")
        }
    }

    @MainActor
    func testCopy() {
        use(.english)
        XCTAssertEqual(SystemPowerReadout.title, "Power")
        XCTAssertEqual(SystemPowerReadout(watts: 38)?.valueText, "38 W")
        XCTAssertEqual(SystemPowerReadout(watts: 38)?.accessibilityLabel, "Power 38 watts")
        use(.russian)
        XCTAssertEqual(SystemPowerReadout(watts: 128)?.valueText, "128 Вт")
        use(.chinese)
        XCTAssertEqual(SystemPowerReadout.title, "整机功耗")
        XCTAssertFalse(SystemPowerReadout.help.isEmpty)
    }
}
