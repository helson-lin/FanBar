import Foundation

/// Why a helper write failed, in a form the app can report without reading error text.
///
/// The XPC replies keep their `(Bool, String?)` signature so a stale daemon and a new app
/// still talk. A current helper puts this structure in the string behind `marker`; a
/// reply without the marker is an older helper's plain localized message.
public struct HelperControlFailure: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case smcConnectionFailed = "SMC_CONNECTION_FAILED"
        case smcOperationFailed = "SMC_OPERATION_FAILED"
        case smcInvalidValue = "SMC_INVALID_VALUE"
        case unlockTimeout = "UNLOCK_TIMEOUT"
        case modeKeyMissing = "MODE_KEY_MISSING"
        case invalidRequest = "INVALID_REQUEST"
        /// The Mac is going to sleep and the fans were handed back to macOS; writes wait for wake.
        case systemSleeping = "SYSTEM_SLEEPING"
    }

    public static let marker = "fanbar-failure-v1:"

    public let code: Code
    /// Only a four-character SMC key name, never a localized parameter description.
    public let smcKey: String?
    public let resultCode: Int32?
    public let fanIndex: Int?
    public var durationMS: Int?
    /// The helper's localized description, shown to the user and never uploaded.
    public let message: String

    public init(code: Code, smcKey: String? = nil, resultCode: Int32? = nil, fanIndex: Int? = nil,
                durationMS: Int? = nil, message: String) {
        self.code = code
        self.smcKey = smcKey.flatMap(Self.validKey)
        self.resultCode = resultCode
        self.fanIndex = fanIndex.flatMap { (0...7).contains($0) ? $0 : nil }
        self.durationMS = durationMS.map { min(max($0, 0), 600_000) }
        self.message = message
    }

    public func encodedReply() -> String {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else {
            return message
        }
        return Self.marker + json
    }

    /// `nil` for a plain message from a helper that predates structured failures.
    public static func decode(reply: String) -> Self? {
        guard reply.hasPrefix(marker),
              let decoded = try? JSONDecoder().decode(Self.self, from: Data(reply.dropFirst(marker.count).utf8)) else {
            return nil
        }
        // Re-validate: the init's bounds do not run for decoded values.
        return Self(code: decoded.code, smcKey: decoded.smcKey, resultCode: decoded.resultCode,
                    fanIndex: decoded.fanIndex, durationMS: decoded.durationMS, message: decoded.message)
    }

    private static func validKey(_ key: String) -> String? {
        key.range(of: "^[A-Za-z0-9! ]{4}$", options: .regularExpression) == nil ? nil : key
    }
}
