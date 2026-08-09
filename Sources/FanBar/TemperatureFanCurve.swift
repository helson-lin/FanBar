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
    /// Fraction of each fan's hardware-reported maximum RPM (0…1.00).
    /// Zero means idle (target 0 RPM); non-zero targets stay within hardware Mn/Mx.
    var fraction: Float

    init(id: UUID = UUID(), celsius: Double, fraction: Float) {
        self.id = id
        self.celsius = celsius
        self.fraction = fraction
    }
}

/// User-editable curve profile. Interpolation uses a monotone cubic spline.
struct FanCurveProfile: Codable, Equatable, Sendable {
    static let minimumFraction: Float = 0
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensor, forKey: .sensor)
        try container.encode(points, forKey: .points)
        try container.encode(hysteresisCelsius, forKey: .hysteresisCelsius)
        try container.encode(maxFractionStepPerUpdate, forKey: .maxFractionStepPerUpdate)
    }

    private enum CodingKeys: String, CodingKey {
        case sensor
        case points
        case hysteresisCelsius
        case maxFractionStepPerUpdate
    }

    /// Default: idle through ~41°C, then a smooth rise to full cooling.
    static let standard = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 41, fraction: 0.00),
            FanCurvePoint(celsius: 50, fraction: 0.30),
            FanCurvePoint(celsius: 65, fraction: 0.55),
            FanCurvePoint(celsius: 78, fraction: 0.80),
            FanCurvePoint(celsius: 88, fraction: 1.00)
        ]
    )

    static let silent = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 45, fraction: 0.00),
            FanCurvePoint(celsius: 58, fraction: 0.20),
            FanCurvePoint(celsius: 72, fraction: 0.40),
            FanCurvePoint(celsius: 85, fraction: 0.65),
            FanCurvePoint(celsius: 95, fraction: 0.90)
        ]
    )

    static let aggressive = FanCurveProfile(
        sensor: .maxChip,
        points: [
            FanCurvePoint(celsius: 38, fraction: 0.00),
            FanCurvePoint(celsius: 48, fraction: 0.40),
            FanCurvePoint(celsius: 60, fraction: 0.70),
            FanCurvePoint(celsius: 72, fraction: 0.90),
            FanCurvePoint(celsius: 82, fraction: 1.00)
        ]
    )

    /// Named built-ins for the settings picker.
    enum BuiltIn: String, CaseIterable, Identifiable, Equatable, Hashable {
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

    /// Smooth monotone cubic interpolation through the anchors.
    func fraction(at celsius: Double) -> Float {
        TemperatureFanCurve(points: points.map {
            TemperatureFanCurve.Point(celsius: $0.celsius, fraction: $0.fraction)
        }).fraction(at: celsius)
    }

    /// Sorts points, clamps ranges, enforces min/max count and 0…100% bounds.
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

/// Monotone cubic spline for chip temperature → maximum-fan fraction.
///
/// Uses Fritsch–Carlson slopes so the curve stays smooth without overshooting
/// past neighboring anchors — important when the low end is 0% idle.
struct TemperatureFanCurve {
    struct Point {
        let celsius: Double
        let fraction: Float
    }

    static let standard = TemperatureFanCurve(points: FanCurveProfile.standard.points.map {
        Point(celsius: $0.celsius, fraction: $0.fraction)
    })

    let points: [Point]

    func fraction(at celsius: Double) -> Float {
        guard let first = points.first, let last = points.last else { return 1 }
        if points.count == 1 { return first.fraction }
        if celsius <= first.celsius { return first.fraction }
        if celsius >= last.celsius { return last.fraction }

        let xs = points.map(\.celsius)
        let ys = points.map { Double($0.fraction) }
        let slopes = Self.monotoneSlopes(x: xs, y: ys)

        for index in 0..<(points.count - 1) {
            let x0 = xs[index]
            let x1 = xs[index + 1]
            guard celsius <= x1 || index == points.count - 2 else { continue }
            if celsius > x1 { continue }

            let h = x1 - x0
            guard h > 0 else { return Float(ys[index + 1]) }
            let t = (celsius - x0) / h
            let t2 = t * t
            let t3 = t2 * t
            // Hermite basis
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            let value = h00 * ys[index]
                + h10 * h * slopes[index]
                + h01 * ys[index + 1]
                + h11 * h * slopes[index + 1]
            return Float(
                min(
                    max(value, Double(FanCurveProfile.minimumFraction)),
                    Double(FanCurveProfile.maximumFraction)
                )
            )
        }
        return last.fraction
    }

    /// Fritsch–Carlson monotone cubic derivatives dy/dx at each knot.
    private static func monotoneSlopes(x: [Double], y: [Double]) -> [Double] {
        let n = x.count
        guard n >= 2 else { return Array(repeating: 0, count: max(n, 0)) }

        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let h = x[i + 1] - x[i]
            delta[i] = h > 0 ? (y[i + 1] - y[i]) / h : 0
        }

        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                if delta[i - 1] == 0 || delta[i] == 0 || delta[i - 1].sign != delta[i].sign {
                    m[i] = 0
                } else {
                    m[i] = (delta[i - 1] + delta[i]) / 2
                }
            }
        }

        for i in 0..<(n - 1) {
            if abs(delta[i]) < 1e-12 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let a = m[i] / delta[i]
            let b = m[i + 1] / delta[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / sqrt(s)
                m[i] = t * a * delta[i]
                m[i + 1] = t * b * delta[i]
            }
        }
        return m
    }
}

/// Loads and stores smart-cooling curves as three editable preset slots.
///
/// Editing anchors keeps you on the current preset (no “custom” dead-end).
/// Switching preset saves the current slot, then loads the target slot.
enum FanCurvePreferences {
    /// Legacy single-profile key (migrated on first load).
    static let legacyProfileKey = "fanbar.fanCurveProfile"
    static let selectionKey = "fanbar.fanCurveBuiltInSelection"
    static let slotsKey = "fanbar.fanCurvePresetSlots"
    private static let customSelectionValue = "custom"

    struct Snapshot {
        var profile: FanCurveProfile
        /// Always one of the three presets — never nil.
        var builtInSelection: FanCurveProfile.BuiltIn
        var slots: [FanCurveProfile.BuiltIn: FanCurveProfile]
    }

    static func load() -> Snapshot {
        let defaults = UserDefaults.standard
        var slots = loadSlots(from: defaults)

        // Migrate pre-slot storage once.
        if slots.isEmpty {
            slots = migratedSlots(from: defaults)
            persist(slots: slots, selection: nil, defaults: defaults)
        }

        for builtIn in FanCurveProfile.BuiltIn.allCases where slots[builtIn] == nil {
            slots[builtIn] = builtIn.profile.sanitized()
        }

        let selection = resolvedSelection(defaults: defaults, slots: slots)
        let profile = slots[selection] ?? selection.profile.sanitized()
        return Snapshot(profile: profile, builtInSelection: selection, slots: slots)
    }

    /// Saves `profile` into `selection` and marks that preset active.
    static func save(profile: FanCurveProfile, selection: FanCurveProfile.BuiltIn) {
        var slots = load().slots
        slots[selection] = profile.sanitized()
        persist(slots: slots, selection: selection, defaults: .standard)
    }

    /// Saves every slot (e.g. after switching presets with both sides updated).
    static func save(slots: [FanCurveProfile.BuiltIn: FanCurveProfile], selection: FanCurveProfile.BuiltIn) {
        var normalized: [FanCurveProfile.BuiltIn: FanCurveProfile] = [:]
        for builtIn in FanCurveProfile.BuiltIn.allCases {
            normalized[builtIn] = (slots[builtIn] ?? builtIn.profile).sanitized()
        }
        persist(slots: normalized, selection: selection, defaults: .standard)
    }

    // MARK: - Private

    private static func resolvedSelection(
        defaults: UserDefaults,
        slots: [FanCurveProfile.BuiltIn: FanCurveProfile]
    ) -> FanCurveProfile.BuiltIn {
        if let raw = defaults.string(forKey: selectionKey),
           raw != customSelectionValue,
           let builtIn = FanCurveProfile.BuiltIn(rawValue: raw) {
            return builtIn
        }
        // Legacy “custom” or missing key → keep active shape under standard.
        if let data = defaults.data(forKey: legacyProfileKey),
           let profile = try? JSONDecoder().decode(FanCurveProfile.self, from: data) {
            return profile.matchingBuiltIn() ?? .standard
        }
        return .standard
    }

    private static func loadSlots(from defaults: UserDefaults) -> [FanCurveProfile.BuiltIn: FanCurveProfile] {
        guard let data = defaults.data(forKey: slotsKey),
              let decoded = try? JSONDecoder().decode([String: FanCurveProfile].self, from: data)
        else {
            return [:]
        }
        var slots: [FanCurveProfile.BuiltIn: FanCurveProfile] = [:]
        for (raw, profile) in decoded {
            guard let builtIn = FanCurveProfile.BuiltIn(rawValue: raw) else { continue }
            slots[builtIn] = profile.sanitized()
        }
        return slots
    }

    private static func migratedSlots(from defaults: UserDefaults) -> [FanCurveProfile.BuiltIn: FanCurveProfile] {
        var slots: [FanCurveProfile.BuiltIn: FanCurveProfile] = [:]
        for builtIn in FanCurveProfile.BuiltIn.allCases {
            slots[builtIn] = builtIn.profile.sanitized()
        }

        if let data = defaults.data(forKey: legacyProfileKey),
           let profile = try? JSONDecoder().decode(FanCurveProfile.self, from: data) {
            let sanitized = profile.sanitized()
            let raw = defaults.string(forKey: selectionKey)
            if let raw, raw != customSelectionValue, let builtIn = FanCurveProfile.BuiltIn(rawValue: raw) {
                slots[builtIn] = sanitized
            } else if let match = sanitized.matchingBuiltIn() {
                slots[match] = sanitized
            } else {
                // Custom edits land in the standard slot so nothing is lost.
                slots[.standard] = sanitized
            }
        }
        return slots
    }

    private static func persist(
        slots: [FanCurveProfile.BuiltIn: FanCurveProfile],
        selection: FanCurveProfile.BuiltIn?,
        defaults: UserDefaults
    ) {
        var payload: [String: FanCurveProfile] = [:]
        for builtIn in FanCurveProfile.BuiltIn.allCases {
            payload[builtIn.rawValue] = (slots[builtIn] ?? builtIn.profile).sanitized()
        }
        do {
            let data = try JSONEncoder().encode(payload)
            defaults.set(data, forKey: slotsKey)
            if let selection {
                defaults.set(selection.rawValue, forKey: selectionKey)
                // Keep legacy key in sync for older diagnostics / smoke tests.
                if let active = try? JSONEncoder().encode(payload[selection.rawValue] ?? selection.profile) {
                    defaults.set(active, forKey: legacyProfileKey)
                }
            }
            defaults.synchronize()
        } catch {
            NSLog("FanBar: failed to save fan curve slots: %@", error.localizedDescription)
        }
    }
}
