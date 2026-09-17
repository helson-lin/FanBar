import Foundation

public enum FanBarService {
    public static let helperBundleID = "local.fanbar.helper"
    public static let helperPlistName = "\(helperBundleID).plist"
    public static let appBundleID = "local.fanbar.app"
}

/// Worst-case timing of the helper's fan writes, shared so the app's reply
/// timeout can never undercut the driver's own manual-mode unlock retry.
public enum FanControlTiming {
    public static let maximumFanCount = 8
    public static let manualModeUnlockSettle: TimeInterval = 0.5
    public static let manualModeUnlockDeadline: TimeInterval = 10
    /// SMC reads and the target write surrounding each fan's unlock.
    public static let perFanIOAllowance: TimeInterval = 1

    /// Fans are unlocked sequentially, so every fan may consume a full unlock.
    public static func writeReplyTimeout(fanCount: Int, base: TimeInterval) -> TimeInterval {
        let fans = min(max(fanCount, 1), maximumFanCount)
        let perFan = manualModeUnlockSettle + manualModeUnlockDeadline + perFanIOAllowance
        return base + Double(fans) * perFan
    }
}

/// The helper deliberately exposes only bounded fan operations, never arbitrary SMC writes.
@objc public protocol FanBarHelperProtocol {
    func getFanCount(
        reply: @escaping @Sendable (Bool, Int, String?) -> Void
    )

    func getFan(
        _ index: Int,
        reply: @escaping @Sendable (Bool, Float, Float, Float, Bool, String?) -> Void
    )

    func setAllFans(
        rpm: Float,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func setCoolingPreset(
        _ rawValue: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func setCoolingFraction(
        _ fraction: Float,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    /// Sets every fan to 80% of its own hardware-reported maximum.
    func setAllFansToEightyPercent(
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func restoreAutomatic(
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
}
