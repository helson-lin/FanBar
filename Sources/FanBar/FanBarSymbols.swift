import Foundation

/// SF Symbol names that need a fallback on older macOS. FanBar supports macOS 11,
/// and an unknown name renders as nothing, so each newer symbol pairs with one
/// that exists there. Each choice takes the OS version so every branch is testable.
enum FanBarSymbols {
    private static var current: OperatingSystemVersion { ProcessInfo.processInfo.operatingSystemVersion }

    static var fan: String { fan(on: current) }
    static var fanFill: String { fanFill(on: current) }
    static var fanBlades: String { fanBlades(on: current) }
    static var fanSlash: String { fanSlash(on: current) }
    static var balanced: String { balanced(on: current) }
    static var gauge: String { gauge(on: current) }

    /// Fan blades: `fan` is macOS 14+, `fanblades` macOS 12+.
    static func fan(on os: OperatingSystemVersion) -> String {
        os.majorVersion >= 14 ? "fan" : fanBlades(on: os)
    }

    /// Filled fan used by the menu-bar glyph. `fan.fill` is macOS 14+;
    /// `fanblades.fill` is the filled fan on macOS 12–13; `wind` on macOS 11.
    static func fanFill(on os: OperatingSystemVersion) -> String {
        if os.majorVersion >= 14 { return "fan.fill" }
        if os.majorVersion >= 12 { return "fanblades.fill" }
        return "wind"
    }

    /// Bare blades for the spinning glyph; `wind` stands in on macOS 11.
    static func fanBlades(on os: OperatingSystemVersion) -> String {
        os.majorVersion >= 12 ? "fanblades" : "wind"
    }

    /// "No fan data": `fan.slash` is macOS 14+.
    static func fanSlash(on os: OperatingSystemVersion) -> String {
        os.majorVersion >= 14 ? "fan.slash" : "exclamationmark.triangle"
    }

    /// Half-filled circle for Balanced: the `.filled` spelling is macOS 12+.
    static func balanced(on os: OperatingSystemVersion) -> String {
        os.majorVersion >= 12 ? "circle.lefthalf.filled" : "circle.lefthalf.fill"
    }

    /// Gauge for Performance: macOS 14+; `speedometer` is available everywhere.
    static func gauge(on os: OperatingSystemVersion) -> String {
        os.majorVersion >= 14 ? "gauge.with.dots.needle.67percent" : "speedometer"
    }
}
