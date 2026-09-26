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

final class ThermalAlertThresholdDragTests: XCTestCase {
    /// Lowering the threshold one degree at a time (a slider drag) must alert
    /// once, not at every step below the current temperature.
    func testLoweringThresholdStepwiseAlertsOnce() {
        var monitor = ThermalAlertMonitor(thresholdCelsius: 90)
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 85, gpuCelsius: nil)
        var alertCount = 0
        for threshold in stride(from: 90.0, through: 60.0, by: -1) {
            monitor.thresholdCelsius = threshold
            alertCount += monitor.alerts(for: reading).count
        }
        XCTAssertEqual(alertCount, 1)
    }
}
