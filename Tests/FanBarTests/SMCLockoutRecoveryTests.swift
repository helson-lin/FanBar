import XCTest
@testable import FanBar

/// Issue 114: after the SMC refused a run of curve writes, FanBar used to hand
/// back for good and say only a restart helps, although the refusal had cleared
/// twenty minutes later. It now retries the same mode on its own.
final class SMCLockoutRecoveryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func recovery(_ mode: ResumableMode = .preset(.builtIn(.silent))) -> SMCLockoutRecovery {
        SMCLockoutRecovery(mode: mode, duration: .never, startedAt: start)
    }

    func testWaitsGrowThenRepeatTheLongestOne() {
        var recovery = recovery()
        var waits: [TimeInterval] = []
        var now = start
        for _ in 0..<6 {
            guard let delay = recovery.nextDelay(at: now) else { return XCTFail("Stopped inside the window") }
            waits.append(delay)
            now = now.addingTimeInterval(delay)
            recovery.recordAttempt()
        }
        XCTAssertEqual(waits, [30, 60, 120, 300, 300, 300])
    }

    func testStopsOnceTheNextAttemptWouldLandAfterTheWindow() {
        var recovery = recovery()
        for _ in 0..<SMCLockoutRecovery.delays.count {
            recovery.recordAttempt()
        }
        let lastChance = start.addingTimeInterval(SMCLockoutRecovery.window - 300)
        XCTAssertEqual(recovery.nextDelay(at: lastChance), 300)
        XCTAssertNil(recovery.nextDelay(at: lastChance.addingTimeInterval(1)))
    }

    func testWakeStartsTheShortWaitsAgain() {
        var recovery = recovery()
        for _ in 0..<5 {
            recovery.recordAttempt()
        }
        recovery.restartBackoff()
        XCTAssertEqual(recovery.nextDelay(at: start), SMCLockoutRecovery.delays[0])
    }

    func testFixedSpeedRetriesTheSameRPM() {
        XCTAssertEqual(SMCLockoutRecovery.write(for: .fixed(3_000), profile: nil, reading: nil), .fixedRPM(3_000))
    }

    func testPresetRetriesTheCurveAtTheCurrentTemperature() {
        let profile = FanCurveProfile(
            sensor: .cpu,
            points: [FanCurvePoint(celsius: 40, fraction: 0.2), FanCurvePoint(celsius: 80, fraction: 1.0)]
        )
        let reading = ThermalReading(sampledAt: start, cpuCelsius: 60, gpuCelsius: 45)

        XCTAssertEqual(
            SMCLockoutRecovery.write(for: .preset(.builtIn(.silent)), profile: profile, reading: reading),
            .coolingFraction(profile.fraction(at: 60))
        )
    }

    func testPresetWaitsWhileItsCurveCannotBeEvaluated() {
        let profile = FanCurveProfile(
            sensor: .cpu,
            points: [FanCurvePoint(celsius: 40, fraction: 0.2), FanCurvePoint(celsius: 80, fraction: 1.0)]
        )
        let noCPU = ThermalReading(sampledAt: start, cpuCelsius: nil, gpuCelsius: 45)
        let mode = ResumableMode.preset(.builtIn(.silent))

        XCTAssertNil(SMCLockoutRecovery.write(for: mode, profile: nil, reading: noCPU), "Deleted preset")
        XCTAssertNil(SMCLockoutRecovery.write(for: mode, profile: profile, reading: nil), "No reading yet")
        XCTAssertNil(SMCLockoutRecovery.write(for: mode, profile: profile, reading: noCPU), "Sensor missing")
    }

    // MARK: Retrier

    private struct Refused: Error {}

    /// Scheduled attempts never fire on their own; each test calls `attempt()`.
    @MainActor
    private func retrier(clock: @escaping () -> Date) -> SMCLockoutRetrier {
        let retrier = SMCLockoutRetrier(now: clock, sleep: { _ in throw CancellationError() })
        retrier.isReady = { true }
        retrier.resolveWrite = { SMCLockoutRecovery.write(for: $0, profile: nil, reading: nil) }
        return retrier
    }

    @MainActor
    func testRefusedAttemptsKeepRetryingWithLongerWaits() async {
        let retrier = retrier { self.start }
        var writes: [SMCLockoutRecovery.Write] = []
        retrier.perform = { writes.append($0); throw Refused() }
        var recovered = false
        retrier.onRecovered = { _ in recovered = true }

        retrier.start(.fixed(3_000), duration: .never)
        XCTAssertEqual(retrier.pendingDelay, 30)
        await retrier.attempt()
        XCTAssertEqual(retrier.pendingDelay, 60)
        await retrier.attempt()
        XCTAssertEqual(retrier.pendingDelay, 120)

        XCTAssertEqual(writes, [.fixedRPM(3_000), .fixedRPM(3_000)])
        XCTAssertFalse(recovered)
        XCTAssertNotNil(retrier.recovery)
    }

    @MainActor
    func testAcceptedWriteTurnsTheModeBackOnOnce() async {
        let retrier = retrier { self.start }
        var recovered: [SMCLockoutRecovery] = []
        retrier.onRecovered = { recovered.append($0) }

        retrier.start(.preset(.builtIn(.silent)), duration: .thirtyMinutes)
        retrier.resolveWrite = { _ in .coolingFraction(0.4) }
        await retrier.attempt()

        XCTAssertEqual(recovered.map(\.mode), [.preset(.builtIn(.silent))])
        XCTAssertEqual(recovered.map(\.duration), [.thirtyMinutes])
        XCTAssertNil(retrier.recovery)
        XCTAssertNil(retrier.pendingDelay)
        await retrier.attempt()
        XCTAssertEqual(recovered.count, 1)
    }

    @MainActor
    func testNotReadyOrUnresolvableSkipsTheWriteAndWaitsLonger() async {
        let retrier = retrier { self.start }
        var wrote = false
        retrier.perform = { _ in wrote = true }

        retrier.start(.fixed(3_000), duration: .never)
        retrier.isReady = { false }
        await retrier.attempt()
        retrier.isReady = { true }
        retrier.resolveWrite = { _ in nil }
        await retrier.attempt()

        XCTAssertFalse(wrote)
        XCTAssertEqual(retrier.pendingDelay, 120)
    }

    @MainActor
    func testAModePickedDuringTheWriteWins() async {
        let retrier = retrier { self.start }
        var recovered = false
        retrier.onRecovered = { _ in recovered = true }
        retrier.perform = { [weak retrier] _ in retrier?.cancel() }

        retrier.start(.fixed(3_000), duration: .never)
        await retrier.attempt()

        XCTAssertFalse(recovered)
        XCTAssertNil(retrier.recovery)
    }

    @MainActor
    func testGivesUpWhenTheWindowCloses() async {
        var now = start
        let retrier = retrier { now }
        retrier.perform = { _ in throw Refused() }
        var gaveUp = 0
        retrier.onGaveUp = { gaveUp += 1 }

        retrier.start(.fixed(3_000), duration: .never)
        now = start.addingTimeInterval(SMCLockoutRecovery.window)
        await retrier.attempt()

        XCTAssertEqual(gaveUp, 1)
        XCTAssertNil(retrier.recovery)
        XCTAssertNil(retrier.pendingDelay)
    }

    @MainActor
    func testWakeReschedulesTheShortWaitOnlyWhileRecovering() async {
        let retrier = retrier { self.start }
        retrier.perform = { _ in throw Refused() }

        retrier.restartAfterWake()
        XCTAssertNil(retrier.pendingDelay)

        retrier.start(.fixed(3_000), duration: .never)
        await retrier.attempt()
        await retrier.attempt()
        retrier.restartAfterWake()
        XCTAssertEqual(retrier.pendingDelay, 30)
    }
}
