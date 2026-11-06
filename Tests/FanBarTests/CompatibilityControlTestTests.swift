import FanBarShared
import Testing
@testable import FanBar

@MainActor
private final class ControlTestClient: CompatibilityControlClient {
    enum Failure: Error { case write, restore }
    var manual = false
    var failsWrite = false
    var writeError: Error = Failure.write
    var failsRestore = false
    var ignoresWrite = false
    var delayedRestoreReads = 0
    var restoring = false
    var calls: [String] = []
    func fans() async throws -> [FanReading] {
        if restoring, delayedRestoreReads > 0 { delayedRestoreReads -= 1 } else if restoring { manual = false }
        return [FanReading(index: 0, minimumRPM: 1200, currentRPM: 1850, maximumRPM: 6000, isManual: manual)]
    }

    func setAllFans(rpm: Int) async throws {
        calls.append("fixed:\(rpm)")
        restoring = false
        manual = !ignoresWrite
        if failsWrite { throw writeError }
    }

    func setCoolingFraction(_ fraction: Float) async throws {
        calls.append("curve")
        restoring = false
        manual = !ignoresWrite
        if failsWrite { throw writeError }
    }

    func restoreAutomatic() async throws {
        calls.append("restore")
        if failsRestore { throw Failure.restore }
        restoring = true
        if delayedRestoreReads == 0 { manual = false }
    }
}

@MainActor
struct CompatibilityControlTestTests {
    @Test func sBothCommandsAndRestoresAfterEach() async {
        let client = ControlTestClient()
        let result = await CompatibilityControlTest.run(client: client, curveFraction: 0.5)
        #expect(result.manual == .requestSucceeded)
        #expect(result.curve == .requestSucceeded)
        #expect(result.restored)
        #expect(client.calls == ["fixed:2350", "restore", "curve", "restore"])
        #expect(!client.manual)
    }

    @Test func restoresPartialWritesAndReportsFailure() async {
        let client = ControlTestClient()
        client.failsWrite = true
        let result = await CompatibilityControlTest.run(client: client, curveFraction: 0.5)
        #expect(result.manual == .requestFailed)
        #expect(result.curve == .requestFailed)
        #expect(result.restored)
        #expect(!client.manual)
        #expect(client.calls.filter { $0 == "restore" }.count == 2)
    }

    @Test func stopsAndRetriesWhenRestorationFails() async {
        let client = ControlTestClient()
        client.failsWrite = true
        client.failsRestore = true
        let result = await CompatibilityControlTest.run(client: client, curveFraction: 0.5)
        #expect(!result.restored)
        #expect(result.curve == .unverified)
        #expect(client.calls == ["fixed:2350", "restore", "restore"])
    }

    @Test func requiresReadbackAndSkipsCurveWithoutTemperature() async {
        let client = ControlTestClient()
        client.ignoresWrite = true
        let result = await CompatibilityControlTest.run(client: client, curveFraction: nil)
        #expect(result.manual == .requestFailed)
        #expect(result.curve == .unverified)
        #expect(result.restored)
    }

    @Test func waitsForDelayedAutomaticModeReadback() async {
        let client = ControlTestClient()
        client.delayedRestoreReads = 2
        let result = await CompatibilityControlTest.run(client: client, curveFraction: nil)
        #expect(result.restored)
        #expect(client.calls == ["fixed:2350", "restore"])
    }

    @Test func reportsAcceptedRestoreThatReadbackNeverConfirms() async {
        let client = ControlTestClient()
        client.delayedRestoreReads = 100
        let result = await CompatibilityControlTest.run(client: client, curveFraction: nil)
        #expect(!result.restored)
        #expect(result.restoreReadbackUnconfirmed)
        #expect(result.currentRestoreError != nil)
        #expect(client.calls == ["fixed:2350", "restore", "restore"])
    }

    @Test func cancellationStillRestoresSystemControl() async {
        let client = ControlTestClient()
        let task = Task { await CompatibilityControlTest.run(client: client, curveFraction: 0.5) }
        while client.calls.isEmpty {
            await Task.yield()
        }
        task.cancel()
        let result = await task.value
        #expect(result.restored)
        #expect(!client.manual)
        #expect(client.calls == ["fixed:2350", "restore"])
        #expect(result.curve == .unverified)
        // Stopping the test is not a failed control request.
        #expect(result.cancelled)
        #expect(result.manual == .unverified)
        #expect(result.controlError == nil)
    }

    @Test func recordsTheHelperFailureAndWhetherSystemControlCameBack() async {
        let client = ControlTestClient()
        client.failsWrite = true
        client.writeError = HelperClientError(message: HelperControlFailure(
            code: .unlockTimeout, fanIndex: 1, durationMS: 10_512, message: "Timed out unlocking system mode for fan 2"
        ).encodedReply())
        let result = await CompatibilityControlTest.run(client: client, curveFraction: 0.5)
        #expect(result.manualFailure == CompatibilityControlFailure(
            code: .unlockTimeout, fanIndex: 1, durationMS: 10_512, restoredAutomatic: true))
        #expect(result.curveFailure?.code == .unlockTimeout)
        // The user still sees the helper's own words, not the encoded payload.
        #expect(result.controlError == "Timed out unlocking system mode for fan 2")
    }

    @Test func recordsPerFanReadbackWhenTheWriteIsIgnored() async {
        let client = ControlTestClient()
        client.ignoresWrite = true
        let result = await CompatibilityControlTest.run(client: client, curveFraction: nil)
        #expect(result.manualFailure == CompatibilityControlFailure(
            code: .readbackNotManual, readbackManual: [false], restoredAutomatic: true))
        #expect(result.curveFailure == nil)
    }

    @Test func leavesNoFailureOnSuccess() async {
        let result = await CompatibilityControlTest.run(client: ControlTestClient(), curveFraction: 0.5)
        #expect(result.manualFailure == nil)
        #expect(result.curveFailure == nil)
    }
}
