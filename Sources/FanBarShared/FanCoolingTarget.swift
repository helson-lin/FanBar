import Foundation

/// The single rule that turns a cooling fraction (0…1) into a per-fan target
/// RPM. The helper applies it to the hardware, and the app uses it to show the
/// same target, so the two cannot drift apart.
public enum FanCoolingTarget {
    /// Zero is an explicit idle request (target 0 RPM). Any other fraction is
    /// a share of the fan's maximum that stays inside the hardware limits.
    public static func targetRPM(
        fraction: Float,
        minimum: Float,
        maximum: Float
    ) -> Float {
        guard fraction > 0 else { return 0 }
        return min(max((maximum * fraction).rounded(), minimum), maximum)
    }
}
