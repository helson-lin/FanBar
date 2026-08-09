import FanBarShared
import Foundation

/// Temperature sensor used as the X-axis input for smart cooling.
enum FanCurveSensor: String, Codable, CaseIterable, Identifiable, Sendable {
    case maxChip
    case cpu
    case gpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxChip: fanBarText("CPU/GPU 较高者", "Higher of CPU/GPU")
        case .cpu: fanBarText("仅 CPU", "CPU only")
        case .gpu: fanBarText("仅 GPU", "GPU only")
        }
    }
}

/// A single anchor on the temperature → cooling-fraction curve.
struct FanCurvePoint: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Chip temperature in Celsius.
    var celsius: Double
    /// Fraction of each fan's hardware-reported maximum RPM (0.30…1.00).
    var fraction: Float

    init(id: UUID = UUID(), celsius: Double, fraction: Float) {
        self.id = id
        self.celsius = celsius
        self.fraction = fraction
    }
}

/// User-editable curve profile. Interpolation still uses `TemperatureFanCurve`.
struct FanCurveProfile: Codable, Equatable, Sendable {
    static let minimumFraction: Float = 0.30
    static let maximumFraction: Float = 1.00
    static let minimumPointCount = 2
    static let maximumPointCount = 8
    static let minimumCelsius = 30.0
    static let maximumCelsius = 100.0

    var sensor: FanCurveSensor
    var points: [FanCurvePoint]

    /// Built-in default — matches the historical smart-cooling curve.
    static let standard = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 45, fraction: 0.35),
            FanCurvePoint(celsius: 60, fraction: 0.50),
            FanCurvePoint(celsius: 75, fraction: 0.75),
            FanCurvePoint(celsius: 85, fraction: 1.00)
        ]
    )

    static let silent = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 50, fraction: 0.30),
            FanCurvePoint(celsius: 65, fraction: 0.40),
            FanCurvePoint(celsius: 78, fraction: 0.55),
            FanCurvePoint(celsius: 90, fraction: 0.85)
        ]
    )

    static let aggressive = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 40, fraction: 0.45),
            FanCurvePoint(celsius: 55, fraction: 0.65),
            FanCurvePoint(celsius: 68, fraction: 0.85),
            FanCurvePoint(celsius: 80, fraction: 1.00)
        ]
    )

    /// Named built-ins for the settings picker.
    enum BuiltIn: String, CaseIterable, Identifiable {
        case standard
        case silent
        case aggressive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: fanBarText("默认", "Default")
            case .silent: fanBarText("静音", "Quiet")
            case .aggressive: fanBarText("激进", "Aggressive")
            }
        }

        var profile: FanCurveProfile {
            switch self {
            case .standard: .standard
            case .silent: .silent
            case .aggressive: .aggressive
            }
        }
    }

    /// Linearly interpolates adjacent points and clamps beyond both ends.
    func fraction(at celsius: Double) -> Float {
        TemperatureFanCurve(points: points.map {
            TemperatureFanCurve.Point(celsius: $0.celsius, fraction: $0.fraction)
        }).fraction(at: celsius)
    }

    /// Sorts points, clamps ranges, enforces min/max count and 30% floor.
    func sanitized() -> FanCurveProfile {
        var cleaned = points
            .map { point in
                FanCurvePoint(
                    id: point.id,
                    celsius: min(
                        max(point.celsius.rounded(), Self.minimumCelsius),
                        Self.maximumCelsius
                    ),
                    fraction: min(
                        max(point.fraction, Self.minimumFraction),
                        Self.maximumFraction
                    )
                )
            }
            .sorted { $0.celsius < $1.celsius }

        // Collapse same-temperature anchors so interpolation stays well-defined.
        var unique: [FanCurvePoint] = []
        for point in cleaned {
            if let last = unique.last, abs(last.celsius - point.celsius) < 0.5 {
                unique[unique.count - 1] = point
            } else {
                unique.append(point)
            }
        }
        cleaned = unique

        if cleaned.count < Self.minimumPointCount {
            cleaned = Self.standard.points
        }
        if cleaned.count > Self.maximumPointCount {
            cleaned = Array(cleaned.prefix(Self.maximumPointCount))
        }

        // Ensure a strictly increasing temperature axis after clamping collisions.
        for index in cleaned.indices.dropFirst() {
            if cleaned[index].celsius <= cleaned[index - 1].celsius {
                cleaned[index].celsius = min(
                    cleaned[index - 1].celsius + 1,
                    Self.maximumCelsius
                )
            }
        }

        return FanCurveProfile(sensor: sensor, points: cleaned)
    }

    func matchingBuiltIn() -> BuiltIn? {
        let normalized = sanitized()
        return BuiltIn.allCases.first { builtIn in
            let candidate = builtIn.profile.sanitized()
            guard candidate.sensor == normalized.sensor,
                  candidate.points.count == normalized.points.count else {
                return false
            }
            return zip(candidate.points, normalized.points).allSatisfy { lhs, rhs in
                abs(lhs.celsius - rhs.celsius) < 0.5
                    && abs(lhs.fraction - rhs.fraction) < 0.01
            }
        }
    }
}

/// Interpolation engine for chip temperature → maximum-fan fraction.
struct TemperatureFanCurve {
    struct Point {
        let celsius: Double
        let fraction: Float
    }

    static let standard = TemperatureFanCurve(points: FanCurveProfile.standard.points.map {
        Point(celsius: $0.celsius, fraction: $0.fraction)
    })

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

/// Loads and stores the active smart-cooling curve.
enum FanCurvePreferences {
    static let profileKey = "fanbar.fanCurveProfile"

    static func load() -> FanCurveProfile {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let decoded = try? JSONDecoder().decode(FanCurveProfile.self, from: data) else {
            return .standard
        }
        return decoded.sanitized()
    }

    static func save(_ profile: FanCurveProfile) {
        let sanitized = profile.sanitized()
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }
}
