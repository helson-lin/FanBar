import Foundation

public enum FanBarService {
    public static let helperBundleID = "local.fanbar.helper"
    public static let helperPlistName = "\(helperBundleID).plist"
    public static let appBundleID = "local.fanbar.app"
    public static let teamID = "64S5F787T9"
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
