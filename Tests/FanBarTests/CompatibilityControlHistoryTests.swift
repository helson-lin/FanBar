import FanBarShared
import Foundation
import XCTest
@testable import FanBar

@MainActor
final class CompatibilityControlHistoryTests: XCTestCase {
    func testResultsSurviveControllerRecreationAndKeepTheirDate() throws {
        let suite = "fanbar-test-control-history-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompatibilityControlHistoryStore(defaults: defaults)
        func controller() -> FanController {
            FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled,
                makeReadingSource: { FakeFanReadingSource() }, compatibilityHistoryStore: store)
        }
        let first = controller()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(CompatibilityControlHistory(device: first.compatibilityDevice, manual: .requestSucceeded,
            curve: .requestSucceeded, recordedAt: date))
        let reopened = controller()
        XCTAssertEqual(reopened.manualControlEvidence, .requestSucceeded)
        XCTAssertEqual(reopened.curveControlEvidence, .requestSucceeded)
        XCTAssertEqual(reopened.controlEvidenceRecordedAt, date)
        reopened.detectCompatibility()
        XCTAssertEqual(reopened.manualControlEvidence, .requestSucceeded)
        XCTAssertEqual(reopened.controlEvidenceRecordedAt, date)
        let newDevice = CompatibilityDevice(modelIdentifier: first.compatibilityDevice.modelIdentifier,
            processor: first.compatibilityDevice.processor, macOSVersion: "99.0.0", appVersion: "next", helperVersion: "next")
        XCTAssertNil(store.load(for: newDevice))
    }

    func testPriorReportsRecoverAutomaticEvidenceButNotUserCheckboxes() throws {
        let device = CompatibilityDevice.current(helperVersion: "test")
        let reading = ThermalReading(sampledAt: Date(), cpuCelsius: 50, gpuCelsius: 45)
        let snapshot = CompatibilitySnapshot.make(device: device,
            observation: CompatibilityObservation(sampledAt: Date(), thermal: reading, fanCount: 1, connectionFailed: false),
            helperState: .enabled, manualEvidence: .requestSucceeded, curveEvidence: .unverified)
        var report = CompatibilityReport(snapshot: snapshot)
        let index = try XCTUnwrap(report.capabilities.firstIndex { $0.capability == .smartCooling })
        report.capabilities[index].userConfirmedWorking = true
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = CompatibilitySavedReceipt(reportID: report.reportID.uuidString,
            serviceURL: try XCTUnwrap(URL(string: "https://report.getfanbar.com")), deletionToken: "test",
            reportData: try report.jsonData(), publishReport: false,
            policyVersion: CompatibilityServicePolicy.supportedVersion, createdAt: date)
        let saved = try XCTUnwrap(CompatibilityControlHistoryStore.recover(from: [receipt], for: device))
        XCTAssertEqual(saved.manual, .requestSucceeded)
        XCTAssertEqual(saved.curve, .unverified)
        XCTAssertEqual(saved.recordedAt, date)
    }

    func testReceiptRecoveryIsAttemptedOncePerDevice() throws {
        let suite = "fanbar-test-control-history-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompatibilityControlHistoryStore(defaults: defaults)
        let device = CompatibilityDevice.current(helperVersion: "test")
        XCTAssertTrue(store.needsRecovery(for: device))
        store.markRecoveryAttempted(for: device)
        XCTAssertFalse(store.needsRecovery(for: device))
        XCTAssertTrue(store.needsRecovery(for: .current(helperVersion: "next")))
    }

    func testLaunchRecoversFromReceiptsOnlyOncePerDevice() throws {
        let suite = "fanbar-test-control-history-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompatibilityControlHistoryStore(defaults: defaults)
        let device = CompatibilityDevice.current(helperVersion: "test")
        let snapshot = CompatibilitySnapshot.make(device: device,
            observation: CompatibilityObservation(sampledAt: Date(), thermal: ThermalReading(sampledAt: Date(), cpuCelsius: 50,
                gpuCelsius: 45), fanCount: 1, connectionFailed: false),
            helperState: .enabled, manualEvidence: .requestSucceeded, curveEvidence: .unverified)
        let report = CompatibilityReport(snapshot: snapshot)
        let receipt = CompatibilitySavedReceipt(reportID: report.reportID.uuidString,
            serviceURL: try XCTUnwrap(URL(string: "https://report.getfanbar.com")), deletionToken: "test",
            reportData: try report.jsonData(), publishReport: false,
            policyVersion: CompatibilityServicePolicy.supportedVersion, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        var keychainReads = 0
        func launch(recovers: Bool = true,
                    receipts: [CompatibilitySavedReceipt] = [receipt]) -> CompatibilityControlHistory? {
            FanController.loadControlHistory(for: device, store: store, recoversFromReceipts: recovers) {
                keychainReads += 1
                return receipts
            }
        }

        XCTAssertNil(launch(recovers: false), "Test controllers never read the Keychain")
        XCTAssertEqual(keychainReads, 0)
        XCTAssertEqual(launch()?.manual, .requestSucceeded)
        XCTAssertEqual(keychainReads, 1)
        XCTAssertEqual(store.load(for: device)?.manual, .requestSucceeded, "Recovered evidence is saved")
        XCTAssertEqual(launch()?.manual, .requestSucceeded)
        XCTAssertEqual(keychainReads, 1, "Saved evidence is used without reading receipts again")

        defaults.removeObject(forKey: "fanbar.compatibility.controlHistory.v1")
        XCTAssertNil(launch())
        XCTAssertEqual(keychainReads, 1, "Recovery is attempted once per device, even when it found evidence")

        let fresh = CompatibilityControlHistoryStore(defaults: defaults)
        let next = CompatibilityDevice.current(helperVersion: "next")
        XCTAssertNil(FanController.loadControlHistory(for: next, store: fresh, recoversFromReceipts: true) {
            keychainReads += 1
            throw CompatibilityServiceError.credentialStorage
        })
        XCTAssertEqual(keychainReads, 2, "A new version tries once; a Keychain failure is not fatal")
        XCTAssertFalse(fresh.needsRecovery(for: next))
    }

    func testControlTestMessagePrioritizesRestorationThenErrorsThenCancellation() {
        let finished = FanController.compatibilityControlMessage(for: CompatibilityControlTestResult())
        XCTAssertEqual(finished, fanBarText("控制测试结束，已恢复系统自动控制。请查看各项结果。",
                                          "Control test finished; system automatic control restored. Review the results below."))

        var cancelled = CompatibilityControlTestResult()
        cancelled.cancelled = true
        XCTAssertEqual(FanController.compatibilityControlMessage(for: cancelled),
                       fanBarText("控制测试已取消，已恢复系统自动控制。", "Control test cancelled. System automatic control restored."))

        var failed = cancelled
        failed.controlError = "timeout"
        let failure = FanController.compatibilityControlMessage(for: failed)
        XCTAssertTrue(failure.contains("timeout"))
        XCTAssertNotEqual(failure, FanController.compatibilityControlMessage(for: cancelled))

        var unrestored = failed
        unrestored.restored = false
        unrestored.restoreError = "mode readback"
        let restoreFailure = FanController.compatibilityControlMessage(for: unrestored)
        XCTAssertTrue(restoreFailure.contains("mode readback"), "A failed restoration is never hidden by other outcomes")
    }

    func testOneUnreadableReceiptDoesNotHideTheOthers() throws {
        let receipt = CompatibilitySavedReceipt(reportID: UUID().uuidString.lowercased(),
            serviceURL: try XCTUnwrap(URL(string: "https://report.getfanbar.com")), deletionToken: "test",
            reportData: Data("{}".utf8), publishReport: false, policyVersion: "2026-10-13", createdAt: Date())
        let decoded = CompatibilityReceiptStore.decode([Data("corrupted".utf8), try JSONEncoder().encode(receipt)])
        XCTAssertEqual(decoded, [receipt])
    }

    func testInvalidHistoryIsIgnored() throws {
        let suite = "fanbar-test-control-history-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "fanbar.compatibility.controlHistory.v1")
        XCTAssertNil(CompatibilityControlHistoryStore(defaults: defaults).load(for: .current(helperVersion: "test")))
    }
}
