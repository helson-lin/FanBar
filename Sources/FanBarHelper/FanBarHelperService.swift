import FanBarShared
import Foundation
import os
import Security

final class FanBarHelperService: NSObject, NSXPCListenerDelegate, FanBarHelperProtocol,
    @unchecked Sendable
{
    private static let log = Logger(subsystem: FanBarService.helperBundleID, category: "service")
    private let listener = NSXPCListener(machServiceName: FanBarService.helperBundleID)
    private let hardwareQueue = DispatchQueue(label: "local.fanbar.helper.hardware")
    private var driver: SMCFanDriver?
    private var activeConnections = 0

    override init() {
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    func restoreForShutdown() {
        hardwareQueue.sync {
            try? driver?.restoreAutomatic()
            driver = nil
        }
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard Self.isAuthorizedClient(connection) else {
            Self.log.error("Rejected XPC client pid \(connection.processIdentifier)")
            return false
        }
        hardwareQueue.sync {
            activeConnections += 1
        }
        connection.exportedInterface = NSXPCInterface(with: FanBarHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            hardwareQueue.async {
                self.activeConnections = max(0, self.activeConnections - 1)
                if self.activeConnections == 0, let driver = self.driver {
                    Self.log.notice("Last client disconnected; restoring automatic fan control")
                    try? driver.restoreAutomatic()
                }
            }
        }
        connection.resume()
        return true
    }

    func getFanCount(reply: @escaping @Sendable (Bool, Int, String?) -> Void) {
        hardwareQueue.async {
            do {
                reply(true, try self.connectedDriver().fans().count, nil)
            } catch {
                reply(false, 0, error.localizedDescription)
            }
        }
    }

    func getFan(
        _ index: Int,
        reply: @escaping @Sendable (Bool, Float, Float, Float, Bool, String?) -> Void
    ) {
        hardwareQueue.async {
            do {
                let fans = try self.connectedDriver().fans()
                guard let fan = fans.first(where: { $0.index == index }) else {
                    reply(false, 0, 0, 0, false, fanBarFormat("未找到风扇 %d", "Fan %d was not found", index + 1))
                    return
                }
                reply(true, fan.actual, fan.minimum, fan.maximum, fan.isManual, nil)
            } catch {
                reply(false, 0, 0, 0, false, error.localizedDescription)
            }
        }
    }

    func setAllFans(
        rpm: Float,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        // NaN survives min/max clamping and would reach the SMC unchanged.
        guard rpm.isFinite, rpm >= 0 else {
            reply(false, fanBarText("转速必须是有效的非负数", "RPM must be a finite, non-negative number"))
            return
        }
        performWrite("setAllFans", reply: reply) { driver in
            try driver.setAllFans(rpm: rpm)
        }
    }

    func setCoolingPreset(
        _ rawValue: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        guard let preset = FanCoolingPreset(rawValue: rawValue) else {
            reply(false, fanBarText("未知的散热预设", "Unknown cooling preset"))
            return
        }
        performWrite("setCoolingPreset", reply: reply) { driver in
            try driver.setCoolingPreset(preset)
        }
    }

    func setCoolingFraction(
        _ fraction: Float,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        // Keep the root API bounded even if a compromised client sends malformed input.
        // 0% is allowed so smart cooling can idle below the low-temp knee.
        guard fraction.isFinite, (0...1.00).contains(fraction) else {
            reply(false, fanBarText("散热比例必须在 0% 到 100% 之间", "Cooling fraction must be between 0% and 100%"))
            return
        }
        performWrite("setCoolingFraction", reply: reply) { driver in
            try driver.setCoolingFraction(fraction)
        }
    }

    func setAllFansToEightyPercent(
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        performWrite("setAllFansToEightyPercent", reply: reply) { driver in
            try driver.setAllFansToEightyPercent()
        }
    }

    func restoreAutomatic(
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        performWrite("restoreAutomatic", reply: reply) { driver in
            try driver.restoreAutomatic()
        }
    }

    /// Serializes a hardware write and records its duration and real error, which
    /// the client cannot see once its reply timeout has already fired.
    private func performWrite(
        _ operation: StaticString,
        reply: @escaping @Sendable (Bool, String?) -> Void,
        _ body: @escaping @Sendable (SMCFanDriver) throws -> Void
    ) {
        hardwareQueue.async {
            let start = Date()
            do {
                try body(self.connectedDriver())
                let elapsed = Date().timeIntervalSince(start)
                Self.log.notice("\(operation, privacy: .public) succeeded in \(elapsed, format: .fixed(precision: 2))s")
                reply(true, nil)
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                Self.log.error("\(operation, privacy: .public) failed after \(elapsed, format: .fixed(precision: 2))s: \(error.localizedDescription, privacy: .public)")
                reply(false, error.localizedDescription)
            }
        }
    }

    private func connectedDriver() throws -> SMCFanDriver {
        if let driver { return driver }
        let newDriver = try SMCFanDriver()
        driver = newDriver
        return newDriver
    }

    /// Limit this root service to the signed FanBar application from the same
    /// team as the helper itself. Deriving the team from our own signature
    /// keeps Development and Developer ID builds aligned without weakening the
    /// requirement for unsigned/ad-hoc clients, which have no team identifier.
    ///
    /// The check is bound to the connection's audit token, never its PID: a
    /// PID can be recycled or `exec`-replaced by a signed binary after an
    /// attacker has already opened the connection.
    private static func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
        guard let text = clientRequirementText() else { return false }
        if #available(macOS 13.0, *) {
            // The system enforces the requirement against the audit token of
            // every incoming message, so a swapped process is rejected too.
            connection.setCodeSigningRequirement(text)
            return true
        }
        guard let token = auditToken(of: connection) else { return false }
        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func clientRequirementText() -> String? {
        guard let teamID = ownTeamIdentifier() else { return nil }
        return "anchor apple generic and identifier \"\(FanBarService.appBundleID)\" " +
            "and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// `auditToken` is not public before macOS 13; KVC is the long-standing
    /// way helpers read it on older systems.
    private static func auditToken(of connection: NSXPCConnection) -> audit_token_t? {
        guard let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        value.getValue(&token, size: MemoryLayout<audit_token_t>.size)
        return token
    }

    private static func ownTeamIdentifier() -> String? {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess,
              let ownCode
        else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
            let information = signingInformation as? [CFString: Any]
        else { return nil }
        return information[kSecCodeInfoTeamIdentifier] as? String
    }
}
