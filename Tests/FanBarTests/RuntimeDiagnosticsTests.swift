import FanBarShared
import Foundation
import XCTest

final class RuntimeDiagnosticsTests: XCTestCase {
    func testJournalPersistsBoundedEventsAndRetainsStartupMarkers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("runtime.json")
        let journal = RuntimeDiagnostics(url: url)
        journal.beginLaunch()
        for value in 0..<270 {
            journal.record(.control, .curve, .succeeded, value: Double(value) / 270)
        }
        let reopened = RuntimeDiagnostics(url: url)
        XCTAssertLessThanOrEqual(reopened.snapshot().count, 256)
        XCTAssertTrue(reopened.snapshot().contains { $0.action == .startup })
        reopened.beginLaunch()
        XCTAssertTrue(reopened.snapshot().contains { $0.action == .previousExitUnknown })
        XCTAssertLessThan(try Data(contentsOf: url).count, 131072)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testServiceStatusSurvivesARunOfFailedWrites() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("runtime.json")
        let journal = RuntimeDiagnostics(url: url)
        journal.record(.service, .status, .enabled)
        // Issue 114: 110 failed curve writes pushed the one status event out of the ring.
        for _ in 0..<300 {
            journal.record(.control, .curve, .failed, code: 1)
        }
        let status = RuntimeDiagnostics(url: url).snapshot().last { $0.component == .service && $0.action == .status }
        XCTAssertEqual(status?.outcome, .enabled)
    }

    func testNormalShutdownIsNotReportedAsUnknownExitAndRequestIDsSurvive() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("events.json")
        let journal = RuntimeDiagnostics(url: url)
        journal.beginLaunch()
        let id = UUID().uuidString.lowercased()
        DiagnosticRequestContext.$id.withValue(id) { journal.record(.control, .fixedRPM, .started, value: 2000) }
        journal.record(.app, .shutdown, .succeeded)
        let reopened = RuntimeDiagnostics(url: url)
        reopened.beginLaunch()
        XCTAssertFalse(reopened.snapshot().contains { $0.action == .previousExitUnknown })
        XCTAssertEqual(reopened.snapshot().first { $0.action == .fixedRPM }?.requestID, id)
    }

    func testLegacyCrashSummaryAlsoDropsFreeFormText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = ["Process: FanBar [123]", "Path: /Users/private/FanBar", "Exception Type: EXC_CRASH (SIGABRT)",
            "Termination Reason: Namespace DYLD, Code 1", ""].joined(separator: "\n")
        try Data(fixture.utf8)
            .write(to: root.appendingPathComponent("FanBar_test.crash"))
        let summary = try XCTUnwrap(DiagnosticCrashReader.summaries(directory: root).first)
        XCTAssertEqual(summary.exception, "EXC_CRASH")
        XCTAssertEqual(summary.terminationNamespace, "DYLD")
        XCTAssertEqual(summary.terminationCode, 1)
    }

    func testCrashSummaryRemovesIdentityPathsAndUntrustedImageNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let body: [String: Any] = ["procName": "FanBar", "procPath": "/Users/private-person/FanBar",
            "exception": ["type": "EXC_BAD_ACCESS", "signal": "SIGSEGV", "message": "private-person"],
            "termination": ["namespace": "CODESIGNING", "code": 2], "faultingThread": 0,
            "threads": [["frames": [["imageIndex": 0, "imageOffset": 123], ["imageIndex": 1, "imageOffset": 456]]]],
            "usedImages": [["name": "FanBar", "path": "/Users/private-person/FanBar"], ["name": "private-person.dylib"]]]
        var data = Data("{\"incident_id\":\"private-uuid\"}\n".utf8)
        data.append(try JSONSerialization.data(withJSONObject: body))
        try data.write(to: root.appendingPathComponent("FanBar-test.ips"))
        let summaries = DiagnosticCrashReader.summaries(directory: root)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.frames.map(\.image), ["FanBar", "other"])
        let text = try XCTUnwrap(String(bytes: JSONEncoder().encode(summaries), encoding: .utf8))
        XCTAssertFalse(text.contains("private-person"))
        XCTAssertFalse(text.contains("private-uuid"))
        XCTAssertFalse(text.contains("/Users/"))
    }

    private func helperEvent(_ action: String, _ outcome: String, secondsAgo: Double,
                             component: String = "helper") throws -> RuntimeDiagnosticEvent {
        let object: [String: Any] = [
            "timestamp": Date().addingTimeInterval(-secondsAgo).timeIntervalSinceReferenceDate,
            "sessionID": "00000000-0000-0000-0000-000000000001",
            "component": component, "action": action, "outcome": outcome,
        ]
        return try JSONDecoder().decode(RuntimeDiagnosticEvent.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testHelperSelectionKeepsOldFailuresDespiteABurstOfRoutineWrites() throws {
        let failure = try helperEvent("restoreAutomatic", "failed", secondsAgo: 6 * 3600)
        let startup = try helperEvent("startup", "succeeded", secondsAgo: 20 * 3600)
        let routine = try (0..<200).map { try helperEvent("curve", "succeeded", secondsAgo: Double(200 - $0)) }
        let selected = RuntimeDiagnostics.selectHelperEvents(recent: routine, important: [failure, startup])
        XCTAssertEqual(selected.count, 64)
        XCTAssertTrue(selected.contains { $0.action == .restoreAutomatic && $0.outcome == .failed })
        XCTAssertTrue(selected.contains { $0.action == .startup })
        XCTAssertEqual(selected.map(\.timestamp), selected.map(\.timestamp).sorted())
        XCTAssertEqual(selected.last?.timestamp, routine.last?.timestamp, "The newest routine events fill the rest")
    }

    func testHelperSelectionDeduplicatesOverlappingWindowsAndBoundsImportantEvents() throws {
        let failure = try helperEvent("fanRead", "failed", secondsAgo: 30)
        let selected = RuntimeDiagnostics.selectHelperEvents(recent: [failure], important: [failure])
        XCTAssertEqual(selected.count, 1)
        let failures = try (0..<100).map { try helperEvent("fanRead", "failed", secondsAgo: Double(100 - $0)) }
        // 32 slots are reserved for failures and lifecycle events; the rest take the newest of anything.
        let bounded = RuntimeDiagnostics.selectHelperEvents(recent: [], important: failures)
        XCTAssertEqual(bounded.map(\.timestamp), failures.suffix(64).map(\.timestamp))
        let appEvent = try helperEvent("curve", "failed", secondsAgo: 1, component: "app")
        XCTAssertTrue(RuntimeDiagnostics.selectHelperEvents(recent: [appEvent], important: []).isEmpty)
    }

    func testHelperLogParsingKeepsOnlyStructuredHelperEvents() throws {
        let event = try helperEvent("authorize", "rejected", secondsAgo: 5)
        let message = try XCTUnwrap(String(data: JSONEncoder().encode(event), encoding: .utf8))
        let line = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: ["eventMessage": message]), encoding: .utf8))
        let other = #"{"eventMessage":"Rejected XPC client pid 42"}"#
        let parsed = RuntimeDiagnostics.parseHelperLog([line, other, "not json", ""].joined(separator: "\n"))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.action, .authorize)
        XCTAssertEqual(parsed.first?.outcome, .rejected)
    }
}
