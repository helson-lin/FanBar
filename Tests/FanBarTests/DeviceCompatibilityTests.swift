import Foundation
import XCTest
@testable import FanBar

@MainActor
final class DeviceCompatibilityTests: XCTestCase {
    private let device = CompatibilityDevice(
        modelIdentifier: "TestMac1,1", processor: "Test Processor", macOSVersion: "15.0.0",
        appVersion: "1.0", helperVersion: "10"
    )

    private func snapshot(
        fanCount: Int? = 2,
        thermal: ThermalReading? = ThermalReading(sampledAt: Date(), cpuCelsius: 52, gpuCelsius: nil),
        connectionFailed: Bool = false,
        helper: FanController.HelperState = .enabled,
        manual: CompatibilityControlEvidence = .unverified,
        curve: CompatibilityControlEvidence = .unverified,
        curveSensor: FanCurveSensor = .maxChip
    ) -> CompatibilitySnapshot {
        CompatibilitySnapshot.make(
            device: device,
            observation: CompatibilityObservation(
                sampledAt: Date(), thermal: thermal, fanCount: fanCount, connectionFailed: connectionFailed
            ),
            helperState: helper, manualEvidence: manual, curveEvidence: curve, curveSensor: curveSensor
        )
    }

    private func result(_ capability: CompatibilityCapability, in snapshot: CompatibilitySnapshot) throws -> CompatibilityResult {
        try XCTUnwrap(snapshot.results.first { $0.capability == capability })
    }

    func testServiceReadinessDoesNotVerifyControl() throws {
        let snapshot = snapshot()
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .available)
        XCTAssertEqual(try result(.gpuTemperature, in: snapshot).status, .notDetected)
        XCTAssertEqual(try result(.manualControl, in: snapshot).status, .unverified)
        XCTAssertEqual(try result(.smartCooling, in: snapshot).reasonCode, "CONTROL_NOT_ATTEMPTED")
    }

    func testPermissionsAndMissingServiceAreDistinct() throws {
        for helper in [FanController.HelperState.requiresApproval, .notRegistered] {
            let snapshot = snapshot(helper: helper, manual: .requestSucceeded)
            XCTAssertEqual(try result(.manualControl, in: snapshot).status, .requiresAuthorization)
        }
        let missing = snapshot(helper: .unavailable)
        XCTAssertEqual(try result(.manualControl, in: missing).reasonCode, "HELPER_MISSING")
    }

    func testZeroFansDoesNotProvePhysicalConfigurationOrControlSupport() throws {
        let snapshot = snapshot(fanCount: 0, manual: .requestSucceeded)
        XCTAssertEqual(try result(.fanReadings, in: snapshot).status, .notDetected)
        XCTAssertEqual(try result(.fanReadings, in: snapshot).reasonCode, "NO_FANS_REPORTED")
        XCTAssertEqual(try result(.manualControl, in: snapshot).status, .unverified)
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .available)
    }

    func testFanFailureDoesNotHideValidTemperatures() throws {
        let snapshot = snapshot(fanCount: nil)
        XCTAssertEqual(try result(.fanReadings, in: snapshot).status, .temporarilyUnavailable)
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .available)
        XCTAssertEqual(try result(.manualControl, in: snapshot).status, .unverified)
    }

    func testConnectionFailureDoesNotReuseOldEvidence() throws {
        let snapshot = snapshot(fanCount: nil, thermal: nil, connectionFailed: true, manual: .requestSucceeded)
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .temporarilyUnavailable)
        XCTAssertEqual(try result(.fanReadings, in: snapshot).reasonCode, "SMC_CONNECTION_FAILED")
        XCTAssertEqual(try result(.manualControl, in: snapshot).status, .unverified)
    }

    func testInvalidSensorValuesCannotVerifyReadings() throws {
        let thermal = ThermalReading(sampledAt: Date(), cpuCelsius: .nan, gpuCelsius: .infinity, ssdCelsius: -5)
        let snapshot = snapshot(thermal: thermal, curve: .requestSucceeded)
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .notDetected)
        XCTAssertEqual(try result(.gpuTemperature, in: snapshot).status, .notDetected)
        XCTAssertEqual(try result(.ssdTemperature, in: snapshot).status, .notDetected)
        XCTAssertEqual(try result(.smartCooling, in: snapshot).reasonCode, "NO_CURVE_SENSOR_EVIDENCE")
    }

    func testCurveChecksSelectedSourceInsteadOfAnyAvailableSensor() throws {
        for sensor in [FanCurveSensor.gpu, .ssd, .battery] {
            let snapshot = snapshot(curve: .requestSucceeded, curveSensor: sensor)
            XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .available)
            XCTAssertEqual(try result(.smartCooling, in: snapshot).reasonCode, "NO_CURVE_SENSOR_EVIDENCE")
        }
        let cpu = snapshot(curve: .requestSucceeded, curveSensor: .cpu)
        XCTAssertEqual(try result(.smartCooling, in: cpu).status, .requestSucceeded)
        let battery = snapshot(
            thermal: ThermalReading(sampledAt: Date(), cpuCelsius: 52, gpuCelsius: nil, batteryCelsius: 31),
            curve: .requestSucceeded, curveSensor: .battery
        )
        XCTAssertEqual(try result(.smartCooling, in: battery).status, .requestSucceeded)
    }

    func testAcceptedAndFailedRequestsRemainSeparateFromVerifiedReadings() throws {
        let snapshot = snapshot(manual: .requestSucceeded, curve: .requestFailed)
        XCTAssertEqual(try result(.manualControl, in: snapshot).status, .requestSucceeded)
        XCTAssertEqual(try result(.smartCooling, in: snapshot).status, .requestFailed)
    }

    func testReportUsesClosedSchemaAndFreshIdentifier() throws {
        let first = CompatibilityReport(snapshot: snapshot())
        let second = CompatibilityReport(snapshot: snapshot())
        XCTAssertNotEqual(first.reportID, second.reportID)
        let data = try first.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "reportID", "device", "fanCount", "capabilities", "selectedTemperatureSource"])
        let inventory = try XCTUnwrap(object["device"] as? [String: Any])
        XCTAssertEqual(Set(inventory.keys), ["modelIdentifier", "processor", "macOSVersion", "appVersion", "helperVersion"])
        let decoded = try JSONDecoder().decode(CompatibilityReport.self, from: data)
        XCTAssertEqual(decoded.device, device)
        XCTAssertEqual(decoded.capabilities.count, CompatibilityCapability.allCases.count)
        let capabilities = try XCTUnwrap(object["capabilities"] as? [[String: Any]])
        XCTAssertTrue(capabilities.allSatisfy { Set($0.keys) == ["capability", "status", "reasonCode"] })
    }

    func testCatalogRequiresExactVersionCombination() {
        let record = CompatibilityRecord(device: device, verifiedOn: "2026-10-13", source: "test", notes: "test")
        let catalog = CompatibilityCatalog(schemaVersion: 1, records: [record])
        XCTAssertEqual(catalog.matching(device), [record])
        let differentOS = CompatibilityDevice(
            modelIdentifier: device.modelIdentifier, processor: device.processor, macOSVersion: "15.0.1",
            appVersion: device.appVersion, helperVersion: device.helperVersion
        )
        XCTAssertTrue(catalog.matching(differentOS).isEmpty)
        XCTAssertEqual(CompatibilityCatalog.load().schemaVersion, 1)
    }

    func testBundledResourcesResolveWithoutGeneratedAccessor() {
        XCTAssertNotNil(FanBarResources.url(forResource: "compatibility", withExtension: "json"))
        XCTAssertNotNil(FanBarResources.url(forResource: "mac-model-names", withExtension: "json"))
    }

    func testRPMDecodingRejectsInvalidFloatsInsteadOfTrapping() throws {
        func floatBytes(_ value: Float) -> [UInt8] {
            withUnsafeBytes(of: value) { Array($0) }
        }
        XCTAssertEqual(try SMCClient.rpm(dataSize: 4, bytes: floatBytes(1_234.6)), 1_235)
        XCTAssertEqual(try SMCClient.rpm(dataSize: 2, bytes: [0x13, 0x88]), 1_250)
        for invalid in [Float.nan, .infinity, -1, 1e12] {
            XCTAssertThrowsError(try SMCClient.rpm(dataSize: 4, bytes: floatBytes(invalid)))
        }
        XCTAssertThrowsError(try SMCClient.rpm(dataSize: 1, bytes: [0]))
    }

    func testDiagnosticRetryReadsTemperatureDespiteFanFailure() throws {
        let source = FakeFanReadingSource()
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source }
        )
        source.error = SMCError.unsupportedKey("FNum", -1)
        controller.detectCompatibility()
        let snapshot = try XCTUnwrap(controller.compatibilitySnapshot)
        XCTAssertEqual(try result(.cpuTemperature, in: snapshot).status, .available)
        XCTAssertEqual(try result(.fanReadings, in: snapshot).status, .temporarilyUnavailable)
        XCTAssertEqual(controller.mode, .automatic)
        XCTAssertEqual(controller.manualControlEvidence, .unverified)
    }

    func testEmptyFanReadingsKeepTemperatureMonitoring() throws {
        let source = FakeFanReadingSource(readings: [])
        let controller = FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source }
        )
        controller.refresh()
        XCTAssertEqual(controller.temperatureHistory.last?.cpuCelsius, 52)
        XCTAssertEqual(try XCTUnwrap(controller.compatibilitySnapshot).fanCount, 0)
        controller.detectCompatibility()
        XCTAssertEqual(controller.mode, .automatic)
    }
}
