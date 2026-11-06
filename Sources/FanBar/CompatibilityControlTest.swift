import FanBarShared
import Foundation

/// Uses the same helper commands as normal control. Success includes reading back
/// manual mode, but is still reported as requestSucceeded, not independent verification.
@MainActor
protocol CompatibilityControlClient {
    func fans() async throws -> [FanReading]
    func setAllFans(rpm: Int) async throws
    func setCoolingFraction(_ fraction: Float) async throws
    func restoreAutomatic() async throws
}

extension HelperClient: CompatibilityControlClient {}

struct CompatibilityControlTestResult {
    var manual: CompatibilityControlEvidence = .unverified
    var curve: CompatibilityControlEvidence = .unverified
    /// Set alongside a `.requestFailed` result, for the compatibility report.
    var manualFailure: CompatibilityControlFailure?
    var curveFailure: CompatibilityControlFailure?
    var restored = true
    var restoreError: String?
    var controlError: String?
    var restoreFailure: Error?
    var controlFailure: Error?
    var restoreReadbackUnconfirmed = false

    var currentControlError: String? { controlFailure?.localizedDescription ?? controlError }

    var currentRestoreError: String? {
        if restoreReadbackUnconfirmed {
            return fanBarText("恢复请求已接受，但回读仍未确认自动模式。",
                "Restore request accepted, but automatic mode was not confirmed by readback.")
        }
        return restoreFailure?.localizedDescription ?? restoreError
    }

    mutating func clearRestoreError() {
        restoreError = nil
        restoreFailure = nil
        restoreReadbackUnconfirmed = false
    }

    mutating func markRestoreReadbackUnconfirmed() {
        restoreReadbackUnconfirmed = true
        restoreFailure = nil
        restoreError = currentRestoreError
    }

    /// The user stopped the test. An interrupted step is left unverified, not failed.
    var cancelled = false
}

@MainActor
enum CompatibilityControlTest {
    // Bounded orchestration is covered by failure, cancellation, and restoration tests.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func run(client: any CompatibilityControlClient, curveFraction: Float?) async -> CompatibilityControlTestResult {
        var result = CompatibilityControlTestResult()
        for isCurve in [false, true] {
            if Task.isCancelled || (isCurve && curveFraction == nil) { break }
            var failure: CompatibilityControlFailure?
            do {
                let readings = try await client.fans()
                guard !readings.isEmpty else { break }
                // The fixed command needs a range shared by every fan. Raise speed
                // for the short test rather than deliberately reducing cooling.
                let lower = readings.map(\.minimumRPM).max() ?? 0
                let upper = readings.map(\.maximumRPM).min() ?? 0
                guard lower >= 0, upper > 0, lower <= upper else { break }
                try Task.checkCancellation()
                if isCurve, let curveFraction {
                    try await client.setCoolingFraction(curveFraction)
                } else {
                    let current = readings.map(\.currentRPM).max() ?? lower
                    try await client.setAllFans(rpm: min(upper, max(lower, current + 500)))
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let feedback = try await client.fans()
                let accepted = Set(feedback.map(\.index)) == Set(readings.map(\.index))
                    && feedback.allSatisfy(\.isManual)
                if isCurve {
                    result.curve = accepted ? .requestSucceeded : .requestFailed
                } else {
                    result.manual = accepted ? .requestSucceeded : .requestFailed
                }
                if !accepted { failure = .readbackNotManual(feedback) }
            } catch is CancellationError {
                result.cancelled = true
            } catch {
                result.controlError = error.localizedDescription
                result.controlFailure = error
                failure = CompatibilityControlFailure(error: error)
                if isCurve { result.curve = .requestFailed } else { result.manual = .requestFailed }
            }
            // Also restore after a failed/timeout write: it may have partly applied.
            // Do not check cancellation here; closing the view must still restore.
            result.restored = false
            result.clearRestoreError()
            for _ in 0..<2 {
                do {
                    try await client.restoreAutomatic()
                    // Firmware may acknowledge a mode write before readback catches up.
                    // This wait must finish even when the view's test task was cancelled.
                    for poll in 0..<10 {
                        if poll > 0 {
                            await Task { try? await Task.sleep(nanoseconds: 200_000_000) }.value
                        }
                        let feedback = try await client.fans()
                        if !feedback.isEmpty, feedback.allSatisfy({ !$0.isManual }) {
                            result.restored = true
                            result.clearRestoreError()
                            break
                        }
                    }
                    if result.restored { break }
                    result.markRestoreReadbackUnconfirmed()
                } catch {
                    result.restoreError = error.localizedDescription
                    result.restoreFailure = error
                    result.restoreReadbackUnconfirmed = false
                    continue
                }
            }
            if var failure {
                failure.restoredAutomatic = result.restored
                if isCurve { result.curveFailure = failure } else { result.manualFailure = failure }
            }
            if !result.restored { break }
        }
        return result
    }
}
