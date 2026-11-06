import XCTest
@testable import FanBar

final class PanelThermalTests: XCTestCase {
    private var savedThreshold: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedThreshold = UserDefaults.standard.object(forKey: ThermalAlertSettings.thresholdKey)
        UserDefaults.standard.set(90.0, forKey: ThermalAlertSettings.thresholdKey)
    }

    override func tearDownWithError() throws {
        if let savedThreshold {
            UserDefaults.standard.set(savedThreshold, forKey: ThermalAlertSettings.thresholdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThermalAlertSettings.thresholdKey)
        }
        try super.tearDownWithError()
    }

    func testPanelHeatAssessmentMatchesMonitorAtCustomThreshold() {
        for threshold in [80.0, 105.0] {
            UserDefaults.standard.set(threshold, forKey: ThermalAlertSettings.thresholdKey)
            for temperature in [threshold - 2, threshold, threshold + 2] {
                for sensor in ThermalSensor.allCases {
                    let reading = ThermalReading(
                        sampledAt: Date(),
                        cpuCelsius: sensor == .cpu ? temperature : 50,
                        gpuCelsius: sensor == .gpu ? temperature : 50,
                        cpuHottestCelsius: 110
                    )
                    var monitor = ThermalAlertMonitor(thresholdCelsius: threshold)
                    XCTAssertEqual(
                        ThermalFocus.from(reading)?.level == .hot,
                        !monitor.alerts(for: reading).isEmpty,
                        "\(sensor), temperature \(temperature), threshold \(threshold)"
                    )
                }
            }
        }
    }

    func testEachPartHasItsOwnLimits() {
        XCTAssertEqual(ThermalLevel(celsius: nil, part: .cpu), .normal)
        XCTAssertEqual(ThermalLevel(celsius: 84.9, part: .cpu), .normal)
        XCTAssertEqual(ThermalLevel(celsius: 85, part: .cpu), .warm)
        XCTAssertEqual(ThermalLevel(celsius: 95, part: .gpu), .hot)

        XCTAssertEqual(ThermalLevel(celsius: 64.9, part: .ssd), .normal)
        XCTAssertEqual(ThermalLevel(celsius: 65, part: .ssd), .warm)
        XCTAssertEqual(ThermalLevel(celsius: 75, part: .ssd), .hot)

        XCTAssertEqual(ThermalLevel(celsius: 39.9, part: .battery), .normal)
        XCTAssertEqual(ThermalLevel(celsius: 40, part: .battery), .warm)
        XCTAssertEqual(ThermalLevel(celsius: 45, part: .battery), .hot)
    }

    func testDisplayCPUPrefersHottestCoreAndFallsBackToAverage() {
        let withHottest = ThermalReading(sampledAt: Date(), cpuCelsius: 62, gpuCelsius: nil, cpuHottestCelsius: 74)
        XCTAssertEqual(withHottest.cpuDisplayCelsius, 74)
        // Control input stays the average.
        XCTAssertEqual(withHottest.cpuCelsius, 62)

        let legacy = ThermalReading(sampledAt: Date(), cpuCelsius: 62, gpuCelsius: nil)
        XCTAssertEqual(legacy.cpuDisplayCelsius, 62)
    }

    func testHistorySavedBeforeHottestCoreStillDecodes() throws {
        let json = #"[{"sampledAt":0,"cpuCelsius":55,"gpuCelsius":50}]"#
        let decoded = try JSONDecoder().decode([ThermalReading].self, from: Data(json.utf8))
        XCTAssertNil(decoded.first?.cpuHottestCelsius)
        XCTAssertEqual(decoded.first?.cpuDisplayCelsius, 55)
    }

    func testFocusUsesAverageCPUForHeatAssessment() {
        let reading = ThermalReading(
            sampledAt: Date(),
            cpuCelsius: 60,
            gpuCelsius: 66,
            ssdCelsius: 44,
            batteryCelsius: 33,
            cpuHottestCelsius: 71
        )
        let focus = ThermalFocus.from(reading)
        XCTAssertEqual(focus?.part, .gpu)
        XCTAssertEqual(focus?.celsius, 66)
        XCTAssertEqual(focus?.isAlert, false)
    }

    func testWarmBatteryLeadsEvenWhenChipsAreHotter() {
        let reading = ThermalReading(
            sampledAt: Date(),
            cpuCelsius: 67,
            gpuCelsius: 60,
            ssdCelsius: 44,
            batteryCelsius: 43
        )
        let focus = ThermalFocus.from(reading)
        XCTAssertEqual(focus?.part, .battery)
        XCTAssertEqual(focus?.level, .warm)
    }

    func testHotterLevelWinsBetweenTwoAlerts() {
        let reading = ThermalReading(
            sampledAt: Date(),
            cpuCelsius: 88,
            gpuCelsius: nil,
            ssdCelsius: 76,
            cpuHottestCelsius: 88
        )
        // CPU average 88 °C is warm; SSD 76 °C is hot.
        let focus = ThermalFocus.from(reading)
        XCTAssertEqual(focus?.part, .ssd)
        XCTAssertEqual(focus?.level, .hot)
    }

    func testFocusIsNilWithoutSensors() {
        XCTAssertNil(ThermalFocus.from(nil))
        XCTAssertNil(ThermalFocus.from(ThermalReading(sampledAt: Date(), cpuCelsius: nil, gpuCelsius: nil)))
    }
}
