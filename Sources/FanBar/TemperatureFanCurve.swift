import Foundation

/// A conservative default curve expressed as chip temperature and maximum-fan fraction.
struct TemperatureFanCurve {
    struct Point {
        let celsius: Double
        let fraction: Float
    }

    static let standard = TemperatureFanCurve(points: [
        Point(celsius: 45, fraction: 0.35),
        Point(celsius: 60, fraction: 0.50),
        Point(celsius: 75, fraction: 0.75),
        Point(celsius: 85, fraction: 1.00)
    ])

    let points: [Point]

    /// Linearly interpolates adjacent points and clamps temperatures beyond both ends.
    func fraction(at celsius: Double) -> Float {
        guard let first = points.first, let last = points.last else { return 1 }
        if celsius <= first.celsius { return first.fraction }
        if celsius >= last.celsius { return last.fraction }

        for (lower, upper) in zip(points, points.dropFirst())
        where celsius <= upper.celsius {
            let progress = Float(
                (celsius - lower.celsius) / (upper.celsius - lower.celsius)
            )
            return lower.fraction + (upper.fraction - lower.fraction) * progress
        }
        return last.fraction
    }
}
