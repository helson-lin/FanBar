import FanBarShared
import Foundation

enum CoolingPresetPreferences {
    static let preferenceKey = "fanbar.visibleCoolingPresets"
    static let defaultRawValue = "2,3"

    static func presets(from rawValue: String) -> [FanCoolingPreset] {
        let selected = Set(
            rawValue.split(separator: ",").compactMap {
                Int($0).flatMap(FanCoolingPreset.init(rawValue:))
            }
        )
        return FanCoolingPreset.allCases.filter(selected.contains).prefix(2).map { $0 }
    }

    static func rawValue(for presets: some Sequence<FanCoolingPreset>) -> String {
        let selected = Set(presets)
        return FanCoolingPreset.allCases
            .filter(selected.contains)
            .prefix(2)
            .map { String($0.rawValue) }
            .joined(separator: ",")
    }
}

extension FanCoolingPreset {
    var title: String {
        switch self {
        case .silent: "静音"
        case .balanced: "均衡"
        case .performance: "性能"
        case .extreme: "极速"
        }
    }

    var percentageText: String {
        "\(Int((maximumFraction * 100).rounded()))%"
    }

    var systemImage: String {
        switch self {
        case .silent: "speaker.slash.fill"
        case .balanced: "circle.lefthalf.filled"
        case .performance: "gauge.with.dots.needle.67percent"
        case .extreme: "bolt.fill"
        }
    }
}
