import FanBarShared
import Foundation

struct HelperClientError: LocalizedError, Sendable {
    let message: String
    /// Connection failures need a system-settings action; hardware errors do not.
    let isConnectionFailure: Bool
    /// The reply never arrived, as opposed to the connection being refused.
    let isTimeout: Bool
    /// Structured cause from a current helper; `nil` for older helpers and app-side failures.
    let failure: HelperControlFailure?
    var diagnosticCode: Int?

    init(message reply: String, isConnectionFailure: Bool = false, isTimeout: Bool = false) {
        let failure = HelperControlFailure.decode(reply: reply)
        let message = failure?.message ?? reply
        self.message = message
        self.failure = failure
        self.isConnectionFailure = isConnectionFailure
        self.isTimeout = isTimeout
        if let code = failure?.resultCode {
            diagnosticCode = Int(code)
        } else if let match = message.range(of: #"[（(]-?[0-9]{1,11}[）)]$"#, options: .regularExpression) {
            // Older helpers already include numeric SMC codes in the localized reply.
            // Extract only that bounded number; never persist the free-form message.
            diagnosticCode = Int(message[match].dropFirst().dropLast())
        }
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

/// What the running helper daemon says about its own build.
enum HelperBuildQuery: Equatable, Sendable {
    case reported(String)
    /// No reply in time: a helper older than the build query, or a hung one.
    case noReply
    case connectionFailed(Int)
}

/// Typed, reconnecting client for the root launch daemon.
final class HelperClient: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var connectionGenerations = HelperConnectionGenerations()
    private let requestTimeout: TimeInterval
    /// Until the caller reports the real count, assume the most fans the helper accepts.
    private var expectedFanCount = FanControlTiming.maximumFanCount
    /// Called after a timed-out connection is torn down. The helper restores
    /// automatic control once its last client disconnects, so the owner must
    /// re-apply any manual mode it still believes is active.
    var onConnectionReset: (@Sendable () -> Void)?

    init(requestTimeout: TimeInterval = 3) {
        self.requestTimeout = max(requestTimeout, 0.01)
    }

    func setExpectedFanCount(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        expectedFanCount = count
        lock.unlock()
    }

    /// A write that times out tears down the connection, and the helper then restores
    /// automatic control, so the timeout must outlast the driver's unlock retries.
    private var writeTimeout: TimeInterval {
        lock.lock()
        let count = expectedFanCount
        lock.unlock()
        return FanControlTiming.writeReplyTimeout(fanCount: count, base: requestTimeout)
    }

    deinit {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
    }

    private func trace<Value>(_ action: RuntimeDiagnosticEvent.Action, value: Double? = nil,
                              _ operation: () async throws -> Value) async throws -> Value {
        let requestID = UUID().uuidString.lowercased()
        let started = ProcessInfo.processInfo.systemUptime
        RuntimeDiagnostics.shared.record(.control, action, .started, requestID: requestID, value: value)
        do {
            let result = try await DiagnosticRequestContext.$id.withValue(requestID) { try await operation() }
            RuntimeDiagnostics.shared.record(.control, action, .succeeded, requestID: requestID,
                durationMS: (ProcessInfo.processInfo.systemUptime - started) * 1000)
            return result
        } catch {
            RuntimeDiagnostics.shared.record(.control, action, .failed, requestID: requestID,
                code: (error as? HelperClientError)?.diagnosticCode ?? (error as NSError).code,
                durationMS: (ProcessInfo.processInfo.systemUptime - started) * 1000)
            throw error
        }
    }

    func fans() async throws -> [FanReading] {
        try await trace(.fanRead) {
            let count = try await fanCount()
            var readings: [FanReading] = []
            for index in 0..<count {
                let reading = try await fan(index)
                readings.append(reading)
                RuntimeDiagnostics.shared.record(.control, .readback, .succeeded, value: Double(reading.currentRPM),
                    fanIndex: index, manual: reading.isManual)
            }
            return readings
        }
    }

    func setAllFans(rpm: Int) async throws {
        try await trace(.fixedRPM, value: Double(rpm)) {
            try await callVoid { proxy, reply in proxy.setAllFans(rpm: Float(rpm), reply: reply) }
        }
    }

    func setCoolingPreset(_ preset: FanCoolingPreset) async throws {
        try await trace(.preset, value: Double(preset.rawValue)) {
            try await callVoid { proxy, reply in proxy.setCoolingPreset(preset.rawValue, reply: reply) }
        }
    }

    func setCoolingFraction(_ fraction: Float) async throws {
        try await trace(.curve, value: Double(fraction)) {
            try await callVoid { proxy, reply in proxy.setCoolingFraction(fraction, reply: reply) }
        }
    }

    func setAllFansToEightyPercent() async throws {
        try await trace(.curve, value: 0.8) {
            try await callVoid { proxy, reply in proxy.setAllFansToEightyPercent(reply: reply) }
        }
    }

    func restoreAutomatic() async throws {
        try await trace(.restoreAutomatic) {
            try await callVoid { proxy, reply in proxy.restoreAutomatic(reply: reply) }
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
            scheduleTimeout(for: gate, continuation: continuation, after: writeTimeout)
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
        continuation: CheckedContinuation<Value, Error>,
        after timeout: TimeInterval? = nil
    ) {
        let requestID = DiagnosticRequestContext.id
        gate.scheduleTimeout(after: timeout ?? requestTimeout) { [weak self] in
            RuntimeDiagnostics.shared.record(.xpc, .timeout, .failed, requestID: requestID, value: timeout ?? self?.requestTimeout)
            self?.invalidateConnection()
            continuation.resume(
                throwing: HelperClientError(
                    message: fanBarText(
                        "控制服务未响应，请重新授权或重启 FanBar",
                        "The fan control service did not respond. Reauthorize it or restart FanBar."
                    ),
                    isConnectionFailure: true,
                    isTimeout: true
                )
            )
        }
    }

    private func proxy(
        error handler: @escaping @Sendable (Error) -> Void
    ) -> FanBarHelperProtocol? {
        let connection = activeConnection()
        let requestID = DiagnosticRequestContext.id
        return connection.remoteObjectProxyWithErrorHandler { error in
            RuntimeDiagnostics.shared.record(.xpc, .connect, .failed, requestID: requestID, code: (error as NSError).code)
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
        RuntimeDiagnostics.shared.record(.xpc, .connect, .started, value: Double(generation))
        newConnection.invalidationHandler = { [weak self] in
            RuntimeDiagnostics.shared.record(.xpc, .invalidated, .observed, value: Double(generation))
            self?.clearConnection(generation: generation)
        }
        newConnection.interruptionHandler = { [weak self] in
            RuntimeDiagnostics.shared.record(.xpc, .interrupted, .observed, value: Double(generation))
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

    /// Diagnostics only. Uses its own short-lived connection: an old helper may silently drop
    /// the unknown message, and timing out here must never tear down the control connection
    /// (the helper restores automatic control when its last client leaves).
    static func queryRunningBuild(timeout: TimeInterval = 2) async -> HelperBuildQuery {
        let connection = NSXPCConnection(machServiceName: FanBarService.helperBundleID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanBarHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<HelperBuildQuery, Never>) in
            let gate = ReplyGate()
            gate.scheduleTimeout(after: timeout) { continuation.resume(returning: .noReply) }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                gate.once { continuation.resume(returning: .connectionFailed((error as NSError).code)) }
            } as? FanBarHelperProtocol
            guard let proxy else {
                gate.once { continuation.resume(returning: .connectionFailed(-1)) }
                return
            }
            proxy.getBuildVersion { build in
                gate.once { continuation.resume(returning: .reported(HelperLaunchBuild.sanitized(build))) }
            }
        }
    }

    /// A timed-out connection is not safe to reuse for the next mode switch.
    private func invalidateConnection() {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
        if current != nil { onConnectionReset?() }
    }
}
