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
    public static let manualModeUnlockDeadline: TimeInterval = 30
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

    /// Read-only: the build this helper process was launched from, captured at startup.
    /// A daemon still running from before an app update reports its old build, which is
    /// exactly what diagnostics need to see. Helpers older than this method never reply.
    func getBuildVersion(
        reply: @escaping @Sendable (String) -> Void
    )
}

public enum HelperLaunchBuild {
    /// The helper ships at FanBar.app/Contents/Library/LaunchServices/<helper>, without its own
    /// Info.plist, so it reads the enclosing app's CFBundleVersion. Call once at process start:
    /// reading later would report a replaced bundle instead of the code actually running.
    public static func read(executableURL: URL) -> String {
        let contents = executableURL.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents",
              let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")),
              let build = info["CFBundleVersion"] as? String else { return "unknown" }
        return sanitized(build)
    }

    /// Only short version tokens leave the helper, never arbitrary plist text.
    public static func sanitized(_ build: String) -> String {
        build.range(of: #"^[A-Za-z0-9._+-]{1,40}$"#, options: .regularExpression) == nil ? "unknown" : build
    }
}
