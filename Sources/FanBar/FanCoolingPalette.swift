import SwiftUI

/// Maps airflow intensity to a cold-only spectrum; warm colors remain reserved for heat and warnings.
enum FanCoolingPalette {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        func mixed(with other: RGB, progress: Double) -> RGB {
            let amount = min(max(progress, 0), 1)
            return RGB(
                red: red + (other.red - red) * amount,
                green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount
            )
        }

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }
    }

    // Higher airflow shifts toward brighter ice cyan instead of warning red.
    private static let low = RGB(red: 0.32, green: 0.55, blue: 0.95)
    private static let balanced = RGB(red: 0.16, green: 0.72, blue: 0.98)
    private static let high = RGB(red: 0.20, green: 0.88, blue: 1.00)

    static func intensity(for fan: FanReading) -> Double {
        guard fan.maximumRPM > 0 else { return 0 }
        return min(max(Double(fan.currentRPM) / Double(fan.maximumRPM), 0), 1)
    }

    static func tint(for fan: FanReading) -> Color {
        let intensity = intensity(for: fan)
        if intensity <= 0.35 { return low.color }
        if intensity <= 0.60 {
            return low.mixed(
                with: balanced,
                progress: (intensity - 0.35) / 0.25
            ).color
        }
        return balanced.mixed(
            with: high,
            progress: (intensity - 0.60) / 0.25
        ).color
    }
}
