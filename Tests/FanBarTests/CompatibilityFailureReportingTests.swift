import FanBarShared
import Foundation
import XCTest
@testable import FanBar

@MainActor
private final class MemoryReceipts: CompatibilityReceiptStoring {
    var items: [CompatibilitySavedReceipt] = []
    func save(_ receipt: CompatibilitySavedReceipt) throws {
        items.removeAll { $0.reportID == receipt.reportID }
        items.append(receipt)
    }

    func receipts() throws -> [CompatibilitySavedReceipt] {
        items
    }

    func remove(reportID: String) throws {
        items.removeAll { $0.reportID == reportID }
    }
}

@MainActor
private final class StubReports: CompatibilityReportServing {
    let servicePolicy: CompatibilityServicePolicy
    var failSubmission = false
    init(policy: CompatibilityServicePolicy) {
        servicePolicy = policy
    }

    func policy() async throws -> CompatibilityServicePolicy {
        servicePolicy
    }

    func submit(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse {
        if failSubmission { throw CompatibilityServiceError.network }
        return CompatibilitySubmissionResponse(
            reportID: receipt.reportID, status: "pending", receivedAt: "2026-10-21T00:00:00Z",
            expiresAt: "2027-01-19T00:00:00Z", publishReport: receipt.publishReport, policyVersion: receipt.policyVersion
        )
    }

    func withdraw(_ receipt: CompatibilitySavedReceipt) async throws {}
}

@MainActor
private final class StubDiagnostics: DiagnosticUploadServing {
    let configuration: CompatibilityServiceConfiguration
    var failNextSubmission = false
    var submissions: [CompatibilitySavedReceipt] = []
    init(configuration: CompatibilityServiceConfiguration) {
        self.configuration = configuration
    }

    func diagnosticPolicy() async throws -> DiagnosticPolicy {
        DiagnosticPolicy(version: DiagnosticPolicy.supportedVersion,
                         serviceOrigin: "https://report.getfanbar.com", retentionDays: 90, maximumBytes: 262_144)
    }

    func submitDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws -> CompatibilitySubmissionResponse {
        submissions.append(receipt)
        if failNextSubmission {
            failNextSubmission = false
            throw CompatibilityServiceError.network
        }
        return CompatibilitySubmissionResponse(
            reportID: receipt.reportID, status: "received", receivedAt: "2026-10-21T00:00:00Z",
            expiresAt: "2027-01-19T00:00:00Z", publishReport: false, policyVersion: DiagnosticPolicy.supportedVersion
        )
    }

    func withdrawDiagnostic(_ receipt: CompatibilitySavedReceipt) async throws {}
}

@MainActor
final class CompatibilityFailureReportingTests: XCTestCase {
    private let device = CompatibilityDevice(
        modelIdentifier: "Mac15,7", processor: "Apple M3 Pro", macOSVersion: "26.6.2", appVersion: "0.7.1", helperVersion: "33"
    )

    private func snapshot(
        helperState: FanController.HelperState = .enabled,
        manual: CompatibilityControlEvidence = .requestFailed,
        failure: CompatibilityControlFailure? = CompatibilityControlFailure(code: .unlockTimeout, fanIndex: 0)
    ) -> CompatibilitySnapshot {
        CompatibilitySnapshot.make(
            device: device,
            observation: CompatibilityObservation(
                sampledAt: Date(), thermal: ThermalReading(sampledAt: Date(), cpuCelsius: 52, gpuCelsius: 48, hasBuiltInBattery: true),
                fanCount: 2, connectionFailed: false
            ),
            helperState: helperState, manualEvidence: manual, curveEvidence: .unverified,
            manualFailure: failure, curveFailure: CompatibilityControlFailure(code: .helperTimeout)
        )
    }

    // MARK: Helper replies

    func testStructuredHelperReplyIsDecodedAndPlainTextFallsBack() {
        let structured = HelperClientError(message: HelperControlFailure(
            code: .smcOperationFailed, smcKey: "F0Md", resultCode: -536_870_212, message: "SMC operation F0Md failed"
        ).encodedReply())
        XCTAssertEqual(structured.message, "SMC operation F0Md failed")
        XCTAssertEqual(structured.diagnosticCode, -536_870_212)
        XCTAssertEqual(CompatibilityControlFailure(error: structured),
                       CompatibilityControlFailure(code: .smcOperationFailed, smcKey: "F0Md", resultCode: -536_870_212))

        // An older helper's reply: only the bounded trailing number survives.
        let legacy = HelperClientError(message: "SMC operation F0Md failed (-9)")
        XCTAssertNil(legacy.failure)
        XCTAssertEqual(CompatibilityControlFailure(error: legacy),
                       CompatibilityControlFailure(code: .helperErrorUnclassified, resultCode: -9))
    }

    func testDecodedFailuresAreBoundedAgain() {
        let reply = HelperControlFailure.marker
            + #"{"code":"UNLOCK_TIMEOUT","smcKey":"/Users/me","fanIndex":42,"durationMS":-5,"message":"x"}"#
        let failure = HelperControlFailure.decode(reply: reply)
        XCTAssertEqual(failure?.code, .unlockTimeout)
        XCTAssertNil(failure?.smcKey)
        XCTAssertNil(failure?.fanIndex)
        XCTAssertEqual(failure?.durationMS, 0)
        XCTAssertNil(HelperControlFailure.decode(reply: HelperControlFailure.marker + "{broken"))
    }

    func testConnectionAndTimeoutFailuresAreDistinguished() {
        let timeout = HelperClientError(message: "did not respond", isConnectionFailure: true, isTimeout: true)
        XCTAssertEqual(CompatibilityControlFailure(error: timeout).code, .helperTimeout)
        let refused = HelperClientError(message: "refused", isConnectionFailure: true)
        XCTAssertEqual(CompatibilityControlFailure(error: refused).code, .helperConnectionFailed)
        XCTAssertEqual(CompatibilityControlFailure(error: CocoaError(.fileNoSuchFile)).code, .helperErrorUnclassified)
    }

    // MARK: Report

    func testFailureIsAttachedOnlyToFailedControlRows() {
        let failed = snapshot().results
        XCTAssertEqual(failed.first { $0.capability == .manualControl }?.failure?.code, .unlockTimeout)
        // Smart cooling is unverified here, so its stale failure must not leak into the report.
        XCTAssertNil(failed.first { $0.capability == .smartCooling }?.failure)

        let unauthorized = snapshot(helperState: .requiresApproval).results
        XCTAssertNil(unauthorized.first { $0.capability == .manualControl }?.failure)
        let succeeded = snapshot(manual: .requestSucceeded).results
        XCTAssertNil(succeeded.first { $0.capability == .manualControl }?.failure)
    }

    func testReportEncodesOnlyTheFieldsThatAreSet() throws {
        let data = try CompatibilityReport(snapshot: snapshot()).jsonData()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["capabilities"] as? [[String: Any]])
        let manual = try XCTUnwrap(rows.first { $0["capability"] as? String == "manualControl" })
        XCTAssertEqual(manual["failure"] as? [String: AnyHashable], ["code": "UNLOCK_TIMEOUT", "fanIndex": 0])
        XCTAssertEqual(rows.filter { $0["failure"] != nil }.count, 1)
    }

    func testEmptyReadbackIsOmittedSoTheReportStaysValid() throws {
        let failure = CompatibilityControlFailure.readbackNotManual([])
        XCTAssertEqual(failure.code, .readbackNotManual)
        XCTAssertNil(failure.readbackManual)
        let data = try JSONEncoder().encode(failure)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["readbackManual"])

        let fans = (0..<10).map {
            FanReading(index: $0, minimumRPM: 1200, currentRPM: 1850, maximumRPM: 6000, isManual: $0.isMultiple(of: 2))
        }
        XCTAssertEqual(CompatibilityControlFailure.readbackNotManual(fans.reversed()).readbackManual,
                       [true, false, true, false, true, false, true, false])
    }

    func testFailuresSurviveTheLocalHistory() throws {
        let suite = "fanbar.tests.failureHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompatibilityControlHistoryStore(defaults: defaults)
        let failure = CompatibilityControlFailure(code: .readbackNotManual, readbackManual: [true, false], restoredAutomatic: true)
        store.save(CompatibilityControlHistory(device: device, manual: .requestFailed, curve: .unverified,
                                               manualFailure: failure, recordedAt: Date()))
        XCTAssertEqual(store.load(for: device)?.manualFailure, failure)
    }

    // MARK: Attached diagnostic

    private final class Counter { var value = 0 }

    private struct UploadFixture {
        let upload: CompatibilityUploadCoordinator
        let diagnostics: StubDiagnostics
        let collections: () -> Int
    }

    private func makeUploadAsync(
        failsReport: Bool = false
    ) async throws -> UploadFixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let policy = try JSONDecoder().decode(CompatibilityServicePolicy.self,
            from: Data(contentsOf: root.appendingPathComponent("contracts/compatibility-policy.example.json")))
        let configuration = try XCTUnwrap(CompatibilityServiceConfiguration(url: try XCTUnwrap(URL(string: "https://report.getfanbar.com"))))
        let reports = StubReports(policy: policy)
        reports.failSubmission = failsReport
        let diagnostics = StubDiagnostics(configuration: configuration)
        let collections = Counter()
        let device = device
        let upload = CompatibilityUploadCoordinator(
            data: try CompatibilityReport(snapshot: snapshot()).jsonData(), configuration: configuration,
            api: reports, store: MemoryReceipts(),
            collectDiagnostic: {
                collections.value += 1
                return DiagnosticReport(diagnosticID: UUID().uuidString.lowercased(), capturedAt: "2026-10-21T00:00:00Z",
                                        device: device, helperState: "enabled", probes: [])
            },
            makeDiagnosticUpload: { collect in
                DiagnosticUploadCoordinator(collect: collect, makeService: { _ in diagnostics }, store: MemoryReceipts())
            }
        )
        await upload.loadPolicy()
        return UploadFixture(upload: upload, diagnostics: diagnostics, collections: { collections.value })
    }

    func testDiagnosticIsSentUnderTheReportIDOnlyWhenChosen() async throws {
        let skippedFixture = try await makeUploadAsync()
        let skipped = skippedFixture.upload, skippedDiagnostics = skippedFixture.diagnostics
        await skipped.submit(consent: true, publishReport: false)
        XCTAssertNotNil(skipped.receipt?.response)
        XCTAssertTrue(skippedDiagnostics.submissions.isEmpty)
        XCTAssertNil(skipped.diagnosticUpload)

        let fixture = try await makeUploadAsync()
        let upload = fixture.upload, diagnostics = fixture.diagnostics
        upload.attachDiagnostic = true
        await upload.submit(consent: true, publishReport: false)
        let reportID = try XCTUnwrap(upload.receipt?.response?.reportID)
        XCTAssertEqual(diagnostics.submissions.map(\.reportID), [reportID])
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(diagnostics.submissions.first).reportData) as? [String: Any]
        XCTAssertEqual(sent?["diagnosticID"] as? String, reportID)
        XCTAssertNotNil(upload.diagnosticUpload?.receipt?.response)
    }

    func testNoDiagnosticWhenTheReportItselfFails() async throws {
        let fixture = try await makeUploadAsync(failsReport: true)
        let upload = fixture.upload, diagnostics = fixture.diagnostics, collections = fixture.collections
        upload.attachDiagnostic = true
        await upload.submit(consent: true, publishReport: false)
        XCTAssertNil(upload.receipt?.response)
        XCTAssertTrue(diagnostics.submissions.isEmpty)
        XCTAssertEqual(collections(), 0)
    }

    func testRetryResendsTheSameDiagnosticWithoutCollectingAgain() async throws {
        let fixture = try await makeUploadAsync()
        let upload = fixture.upload, diagnostics = fixture.diagnostics, collections = fixture.collections
        diagnostics.failNextSubmission = true
        upload.attachDiagnostic = true
        await upload.submit(consent: true, publishReport: false)
        XCTAssertNil(upload.diagnosticUpload?.receipt?.response)
        XCTAssertNotNil(upload.diagnosticUpload?.error)

        await upload.submitAttachedDiagnostic()
        XCTAssertNotNil(upload.diagnosticUpload?.receipt?.response)
        XCTAssertEqual(collections(), 1)
        XCTAssertEqual(Set(diagnostics.submissions.map(\.reportID)).count, 1)
    }
}
