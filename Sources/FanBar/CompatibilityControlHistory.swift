import Foundation

struct CompatibilityControlHistory: Codable {
    let device: CompatibilityDevice
    let manual: CompatibilityControlEvidence
    let curve: CompatibilityControlEvidence
    var manualFailure: CompatibilityControlFailure?
    var curveFailure: CompatibilityControlFailure?
    let recordedAt: Date
}

/// Only local control evidence; never contains credentials or a device identifier.
struct CompatibilityControlHistoryStore {
    let defaults: UserDefaults
    private let key = "fanbar.compatibility.controlHistory.v1"
    private let recoveryKey = "fanbar.compatibility.controlHistory.recoveryAttempted.v1"

    func load(for device: CompatibilityDevice) -> CompatibilityControlHistory? {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(CompatibilityControlHistory.self, from: data),
              saved.device == device else { return nil }
        return saved
    }

    /// Recover existing automatic results from this app's local report receipts.
    /// A user-confirmation checkbox alone is never treated as an automatic test.
    static func recover(from receipts: [CompatibilitySavedReceipt], for device: CompatibilityDevice) -> CompatibilityControlHistory? {
        var manual: CompatibilityControlEvidence = .unverified
        var curve: CompatibilityControlEvidence = .unverified
        var manualFailure: CompatibilityControlFailure?
        var curveFailure: CompatibilityControlFailure?
        var recordedAt: Date?
        for receipt in receipts.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let report = try? JSONDecoder().decode(CompatibilityReport.self, from: receipt.reportData),
                  report.device == device else { continue }
            for result in report.capabilities {
                guard let evidence = CompatibilityControlEvidence(rawValue: result.status.rawValue),
                    evidence != .unverified else { continue }
                if result.capability == .manualControl, manual == .unverified {
                    manual = evidence
                    manualFailure = result.failure
                    recordedAt = recordedAt ?? receipt.createdAt
                }
                if result.capability == .smartCooling, curve == .unverified {
                    curve = evidence
                    curveFailure = result.failure
                    recordedAt = recordedAt ?? receipt.createdAt
                }
            }
            if manual != .unverified, curve != .unverified { break }
        }
        guard let recordedAt else { return nil }
        return CompatibilityControlHistory(device: device, manual: manual, curve: curve,
            manualFailure: manualFailure, curveFailure: curveFailure, recordedAt: recordedAt)
    }

    func needsRecovery(for device: CompatibilityDevice) -> Bool {
        guard let data = defaults.data(forKey: recoveryKey),
              let attempted = try? JSONDecoder().decode(CompatibilityDevice.self, from: data) else { return true }
        return attempted != device
    }

    func markRecoveryAttempted(for device: CompatibilityDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        defaults.set(data, forKey: recoveryKey)
    }

    func save(_ record: CompatibilityControlHistory) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}
