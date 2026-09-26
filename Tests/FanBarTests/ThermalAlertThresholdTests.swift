import XCTest
@testable import FanBar

final class ThermalAlertThresholdTests: XCTestCase {
    func testClampedThresholdStaysInsideSupportedRange() {
        XCTAssertEqual(ThermalAlertSettings.clampedThreshold(20), 60)
        XCTAssertEqual(ThermalAlertSettings.clampedThreshold(150), 105)
        XCTAssertEqual(ThermalAlertSettings.clampedThreshold(84.6), 85)
    }

    func testMonitorAlertsAtCustomThreshold() {
        var monitor = ThermalAlertMonitor(thresholdCelsius: 80)
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 82, gpuCelsius: 70)

        XCTAssertEqual(monitor.alerts(for: reading).map(\.sensor), [.cpu])
    }

    func testRaisingThresholdSilencesReadingBelowIt() {
        var monitor = ThermalAlertMonitor(thresholdCelsius: 80)
        monitor.thresholdCelsius = 90
        monitor.reset()
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 85, gpuCelsius: nil)

        XCTAssertTrue(monitor.alerts(for: reading).isEmpty)
    }
}
