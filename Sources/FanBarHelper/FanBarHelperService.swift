import FanBarShared
import Foundation
import Security

final class FanBarHelperService: NSObject, NSXPCListenerDelegate, FanBarHelperProtocol,
    @unchecked Sendable
{
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
        guard Self.isAuthorizedClient(connection) else { return false }
        hardwareQueue.sync {
            activeConnections += 1
        }
        connection.exportedInterface = NSXPCInterface(with: FanBarHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            hardwareQueue.async {
                self.activeConnections = max(0, self.activeConnections - 1)
                if self.activeConnections == 0 {
                    try? self.driver?.restoreAutomatic()
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
        hardwareQueue.async {
            do {
                try self.connectedDriver().setAllFans(rpm: rpm)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func setCoolingPreset(
        _ rawValue: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        hardwareQueue.async {
            guard let preset = FanCoolingPreset(rawValue: rawValue) else {
                reply(false, fanBarText("未知的散热预设", "Unknown cooling preset"))
                return
            }
            do {
                try self.connectedDriver().setCoolingPreset(preset)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func setCoolingFraction(
        _ fraction: Float,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        hardwareQueue.async {
            // Keep the root API bounded even if a compromised client sends malformed input.
            // 0% is allowed so smart cooling can idle below the low-temp knee.
            guard fraction.isFinite, (0...1.00).contains(fraction) else {
                reply(false, fanBarText("散热比例必须在 0% 到 100% 之间", "Cooling fraction must be between 0% and 100%"))
                return
            }
            do {
                try self.connectedDriver().setCoolingFraction(fraction)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func setAllFansToEightyPercent(
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        hardwareQueue.async {
            do {
                try self.connectedDriver().setAllFansToEightyPercent()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func restoreAutomatic(
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        hardwareQueue.async {
            do {
                try self.connectedDriver().restoreAutomatic()
                reply(true, nil)
            } catch {
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
    private static func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)]
            as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              let teamID = ownTeamIdentifier()
        else { return false }

        let text =
            "anchor apple generic and identifier \"\(FanBarService.appBundleID)\" " +
            "and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
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
