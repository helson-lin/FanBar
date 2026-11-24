import Foundation

/// The last successfully accepted fixed target, shared with existing installations.
@MainActor
enum FixedRPMPreference {
    static let key = "fanbar.customFixedRPM"

    static func load(from defaults: UserDefaults = .standard) -> Int? {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    static func apply(
        _ rpm: Int,
        to defaults: UserDefaults = .standard,
        write: (Int) async throws -> Void
    ) async throws {
        try await write(rpm)
        defaults.set(rpm, forKey: key)
    }
}
