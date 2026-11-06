import FanBarShared
import XCTest
@testable import FanBar

final class FanCurveSensorDisplayTests: XCTestCase {
    private var savedLanguage: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    override func tearDownWithError() throws {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
        }
        try super.tearDownWithError()
    }

    func testDescriptionNamesTheSelectedTemperatureSource() {
        let reading = ThermalReading(
            sampledAt: Date(), cpuCelsius: 55, gpuCelsius: 70, ssdCelsius: 40, batteryCelsius: 33.6,
            cpuHottestCelsius: 99
        )
        XCTAssertEqual(FanCurveSensor.battery.temperature(in: reading), 33.6)
        XCTAssertEqual(FanCurveSensor.battery.controlDescription(for: reading), "Following Battery at 34°")
        XCTAssertEqual(FanCurveSensor.cpu.controlDescription(for: reading), "Following CPU average at 55°")
        XCTAssertEqual(FanCurveSensor.gpu.controlDescription(for: reading), "Following GPU at 70°")
        XCTAssertEqual(FanCurveSensor.ssd.controlDescription(for: reading), "Following SSD at 40°")
        XCTAssertEqual(FanCurveSensor.maxChip.controlDescription(for: reading), "Following Higher of CPU/GPU at 70°")
    }

    func testDescriptionExplainsGPUFallbackAndDoesNotInventSSDReadings() {
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 55, gpuCelsius: nil)
        XCTAssertEqual(FanCurveSensor.gpu.temperature(in: reading), 55)
        XCTAssertEqual(FanCurveSensor.gpu.controlDescription(for: reading), "Following CPU (GPU unavailable) at 55°")
        XCTAssertNil(FanCurveSensor.ssd.temperature(in: reading))
        XCTAssertEqual(FanCurveSensor.ssd.controlDescription(for: reading), "Following SSD at —")
        XCTAssertNil(FanCurveSensor.battery.temperature(in: reading))
        XCTAssertEqual(FanCurveSensor.battery.controlDescription(for: reading), "Following Battery at —")
    }

    @MainActor
    func testPanelModeLineNamesItsActualTemperatureSource() {
        let reading = ThermalReading(
            sampledAt: Date(), cpuCelsius: 55, gpuCelsius: 70, ssdCelsius: 40, cpuHottestCelsius: 99
        )
        let expected: [(FanCurveSensor, String)] = [
            (.cpu, "Following CPU average at 55°"),
            (.gpu, "Following GPU at 70°"),
            (.ssd, "Following SSD at 40°"),
            (.maxChip, "Following Higher of CPU/GPU at 70°")
        ]
        for (sensor, text) in expected {
            XCTAssertEqual(
                FanMenu.modeDescription(for: .temperatureCurve, sensor: sensor, reading: reading, fanCount: 2), text
            )
        }
    }

    @MainActor
    func testPanelModeLineHandlesMissingSensorsAndOtherModes() {
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 55, gpuCelsius: nil)
        XCTAssertEqual(
            FanMenu.modeDescription(for: .temperatureCurve, sensor: .gpu, reading: reading, fanCount: 1),
            "Following CPU (GPU unavailable) at 55°"
        )
        XCTAssertEqual(
            FanMenu.modeDescription(for: .temperatureCurve, sensor: .ssd, reading: reading, fanCount: 1),
            "Following SSD at —"
        )
        XCTAssertEqual(
            FanMenu.modeDescription(for: .temperatureCurve, sensor: .cpu, reading: nil, fanCount: 1),
            "Following CPU average at —"
        )
        XCTAssertEqual(
            FanMenu.modeDescription(for: .automatic, sensor: .ssd, reading: reading, fanCount: 1),
            "Controlled by macOS"
        )
        XCTAssertEqual(
            FanMenu.modeDescription(for: .fixed(3500), sensor: .ssd, reading: reading, fanCount: 2),
            "Fans hold the same speed"
        )
    }

    func testBatteryIsOfferedOnlyWhenThisMacHasOne() {
        // `installed` mirrors ThermalReading.hasBuiltInBattery, where nil means unknown.
        // swiftlint:disable:next discouraged_optional_boolean
        func reading(battery: Double?, installed: Bool?) -> ThermalReading {
            ThermalReading(sampledAt: Date(), cpuCelsius: 55, gpuCelsius: 60, ssdCelsius: 40,
                           batteryCelsius: battery, hasBuiltInBattery: installed)
        }
        let withoutBattery: [FanCurveSensor] = [.maxChip, .cpu, .gpu, .ssd]
        // Desktop Macs have no battery service at all, so the flag is unknown rather than false.
        XCTAssertEqual(FanCurveSensor.selectable(reading: reading(battery: nil, installed: nil), current: .maxChip),
                       withoutBattery)
        XCTAssertEqual(FanCurveSensor.selectable(reading: reading(battery: nil, installed: false), current: .cpu),
                       withoutBattery)
        XCTAssertEqual(FanCurveSensor.selectable(reading: nil, current: .maxChip), withoutBattery)
        XCTAssertEqual(FanCurveSensor.selectable(reading: reading(battery: nil, installed: true), current: .maxChip),
                       FanCurveSensor.allCases)
        XCTAssertEqual(FanCurveSensor.selectable(reading: reading(battery: 31, installed: nil), current: .maxChip),
                       FanCurveSensor.allCases)
        // A profile that already follows the battery keeps it selectable.
        XCTAssertEqual(FanCurveSensor.selectable(reading: reading(battery: nil, installed: nil), current: .battery),
                       FanCurveSensor.allCases)
    }
}
