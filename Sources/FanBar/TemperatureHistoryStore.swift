import Foundation

/// Persists the temperature trace to `UserDefaults` so the chart doesn't start
/// blank every time the app relaunches. Only the last `historyDuration` window
/// is worth keeping, so loading re-applies the same cutoff the chart uses.
enum TemperatureHistoryStore {
    static let preferenceKey = "fanbar.temperatureHistory"

    static func load(
        from defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [ThermalReading] {
        guard let data = defaults.data(forKey: preferenceKey),
              let decoded = try? JSONDecoder().decode([ThermalReading].self, from: data) else {
            return []
        }
        let cutoff = now.addingTimeInterval(-TemperatureChart.historyDuration)
        return decoded.filter { $0.sampledAt >= cutoff }
    }

    static func save(_ samples: [ThermalReading], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: preferenceKey)
    }
}
