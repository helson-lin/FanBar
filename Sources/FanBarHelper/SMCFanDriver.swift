import AppleSMC
import FanBarShared
import Foundation
import os

enum FanHardwareError: LocalizedError {
    case unavailable(Int32)
    case operation(String, Int32)
    case invalidValue(String)
    case unlockTimeout(Int)
    case modeKeyMissing

    var errorDescription: String? {
        switch self {
        case .unavailable(let code):
            fanBarFormat("无法以特权身份连接 AppleSMC（%d）", "Unable to connect to AppleSMC with privileges (%d)", code)
        case .operation(let key, let code):
            fanBarFormat("SMC 操作 %@ 失败（%d）", "SMC operation %@ failed (%d)", key, code)
        case .invalidValue(let key):
            fanBarFormat("SMC 键 %@ 返回了无效数据", "SMC key %@ returned invalid data", key)
        case .unlockTimeout(let fan):
            fanBarFormat("风扇 %d 的系统模式解锁超时", "Timed out unlocking system mode for fan %d", fan + 1)
        case .modeKeyMissing:
            fanBarText(
                "此 Mac 的 SMC 未提供风扇模式键（F0Md/F0md），无法手动控制风扇",
                "This Mac's SMC has no fan mode key (F0Md/F0md/FS!), so manual fan control is unavailable"
            )
        }
    }
}

extension FanHardwareError {
    /// AppleSMC's "key not found" (0x84), as the bridge reports an SMC result.
    static let keyNotFoundCode: Int32 = 0x10084

    /// The SMC answered that the key does not exist, rather than failing to answer.
    var isKeyNotFound: Bool {
        if case .operation(_, Self.keyNotFoundCode) = self { return true }
        return false
    }

    /// The structured form sent to the app; only fixed codes, SMC key names and numbers.
    func controlFailure(durationMS: Int? = nil) -> HelperControlFailure {
        let message = errorDescription ?? ""
        switch self {
        case .unavailable(let code):
            return HelperControlFailure(code: .smcConnectionFailed, resultCode: code, durationMS: durationMS, message: message)
        case .operation(let key, let code):
            return HelperControlFailure(code: .smcOperationFailed, smcKey: key, resultCode: code,
                                        durationMS: durationMS, message: message)
        case .invalidValue(let key):
            // Some call sites pass a localized parameter name; the failure keeps only real key names.
            return HelperControlFailure(code: .smcInvalidValue, smcKey: key, durationMS: durationMS, message: message)
        case .unlockTimeout(let fan):
            return HelperControlFailure(code: .unlockTimeout, fanIndex: fan, durationMS: durationMS, message: message)
        case .modeKeyMissing:
            return HelperControlFailure(code: .modeKeyMissing, durationMS: durationMS, message: message)
        }
    }
}

/// Raw SMC key access. The helper talks to AppleSMC; tests substitute an
/// in-memory key table so the control logic can run without hardware.
protocol SMCKeyStore: AnyObject {
    func read(_ name: String) throws -> FanBarSMCValue
    func write(_ name: String, _ value: FanBarSMCValue) throws
}

final class AppleSMCKeyStore: SMCKeyStore {
    init() throws {
        let result = fanbar_smc_open()
        guard result == 0 else { throw FanHardwareError.unavailable(result) }
    }

    deinit {
        fanbar_smc_close()
    }

    func read(_ name: String) throws -> FanBarSMCValue {
        var value = FanBarSMCValue()
        let result = Self.reconnecting({ fanbar_smc_read(Self.key(name), &value) }, reopen: fanbar_smc_reopen)
        guard result == 0 else { throw FanHardwareError.operation(name, result) }
        return value
    }

    func write(_ name: String, _ value: FanBarSMCValue) throws {
        var value = value
        let result = Self.reconnecting({ fanbar_smc_write(Self.key(name), &value) }, reopen: fanbar_smc_reopen)
        guard result == 0 else { throw FanHardwareError.operation(name, result) }
    }

    /// The helper keeps one connection for its whole life. When AppleSMC drops
    /// it, every later call fails the same way until the helper restarts, so
    /// reopen once and repeat the call. Reads and fan writes are idempotent.
    static func reconnecting(_ call: () -> Int32, reopen: () -> Int32) -> Int32 {
        let result = call()
        guard isConnectionLost(result), reopen() == 0 else { return result }
        return call()
    }

    /// Codes meaning the connection itself is gone, not that the SMC said no.
    static func isConnectionLost(_ code: Int32) -> Bool {
        connectionLostCodes.contains(UInt32(bitPattern: code))
    }

    private static let connectionLostCodes: Set<UInt32> = [
        0x1000_0003, // MACH_SEND_INVALID_DEST: the port is dead
        0x1000_0007, // MACH_SEND_INVALID_RIGHT
        UInt32(bitPattern: -308), // MIG_SERVER_DIED
        0xE000_02C0, // kIOReturnNoDevice
        0xE000_02CD, // kIOReturnNotOpen, also the bridge's answer when it holds no connection
        0xE000_02D9, // kIOReturnNotAttached
        0xE000_02E8, // kIOReturnOffline
    ]

    private static func key(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

struct HardwareFan {
    let index: Int
    let actual: Float
    let target: Float
    let minimum: Float
    let maximum: Float
    let isManual: Bool
}

/// Root-only Apple Silicon fan controller.
///
/// The mode probing, Float32 encoding, and Ftst retry sequence are based on the
/// MIT-licensed macos-smc-fan interoperability research by Alexander Goodkind.
final class SMCFanDriver {
    private static let log = Logger(subsystem: FanBarService.helperBundleID, category: "driver")
    /// How this Mac switches a fan between system and manual control.
    private enum ModeControl: Equatable {
        /// Apple Silicon and newer Intel: one mode byte per fan (`F0Md` / `F0md`).
        case perFan(String)
        /// Older Intel (e.g. Mac mini 2014): `FS! ` is a bitmask, bit N = fan N forced manual.
        case forceMask
    }

    /// How long to wait for `Ftst` to unlock a fan's mode key.
    struct UnlockTiming {
        var settle: TimeInterval
        var deadline: TimeInterval
        var pollInterval: TimeInterval

        static let hardware = UnlockTiming(
            settle: FanControlTiming.manualModeUnlockSettle,
            deadline: FanControlTiming.manualModeUnlockDeadline,
            pollInterval: 0.1
        )
    }

    static let forceMaskKey = "FS! "
    private static let perFanFormats = ["F%dmd", "F%dMd"]
    private let store: SMCKeyStore
    private let unlockTiming: UnlockTiming
    /// Probed when the driver opens, often seconds after wake while the SMC is
    /// still slow. Only a found key is kept; a failed probe runs again on the
    /// next request instead of breaking control until the helper restarts.
    private var probedModeControl: ModeControl?
    private var probedForceTest = false

    convenience init() throws {
        try self.init(store: AppleSMCKeyStore())
    }

    init(store: SMCKeyStore, unlockTiming: UnlockTiming = .hardware) {
        self.store = store
        self.unlockTiming = unlockTiming
        probedModeControl = try? SMCFanDriver.detectModeControl(in: store)
        _ = probeForceTest()
    }

    /// Nil only when the SMC said every mode key is missing. Any other failed
    /// read throws, so one slow answer is never reported as a permanent limit.
    private func modeControl() throws -> ModeControl? {
        if let probedModeControl { return probedModeControl }
        probedModeControl = try Self.detectModeControl(in: store)
        return probedModeControl
    }

    /// Reads `Ftst` again until it has been found once.
    private func probeForceTest() -> Bool {
        if !probedForceTest {
            probedForceTest = (try? store.read("Ftst")) != nil
        }
        return probedForceTest
    }

    deinit {
        // Returning to system policy is more important than preserving a manual preset.
        // The store closes the SMC connection after this runs.
        try? restoreAutomatic()
    }

    func fans() throws -> [HardwareFan] {
        let countValue = try store.read("FNum")
        let count = Int(Self.bytes(of: countValue).first ?? 0)
        guard (1...8).contains(count) else {
            throw FanHardwareError.invalidValue("FNum")
        }

        return try (0..<count).map { index in
            let isManual = try isManualMode(fan: index)
            return HardwareFan(
                index: index,
                actual: try readFloat("F\(index)Ac"),
                target: try readFloat("F\(index)Tg"),
                minimum: try readFloat("F\(index)Mn"),
                maximum: try readFloat("F\(index)Mx"),
                isManual: isManual
            )
        }
    }

    func setAllFans(rpm: Float) throws {
        let snapshot = try fans()
        try setFans(snapshot) { fan in
            min(max(rpm, fan.minimum), fan.maximum)
        }
    }

    func setAllFansToEightyPercent() throws {
        try setCoolingPreset(.extreme)
    }

    func setCoolingPreset(_ preset: FanCoolingPreset) throws {
        try setCoolingFraction(preset.maximumFraction)
    }

    func setCoolingFraction(_ fraction: Float) throws {
        // 0% is intentional idle (smart-cooling low-temp segment); still hard-capped at 100%.
        guard fraction.isFinite, (0...1.00).contains(fraction) else {
            throw FanHardwareError.invalidValue(fanBarText("散热比例", "cooling fraction"))
        }
        let snapshot = try fans()
        try setFans(snapshot) { fan in
            // Explicit idle at 0%; other fractions stay inside hardware Mn/Mx.
            FanCoolingTarget.targetRPM(
                fraction: fraction,
                minimum: fan.minimum,
                maximum: fan.maximum
            )
        }
    }

    private func setFans(
        _ snapshot: [HardwareFan],
        target: (HardwareFan) -> Float
    ) throws {
        do {
            for fan in snapshot {
                try enableManualMode(fan: fan.index)
                try writeFloat("F\(fan.index)Tg", value: target(fan))
            }
        } catch {
            // A partial multi-fan transition is unsafe; roll the whole machine back.
            try? restoreAutomatic()
            throw error
        }
    }

    func restoreAutomatic() throws {
        let countValue = try store.read("FNum")
        let count = Int(Self.bytes(of: countValue).first ?? 0)
        guard (1...8).contains(count) else {
            throw FanHardwareError.invalidValue("FNum")
        }

        var errors = FirstError()
        let (modes, modesAreGuessed) = restorableModes(&errors)
        // Fans whose known mode key refused 0 keep their target until Ftst is cleared.
        var refused: [Int: Error] = [:]
        for index in 0..<count {
            if let error = clearPerFanModes(of: index, in: modes), !modesAreGuessed {
                refused[index] = error
                continue
            }
            errors.record { try writeFloat("F\(index)Tg", value: 0) }
        }
        if modes.contains(.forceMask) {
            errors.record(reported: !modesAreGuessed) { try writeBytes(Self.forceMaskKey, bytes: [0, 0]) }
        }
        if probeForceTest() {
            errors.record { try writeBytes("Ftst", bytes: [0]) }
        }
        if let error = handBackRefusedFans(refused, modes: modes) {
            errors.note(error)
        }
        if let error = errors.first { throw error }
    }

    /// Keeps the first failure while the rest of a restore still runs.
    private struct FirstError {
        private(set) var first: Error?

        mutating func record(reported: Bool = true, _ step: () throws -> Void) {
            do {
                try step()
            } catch {
                if reported { note(error) }
            }
        }

        mutating func note(_ error: Error) {
            if first == nil { first = error }
        }
    }

    /// The probed mode control, or, when the probe fails, every key the mode
    /// could live in; the ones this Mac lacks fail harmlessly and are not reported.
    private func restorableModes(_ errors: inout FirstError) -> (modes: [ModeControl], guessed: Bool) {
        do {
            return (try modeControl().map { [$0] } ?? [], false)
        } catch {
            errors.note(error)
            return (Self.perFanFormats.map(ModeControl.perFan) + [.forceMask], true)
        }
    }

    /// Writes 0 to each per-fan mode key and returns the last refusal, if any.
    private func clearPerFanModes(of index: Int, in modes: [ModeControl]) -> Error? {
        var refusal: Error?
        for case .perFan(let format) in modes {
            do {
                try writeBytes(String(format: format, index), bytes: [0])
            } catch {
                refusal = error
            }
        }
        return refusal
    }

    /// Some SMCs refuse a mode of 0 while `Ftst` is still set. Once `Ftst` is
    /// cleared, macOS may already have taken the fan back, or the write goes
    /// through. A fan still in manual mode is held at its minimum, never at a
    /// target of 0, which would keep it stopped however hot the Mac gets.
    private func handBackRefusedFans(_ refused: [Int: Error], modes: [ModeControl]) -> Error? {
        guard !refused.isEmpty, case .perFan(let format)? = modes.first else { return nil }
        Thread.sleep(forTimeInterval: unlockTiming.settle)
        var firstError: Error?
        for (index, error) in refused.sorted(by: { $0.key < $1.key }) {
            let key = String(format: format, index)
            let released = (try? store.read(key)).map { Self.bytes(of: $0).first == 0 } == true
                || (try? writeBytes(key, bytes: [0])) != nil
            if released {
                try? writeFloat("F\(index)Tg", value: 0)
                Self.log.notice("Fan \(index) went back to macOS once Ftst was cleared")
                continue
            }
            if firstError == nil { firstError = error }
            if let minimum = try? readFloat("F\(index)Mn") {
                try? writeFloat("F\(index)Tg", value: minimum)
            }
            Self.log.error("Fan \(index) stayed in manual mode; holding it at its minimum")
        }
        return firstError
    }

    private func enableManualMode(fan index: Int) throws {
        guard let modeControl = try self.modeControl() else { throw FanHardwareError.modeKeyMissing }
        if case .forceMask = modeControl {
            try setMode(fan: index, manual: true)
            return
        }
        let key = modeKey(index, in: modeControl) ?? ""
        if (try? writeBytes(key, bytes: [1])) != nil {
            return
        }
        guard probeForceTest() else {
            throw FanHardwareError.operation(key, -1)
        }

        let unlockStart = Date()
        try writeBytes("Ftst", bytes: [1])
        Thread.sleep(forTimeInterval: unlockTiming.settle)

        let deadline = Date().addingTimeInterval(unlockTiming.deadline)
        while Date() < deadline {
            if (try? writeBytes(key, bytes: [1])) != nil {
                let elapsed = Date().timeIntervalSince(unlockStart)
                Self.log.notice("Fan \(index) manual mode needed Ftst unlock: \(elapsed, format: .fixed(precision: 2))s")
                return
            }
            Thread.sleep(forTimeInterval: unlockTiming.pollInterval)
        }
        Self.log.error("Fan \(index) manual mode unlock timed out")
        throw FanHardwareError.unlockTimeout(index)
    }

    private func modeKey(_ index: Int, in modeControl: ModeControl?) -> String? {
        guard case .perFan(let format) = modeControl else { return nil }
        return String(format: format, index)
    }

    private func isManualMode(fan index: Int) throws -> Bool {
        // Nil means no mode key at all, so never manual; a failed probe is reported.
        let modeControl = try self.modeControl()
        switch modeControl {
        case .perFan:
            return (Self.bytes(of: try store.read(modeKey(index, in: modeControl) ?? "")).first ?? 0) == 1
        case .forceMask:
            return Self.forceMask(from: try store.read(Self.forceMaskKey)) & (1 << UInt16(index)) != 0
        case nil:
            return false
        }
    }

    private func setMode(fan index: Int, manual: Bool) throws {
        let modeControl = try self.modeControl()
        switch modeControl {
        case .perFan:
            try writeBytes(modeKey(index, in: modeControl) ?? "", bytes: [manual ? 1 : 0])
        case .forceMask:
            var mask = Self.forceMask(from: try store.read(Self.forceMaskKey))
            let bit = UInt16(1) << UInt16(index)
            mask = manual ? (mask | bit) : (mask & ~bit)
            try writeBytes(Self.forceMaskKey, bytes: [UInt8(mask >> 8), UInt8(mask & 0xff)])
        case nil:
            throw FanHardwareError.modeKeyMissing
        }
    }

    private static func forceMask(from value: FanBarSMCValue) -> UInt16 {
        let raw = bytes(of: value)
        guard raw.count >= 2 else { return UInt16(raw.first ?? 0) }
        return UInt16(raw[0]) << 8 | UInt16(raw[1])
    }

    /// Nil when the SMC reports every candidate key missing; throws the first
    /// other failure, which says nothing about whether the key exists.
    private static func detectModeControl(in store: SMCKeyStore) throws -> ModeControl? {
        var unanswered: Error?
        func exists(_ key: String) -> Bool {
            do {
                _ = try store.read(key)
                return true
            } catch {
                if (error as? FanHardwareError)?.isKeyNotFound != true, unanswered == nil { unanswered = error }
                return false
            }
        }
        for format in perFanFormats where exists(String(format: format, 0)) {
            return .perFan(format)
        }
        if exists(forceMaskKey) {
            return .forceMask
        }
        if let unanswered {
            log.error("Fan mode key probe failed; will probe again: \(unanswered.localizedDescription, privacy: .public)")
            throw unanswered
        }
        log.error("No fan mode key (F0md/F0Md/FS!) found in SMC")
        return nil
    }

    private static func bytes(of value: FanBarSMCValue) -> [UInt8] {
        withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(min(value.data_size, 32))))
        }
    }

    private func readFloat(_ name: String) throws -> Float {
        let value = try store.read(name)
        let raw = Self.bytes(of: value)
        if value.data_size == 4, raw.count >= 4 {
            return raw.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }
        if value.data_size == 2, raw.count >= 2 {
            return Float(UInt16(raw[0]) << 8 | UInt16(raw[1])) / 4
        }
        throw FanHardwareError.invalidValue(name)
    }

    private func writeFloat(_ name: String, value: Float) throws {
        // A garbage Mn/Mx read must not reach UInt16(_:), which traps on NaN or overflow.
        guard value.isFinite, (0...16_383).contains(value) else { throw FanHardwareError.invalidValue(name) }
        let metadata = try store.read(name)
        let encoded: [UInt8]
        if metadata.data_size == 4 {
            encoded = withUnsafeBytes(of: value) { Array($0) }
        } else if metadata.data_size == 2 {
            let raw = UInt16(max(0, value) * 4)
            encoded = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        } else {
            throw FanHardwareError.invalidValue(name)
        }
        try write(name, metadata: metadata, bytes: encoded)
    }

    private func writeBytes(_ name: String, bytes: [UInt8]) throws {
        let metadata = try store.read(name)
        try write(name, metadata: metadata, bytes: bytes)
    }

    private func write(
        _ name: String,
        metadata: FanBarSMCValue,
        bytes: [UInt8]
    ) throws {
        var value = metadata
        withUnsafeMutableBytes(of: &value.bytes) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in bytes.prefix(Int(value.data_size)).enumerated() {
                buffer[index] = byte
            }
        }
        try store.write(name, value)
    }
}
