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
    static let minimumHysteresisCelsius = 0.0
    static let maximumHysteresisCelsius = 5.0
    static let defaultHysteresisCelsius = 2.0
    static let minimumFractionStep: Float = 0.02
    static let maximumFractionStep: Float = 0.20
    static let defaultFractionStep: Float = 0.05

    var sensor: FanCurveSensor
    var points: [FanCurvePoint]
    /// Extra °C applied on the falling edge so fans do not chatter near a knee.
    var hysteresisCelsius: Double
    /// Max absolute fraction change applied per control tick (rate limit).
    var maxFractionStepPerUpdate: Float

    init(
        sensor: FanCurveSensor,
        points: [FanCurvePoint],
        hysteresisCelsius: Double = defaultHysteresisCelsius,
        maxFractionStepPerUpdate: Float = defaultFractionStep
    ) {
        self.sensor = sensor
        self.points = points
        self.hysteresisCelsius = hysteresisCelsius
        self.maxFractionStepPerUpdate = maxFractionStepPerUpdate
    }

    // Older builds only stored sensor + points; missing keys keep smoothing defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sensor = try container.decode(FanCurveSensor.self, forKey: .sensor)
        points = try container.decode([FanCurvePoint].self, forKey: .points)
        hysteresisCelsius = try container.decodeIfPresent(
            Double.self,
            forKey: .hysteresisCelsius
        ) ?? Self.defaultHysteresisCelsius
        maxFractionStepPerUpdate = try container.decodeIfPresent(
            Float.self,
            forKey: .maxFractionStepPerUpdate
        ) ?? Self.defaultFractionStep
    }

    private enum CodingKeys: String, CodingKey {
        case sensor
        case points
        case hysteresisCelsius
        case maxFractionStepPerUpdate
    }

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
    ///
    /// Never replaces a user curve with the built-in default. Colliding
    /// temperatures are spread by 1°C so edits cannot wipe the whole profile.
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

        if cleaned.isEmpty {
            cleaned = Self.standard.points.map {
                FanCurvePoint(celsius: $0.celsius, fraction: $0.fraction)
            }
        }

        // Guarantee a usable curve without discarding the user's points.
        while cleaned.count < Self.minimumPointCount {
            let last = cleaned[cleaned.count - 1]
            cleaned.append(
                FanCurvePoint(
                    celsius: min(last.celsius + 5, Self.maximumCelsius),
                    fraction: min(last.fraction + 0.1, Self.maximumFraction)
                )
            )
        }
        if cleaned.count > Self.maximumPointCount {
            cleaned = Array(cleaned.prefix(Self.maximumPointCount))
        }

        // Strictly increasing X-axis (forward pass, then backward if ceiling-hit).
        for index in cleaned.indices.dropFirst() {
            if cleaned[index].celsius <= cleaned[index - 1].celsius {
                cleaned[index].celsius = min(
                    cleaned[index - 1].celsius + 1,
                    Self.maximumCelsius
                )
            }
        }
        for index in cleaned.indices.dropLast().reversed() {
            if cleaned[index].celsius >= cleaned[index + 1].celsius {
                cleaned[index].celsius = max(
                    cleaned[index + 1].celsius - 1,
                    Self.minimumCelsius
                )
            }
        }

        return FanCurveProfile(
            sensor: sensor,
            points: cleaned,
            hysteresisCelsius: min(
                max(hysteresisCelsius.rounded(), Self.minimumHysteresisCelsius),
                Self.maximumHysteresisCelsius
            ),
            maxFractionStepPerUpdate: min(
                max(maxFractionStepPerUpdate, Self.minimumFractionStep),
                Self.maximumFractionStep
            )
        )
    }

    /// Localized label for the menu bar and settings (built-in name or “Custom”).
    var displayName: String {
        matchingBuiltIn()?.title ?? fanBarText("自定义", "Custom")
    }

    func matchingBuiltIn() -> BuiltIn? {
        let normalized = sanitized()
        return BuiltIn.allCases.first { builtIn in
            let candidate = builtIn.profile.sanitized()
            // Smoothing knobs are user-tunable and do not disqualify a built-in shape.
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
