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
    var attempts = 0

    /// Seconds until the next attempt, or nil when it would land after the window.
    func nextDelay(at now: Date) -> TimeInterval? {
        let delay = Self.delays[min(attempts, Self.delays.count - 1)]
        guard now.addingTimeInterval(delay).timeIntervalSince(startedAt) <= Self.window else { return nil }
        return delay
    }

    mutating func recordAttempt() {
        attempts += 1
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
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Whether FanBar may write now: still in Automatic, helper enabled, nothing in flight.
    var isReady: () -> Bool = { false }
    var resolveWrite: (ResumableMode) -> SMCLockoutRecovery.Write? = { _ in nil }
    var perform: (SMCLockoutRecovery.Write) async throws -> Void = { _ in }
    /// The SMC took the write; turn the mode back on the usual way.
    var onRecovered: (SMCLockoutRecovery) -> Void = { _ in }
    /// The window closed with the SMC still refusing.
    var onGaveUp: () -> Void = {}

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
        recovery = SMCLockoutRecovery(mode: mode, duration: duration, startedAt: now())
        schedule()
    }

    func cancel() {
        task?.cancel()
        task = nil
        pendingDelay = nil
        recovery = nil
    }

    func restartAfterWake() {
        guard recovery != nil else { return }
        recovery?.restartBackoff()
        schedule()
    }

    /// Writes the refused mode once, quietly, so a failed attempt never flashes
    /// an error banner every few minutes.
    func attempt() async {
        guard var current = recovery else { return }
        pendingDelay = nil
        current.recordAttempt()
        recovery = current
        guard isReady(), let write = resolveWrite(current.mode) else {
            schedule()
            return
        }
        do {
            try await perform(write)
        } catch {
            // The helper already handed the failed write back to macOS.
            schedule()
            return
        }
        // A mode the user picked meanwhile cancelled this recovery and is queued behind the write.
        guard recovery == current else { return }
        cancel()
        onRecovered(current)
    }

    private func schedule() {
        task?.cancel()
        guard let delay = recovery?.nextDelay(at: now()) else {
            guard recovery != nil else { return }
            cancel()
            onGaveUp()
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
