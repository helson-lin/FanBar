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
                    reply(false, 0, 0, 0, false, "未找到风扇 \(index + 1)")
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

    /// Limit this root service to the signed FanBar application from the same team.
    private static func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)]
            as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else { return false }

        let text =
            "anchor apple generic and identifier \"\(FanBarService.appBundleID)\" " +
            "and certificate leaf[subject.OU] = \"\(FanBarService.teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
