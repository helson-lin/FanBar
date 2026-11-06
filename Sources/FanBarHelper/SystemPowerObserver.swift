import Foundation
import IOKit
import IOKit.pwr_mgt

/// Forwards system sleep and wake to the helper. Sleep is held until
/// `willSleep` returns, so the fans are back with macOS before the SMC sleeps.
final class SystemPowerObserver {
    /// The power messages the helper acts on.
    enum Message: Equatable {
        /// Sleep is being considered; FanBar never vetoes it.
        case canSleep
        /// Sleep is committed and waits for an acknowledgement.
        case willSleep
        /// The Mac is waking.
        case wake

        /// `iokit_common_msg()` values; the macros are not imported into Swift.
        init?(messageType: UInt32) {
            switch messageType {
            case 0xE000_0270: self = .canSleep
            case 0xE000_0280: self = .willSleep
            // Will-power-on and has-powered-on both, so a wake that skips one
            // still lifts the hold on writes.
            case 0xE000_0320, 0xE000_0300: self = .wake
            default: return nil
            }
        }
    }

    private let willSleep: () -> Void
    private let didWake: () -> Void
    private let allowPowerChange: (io_connect_t, Int) -> Void
    private var rootPort: io_connect_t = IO_OBJECT_NULL
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL

    init(
        willSleep: @escaping () -> Void,
        didWake: @escaping () -> Void,
        allowPowerChange: @escaping (io_connect_t, Int) -> Void = { _ = IOAllowPowerChange($0, $1) }
    ) {
        self.willSleep = willSleep
        self.didWake = didWake
        self.allowPowerChange = allowPowerChange
    }

    /// Registers on the current run loop; returns false when IOKit refuses.
    @discardableResult
    func start() -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPort, { context, _, messageType, argument in
            guard let context else { return }
            Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
                .handle(messageType, argument: argument)
        }, &notifier)
        guard rootPort != IO_OBJECT_NULL, let notifyPort else { return false }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
            .defaultMode
        )
        return true
    }

    deinit {
        if notifier != IO_OBJECT_NULL { IODeregisterForSystemPower(&notifier) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        if rootPort != IO_OBJECT_NULL { IOServiceClose(rootPort) }
    }

    /// `argument` carries the notification ID that sleep messages must acknowledge.
    func handle(_ messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        let notificationID = Int(bitPattern: argument)
        switch Message(messageType: messageType) {
        case .canSleep:
            allowPowerChange(rootPort, notificationID)
        case .willSleep:
            willSleep()
            allowPowerChange(rootPort, notificationID)
        case .wake:
            didWake()
        case nil:
            break
        }
    }
}
