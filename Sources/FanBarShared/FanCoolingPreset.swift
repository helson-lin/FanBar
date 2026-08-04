import Foundation

/// A closed set of safe, user-facing cooling levels accepted by the root helper.
public enum FanCoolingPreset: Int, CaseIterable, Identifiable, Sendable {
    case silent
    case balanced
    case performance
    case extreme

    public var id: Int { rawValue }

    public var maximumFraction: Float {
        switch self {
        case .silent: 0.35
        case .balanced: 0.50
        case .performance: 0.65
        case .extreme: 0.80
        }
    }
}
