import Foundation

/// The last successfully accepted fixed target, shared with existing installations.
@MainActor
enum FixedRPMPreference {
    static let key = "fanbar.customFixedRPM"
    private static let smokeTestSuite = "local.fanbar.automatic-restore-smoke"

    /// Keep smoke-test writes separate from the user's remembered target.
    static func smokeTestDefaults() -> UserDefaults? {
        UserDefaults(suiteName: smokeTestSuite)
    }

    static func load(from defaults: UserDefaults? = .standard) -> Int? {
        guard let defaults else { return nil }
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    static func initialTarget(saved: Int?, presets: [Int], in range: ClosedRange<Int>) -> Int {
        let validSaved = saved.flatMap { $0 > 0 ? $0 : nil }
        let preferred = validSaved ?? presets.first(where: range.contains) ?? range.lowerBound
        return min(max(preferred, range.lowerBound), range.upperBound)
    }

    /// Picks the initial Manual target for the controller's current shared fan range,
    /// returning nil when fan bounds are unavailable or do not overlap.
    static func initialTarget(for controller: FanController) -> Int? {
        controller.fixedRPMRange.map {
            initialTarget(saved: controller.customFixedRPM, presets: FanController.fixedRPMPresets, in: $0)
        }
    }

    @discardableResult
    static func apply(
        _ rpm: Int,
        to defaults: UserDefaults? = .standard,
        write: (Int) async throws -> Void
    ) async throws -> Int? {
        try await write(rpm)
        if rpm > 0, let defaults {
            defaults.set(rpm, forKey: key)
        }
        return load(from: defaults)
    }
}
