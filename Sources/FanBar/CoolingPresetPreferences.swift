import FanBarShared
import Foundation

/// Which presets appear as shortcut buttons in the menu panel (up to two).
enum CoolingPresetPreferences {
    static let preferenceKey = "fanbar.menuCoolingPresets.v2"
    /// Pre-custom-preset key (`"2,3"`), still written for older builds.
    static let legacyPreferenceKey = "fanbar.visibleCoolingPresets"
    static let defaultRawValue = "builtin:2,builtin:3"
    static let menuLimit = 2

    /// Shortcuts in display order (`available` order), skipping presets that
    /// no longer exist so a deleted custom preset never leaves a dead button.
    static func presets(
        from rawValue: String,
        available: [CoolingPresetID]
    ) -> [CoolingPresetID] {
        let selected = Set(rawValue.split(separator: ",").compactMap {
            CoolingPresetID(token: String($0))
        })
        return Array(available.filter(selected.contains).prefix(menuLimit))
    }

    static func rawValue(for presets: [CoolingPresetID]) -> String {
        presets.prefix(menuLimit).map(\.token).joined(separator: ",")
    }

    /// The shortcut list after checking or unchecking `id`, kept in display
    /// order. Returns nil when a new shortcut would exceed the limit.
    static func toggling(
        _ id: CoolingPresetID,
        in current: [CoolingPresetID],
        order: [CoolingPresetID]
    ) -> [CoolingPresetID]? {
        var selection = Set(current)
        if selection.contains(id) {
            selection.remove(id)
        } else {
            guard selection.count < menuLimit else { return nil }
            selection.insert(id)
        }
        return order.filter(selection.contains)
    }

    /// Persists a shortcut list and mirrors its built-in part to the legacy key.
    static func save(_ presets: [CoolingPresetID], defaults: UserDefaults = .standard) {
        defaults.set(rawValue(for: presets), forKey: preferenceKey)
        let legacy = presets.compactMap(\.builtInPreset).map { String($0.rawValue) }
        defaults.set(legacy.joined(separator: ","), forKey: legacyPreferenceKey)
    }

    static func removing(_ id: CoolingPresetID, defaults: UserDefaults = .standard) {
        let current = (defaults.string(forKey: preferenceKey) ?? defaultRawValue)
            .split(separator: ",")
            .compactMap { CoolingPresetID(token: String($0)) }
        guard current.contains(id) else { return }
        save(current.filter { $0 != id }, defaults: defaults)
    }

    /// Copies the legacy `"2,3"` list into the v2 key once.
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: preferenceKey) == nil,
              let legacy = defaults.string(forKey: legacyPreferenceKey) else { return }
        let presets = FanCoolingPreset.allCases.filter { preset in
            legacy.split(separator: ",").contains { Int($0) == preset.rawValue }
        }
        defaults.set(
            rawValue(for: presets.map { CoolingPresetID.builtIn($0) }),
            forKey: preferenceKey
        )
    }
}

extension FanCoolingPreset {
    var title: String {
        switch self {
        case .silent: fanBarText("静音", "Silent")
        case .balanced: fanBarText("均衡", "Balanced")
        case .performance: fanBarText("性能", "Performance")
        case .extreme: fanBarText("极速", "Extreme")
        }
    }

    var systemImage: String {
        switch self {
        case .silent: "speaker.slash.fill"
        case .balanced: FanBarSymbols.balanced
        case .performance: FanBarSymbols.gauge
        case .extreme: "bolt.fill"
        }
    }
}
