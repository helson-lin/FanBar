import FanBarShared
import Foundation

struct HelperClientError: LocalizedError, Sendable {
    let message: String
    /// Connection failures need a system-settings action; hardware errors do not.
    let isConnectionFailure: Bool

    init(message: String, isConnectionFailure: Bool = false) {
        self.message = message
        self.isConnectionFailure = isConnectionFailure
    }

    var errorDescription: String? { message }
}

/// Serializes an XPC reply against its timeout. A daemon can accept a
/// connection without invoking the reply block, so duplicate protection alone
/// is insufficient: every continuation also needs a finite escape path.
final class ReplyGate: @unchecked Sendable {
    private var replied = false
    private var timeoutWorkItem: DispatchWorkItem?
    private let lock = NSLock()

    func once(_ action: () -> Void) {
        lock.lock()
        guard !replied else {
            lock.unlock()
            return
        }
        replied = true
        let pendingTimeout = timeoutWorkItem
        timeoutWorkItem = nil
        lock.unlock()
        pendingTimeout?.cancel()
        action()
    }

    func scheduleTimeout(
        after interval: TimeInterval,
        _ action: @escaping @Sendable () -> Void
    ) {
        let workItem = DispatchWorkItem { [self] in
            once(action)
        }
        lock.lock()
        guard !replied else {
            lock.unlock()
            return
        }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = workItem
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + interval,
            execute: workItem
        )
    }
}

/// Assigns each cached XPC connection a monotonically increasing identity so
/// delayed callbacks from an older connection cannot clear its replacement.
struct HelperConnectionGenerations {
    private(set) var current: UInt64 = 0

    mutating func issue() -> UInt64 {
        current &+= 1
        return current
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == current
    }
}

/// Typed, reconnecting client for the root launch daemon.
final class HelperClient: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var connectionGenerations = HelperConnectionGenerations()
    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 3) {
        self.requestTimeout = max(requestTimeout, 0.01)
    }

    deinit {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
    }

    func fans() async throws -> [FanReading] {
        let count = try await fanCount()
        var readings: [FanReading] = []
        for index in 0..<count {
            readings.append(try await fan(index))
        }
        return readings
    }

    func setAllFans(rpm: Int) async throws {
        try await callVoid { proxy, reply in
            proxy.setAllFans(rpm: Float(rpm), reply: reply)
        }
    }

    func setCoolingPreset(_ preset: FanCoolingPreset) async throws {
        try await callVoid { proxy, reply in
            proxy.setCoolingPreset(preset.rawValue, reply: reply)
        }
    }

    func setCoolingFraction(_ fraction: Float) async throws {
        try await callVoid { proxy, reply in
            proxy.setCoolingFraction(fraction, reply: reply)
        }
    }

    func setAllFansToEightyPercent() async throws {
        try await callVoid { proxy, reply in
            proxy.setAllFansToEightyPercent(reply: reply)
        }
    }

    func restoreAutomatic() async throws {
        try await callVoid { proxy, reply in
            proxy.restoreAutomatic(reply: reply)
        }
    }

    private func fanCount() async throws -> Int {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, Error>) in
            let gate = ReplyGate()
            scheduleTimeout(for: gate, continuation: continuation)
            guard let proxy = proxy(error: { error in
                gate.once { continuation.resume(throwing: error) }
            }) else {
                gate.once {
                    continuation.resume(throwing: HelperClientError(
                        message: fanBarText("无法连接风扇控制服务", "Unable to connect to the fan control service"),
                        isConnectionFailure: true
                    ))
                }
                return
            }
            proxy.getFanCount { success, count, error in
                gate.once {
                    if success {
                        continuation.resume(returning: count)
                    } else {
                        continuation.resume(
                            throwing: HelperClientError(message: error ?? fanBarText("无法读取风扇数量", "Unable to read the fan count"))
                        )
                    }
                }
            }
        }
    }

    private func fan(_ index: Int) async throws -> FanReading {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<FanReading, Error>) in
            let gate = ReplyGate()
            scheduleTimeout(for: gate, continuation: continuation)
            guard let proxy = proxy(error: { error in
                gate.once { continuation.resume(throwing: error) }
            }) else {
                gate.once {
                    continuation.resume(throwing: HelperClientError(
                        message: fanBarText("无法连接风扇控制服务", "Unable to connect to the fan control service"),
                        isConnectionFailure: true
                    ))
                }
                return
            }
            proxy.getFan(index) { success, actual, minimum, maximum, manual, error in
                gate.once {
                    if success {
                        continuation.resume(
                            returning: FanReading(
                                index: index,
                                minimumRPM: Int(minimum.rounded()),
                                currentRPM: Int(actual.rounded()),
                                maximumRPM: Int(maximum.rounded()),
                                isManual: manual
                            )
                        )
                    } else {
                        continuation.resume(
                            throwing: HelperClientError(message: error ?? fanBarFormat("无法读取风扇 %d", "Unable to read fan %d", index + 1))
                        )
                    }
                }
            }
        }
    }

    private func callVoid(
        _ body: @escaping (
            FanBarHelperProtocol,
            @escaping @Sendable (Bool, String?) -> Void
        ) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let gate = ReplyGate()
            scheduleTimeout(for: gate, continuation: continuation)
            guard let proxy = proxy(error: { error in
                gate.once { continuation.resume(throwing: error) }
            }) else {
                gate.once {
                    continuation.resume(throwing: HelperClientError(
                        message: fanBarText("无法连接风扇控制服务", "Unable to connect to the fan control service"),
                        isConnectionFailure: true
                    ))
                }
                return
            }
            body(proxy) { success, error in
                gate.once {
                    if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                        throwing: HelperClientError(message: error ?? fanBarText("风扇控制失败", "Fan control failed"))
                        )
                    }
                }
            }
        }
    }

    private func scheduleTimeout<Value>(
        for gate: ReplyGate,
        continuation: CheckedContinuation<Value, Error>
    ) {
        gate.scheduleTimeout(after: requestTimeout) { [weak self] in
            self?.invalidateConnection()
            continuation.resume(
                throwing: HelperClientError(
                    message: fanBarText(
                        "控制服务未响应，请重新授权或重启 FanBar",
                        "The fan control service did not respond. Reauthorize it or restart FanBar."
                    ),
                    isConnectionFailure: true
                )
            )
        }
    }

    private func proxy(
        error handler: @escaping @Sendable (Error) -> Void
    ) -> FanBarHelperProtocol? {
        let connection = activeConnection()
        return connection.remoteObjectProxyWithErrorHandler { error in
            handler(HelperClientError(
                message: error.localizedDescription,
                isConnectionFailure: true
            ))
        } as? FanBarHelperProtocol
    }

    private func activeConnection() -> NSXPCConnection {
        lock.lock()
        if let connection {
            lock.unlock()
            return connection
        }
        let newConnection = NSXPCConnection(
            machServiceName: FanBarService.helperBundleID,
            options: .privileged
        )
        let generation = connectionGenerations.issue()
        newConnection.remoteObjectInterface = NSXPCInterface(with: FanBarHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.clearConnection(generation: generation)
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.clearConnection(generation: generation)
        }
        newConnection.resume()
        connection = newConnection
        lock.unlock()
        return newConnection
    }

    private func clearConnection(generation: UInt64) {
        lock.lock()
        if connectionGenerations.isCurrent(generation) {
            connection = nil
        }
        lock.unlock()
    }

    /// A timed-out connection is not safe to reuse for the next mode switch.
    private func invalidateConnection() {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
    }
}
