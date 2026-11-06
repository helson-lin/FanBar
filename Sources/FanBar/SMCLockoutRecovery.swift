import FanBarShared
import Foundation

/// After a run of refused curve writes FanBar hands the fans to macOS, then
/// keeps trying the user's mode again on its own. The refusal often clears by
/// itself minutes after wake (issue 114); giving up for good left the fans in
/// Automatic until the user noticed and switched back by hand.
struct SMCLockoutRecovery: Equatable {
    /// Waits between attempts; the last one repeats until the window closes.
    static let delays: [TimeInterval] = [30, 60, 120, 300]
    /// As long as the panel notice stays up; past that FanBar stops trying.
    static let window: TimeInterval = ControlNotice.handedBackLifetime

    let mode: ResumableMode
    let duration: FanController.AutomaticRestoreDuration
    let startedAt: Date
    /// Attempts so far, written or skipped; they set the wait before the next.
    var attempts = 0
    /// Writes the SMC actually turned down. Skipped attempts and lost
    /// connections are not refusals, so they never count here.
    var refusedWrites = 0
    /// Writes the helper never answered: the connection dropped or timed out.
    var unansweredWrites = 0

    /// Seconds until the next attempt, or nil when it would land after the window.
    func nextDelay(at now: Date) -> TimeInterval? {
        let delay = Self.delays[min(attempts, Self.delays.count - 1)]
        guard now.addingTimeInterval(delay).timeIntervalSince(startedAt) <= Self.window else { return nil }
        return delay
    }

    mutating func recordAttempt() {
        attempts += 1
    }

    mutating func recordFailedWrite(_ error: Error) {
        if Self.isRefusal(error) {
            refusedWrites += 1
        } else {
            unansweredWrites += 1
        }
    }

    /// Why the window closed without the mode coming back.
    enum GiveUp: Equatable {
        /// At least one write reached the SMC and it said no.
        case stillRefused
        /// Writes went out but the helper never answered any of them.
        case unanswered
        /// No write went out: the helper was off, the preset was gone or no
        /// temperature could be read.
        case neverRetried
    }

    var giveUp: GiveUp {
        if refusedWrites > 0 { return .stillRefused }
        return unansweredWrites > 0 ? .unanswered : .neverRetried
    }

    /// A lost or timed-out connection says nothing about the SMC.
    static func isRefusal(_ error: Error) -> Bool {
        (error as? HelperClientError)?.isConnectionFailure != true
    }

    /// Right after wake the SMC is slow, not stuck; start the short waits again.
    mutating func restartBackoff() {
        attempts = 0
    }

    /// What one attempt writes: the same request the mode itself would make now.
    enum Write: Equatable {
        case fixedRPM(Int)
        case coolingFraction(Float)
    }

    /// Nil while a preset's curve cannot be evaluated: deleted preset or no reading yet.
    static func write(for mode: ResumableMode, profile: FanCurveProfile?, reading: ThermalReading?) -> Write? {
        switch mode {
        case .fixed(let rpm):
            return .fixedRPM(rpm)
        case .preset:
            guard let profile, let reading, let temperature = profile.sensor.temperature(in: reading) else { return nil }
            return .coolingFraction(profile.fraction(at: temperature))
        }
    }
}

/// Runs the retries for one refused mode. The controller supplies the readiness
/// check, the hardware write and what happens on success, so the sequencing can
/// be tested without a helper.
@MainActor
final class SMCLockoutRetrier {
    private(set) var recovery: SMCLockoutRecovery?
    /// The wait before the attempt now scheduled; nil when none is.
    private(set) var pendingDelay: TimeInterval?
    private var task: Task<Void, Never>?
    /// The write now with the helper. Cancelling the recovery cannot recall it.
    private var inFlightWrite: Task<Void, Error>?
    /// Changes whenever a recovery starts or ends. A write compares it, not the
    /// recovery itself, which a wake changes by restarting the backoff.
    private var generation = 0
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Whether FanBar may write now: still in Automatic, helper enabled, nothing in flight.
    var isReady: () -> Bool = { false }
    var resolveWrite: (ResumableMode) -> SMCLockoutRecovery.Write? = { _ in nil }
    var perform: (SMCLockoutRecovery.Write) async throws -> Void = { _ in }
    /// The SMC took the write; turn the mode back on the usual way.
    var onRecovered: (SMCLockoutRecovery) -> Void = { _ in }
    /// The window closed without the mode coming back.
    var onGaveUp: (SMCLockoutRecovery.GiveUp) -> Void = { _ in }

    init(
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    func start(_ mode: ResumableMode, duration: FanController.AutomaticRestoreDuration) {
        generation += 1
        recovery = SMCLockoutRecovery(mode: mode, duration: duration, startedAt: now())
        schedule()
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        pendingDelay = nil
        recovery = nil
    }

    /// Waits for a write that already reached the helper. Every mode switch calls
    /// this before its own write, so the two never share the connection at once
    /// and a timed-out retry cannot drop the connection under the user's request.
    func finishInFlightWrite() async {
        _ = await inFlightWrite?.result
    }

    func restartAfterWake() {
        guard recovery != nil else { return }
        recovery?.restartBackoff()
        schedule()
    }

    /// Writes the refused mode once, quietly, so a failed attempt never flashes
    /// an error banner every few minutes.
    func attempt() async {
        guard let mode = recovery?.mode else { return }
        // A wake can bring the next attempt forward while the last write is still out.
        guard inFlightWrite == nil else {
            schedule()
            return
        }
        pendingDelay = nil
        recovery?.recordAttempt()
        guard isReady(), let write = resolveWrite(mode) else {
            schedule()
            return
        }
        let ownGeneration = generation
        let request = Task { @MainActor [perform] in try await perform(write) }
        inFlightWrite = request
        let result = await request.result
        inFlightWrite = nil
        // A mode the user picked meanwhile cancelled this recovery and waited for this write.
        guard generation == ownGeneration, let finished = recovery else { return }
        if case .failure(let error) = result {
            // The helper already handed the failed write back to macOS.
            recovery?.recordFailedWrite(error)
            schedule()
            return
        }
        cancel()
        onRecovered(finished)
    }

    private func schedule() {
        task?.cancel()
        guard let delay = recovery?.nextDelay(at: now()) else {
            guard let recovery else { return }
            cancel()
            onGaveUp(recovery.giveUp)
            return
        }
        pendingDelay = delay
        task = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.attempt()
        }
    }
}

extension SMCLockoutRecovery.GiveUp {
    /// Only a write the SMC turned down earns the restart advice.
    var message: LocalizedControlText {
        switch self {
        case .stillRefused:
            LocalizedControlText {
                fanBarText("SMC 仍然拒绝风扇写入，重启 Mac 可恢复", "The SMC still refuses fan writes; restarting your Mac clears it")
            }
        case .unanswered:
            LocalizedControlText {
                fanBarText("控制服务一直没有回应，风扇仍由 macOS 调节", "The fan control service never answered; macOS still controls the fans")
            }
        case .neverRetried:
            LocalizedControlText {
                fanBarText("FanBar 没能重试风扇模式，风扇仍由 macOS 调节", "FanBar couldn't retry the fan mode; macOS still controls the fans")
            }
        }
    }
}
