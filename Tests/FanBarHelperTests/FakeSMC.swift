import AppleSMC
import Foundation
@testable import FanBarHelper

/// In-memory SMC key table that mimics the behaviors SMCFanDriver depends on.
final class FakeSMC: SMCKeyStore, @unchecked Sendable {
    struct Fan {
        var minimum: Float
        var maximum: Float
        var actual: Float
    }

    enum Encoding {
        /// Apple Silicon: little-endian Float32 (`flt `).
        case float32
        /// Older Intel: unsigned fixed point with two fraction bits (`fpe2`).
        case fpe2
    }

    private let lock = NSLock()
    private var keys: [String: FanBarSMCValue] = [:]
    private var log: [(key: String, bytes: [UInt8])] = []
    private var failures: [String: Int32] = [:]
    private var readFailures: [String: Int32] = [:]
    private var passingReadFailures: [String: (code: Int32, remaining: Int)] = [:]
    private let encoding: Encoding

    /// Apple Silicon refuses `F%dmd = 1` until `Ftst` is set.
    var manualModeRequiresForceTest = false
    /// The mode key never accepts manual mode (unlock never succeeds).
    var rejectsManualMode = false

    private init(fans: [Fan], encoding: Encoding) {
        self.encoding = encoding
        keys["FNum"] = Self.value([UInt8(fans.count)])
        for (index, fan) in fans.enumerated() {
            keys["F\(index)Ac"] = encode(fan.actual)
            keys["F\(index)Tg"] = encode(0)
            keys["F\(index)Mn"] = encode(fan.minimum)
            keys["F\(index)Mx"] = encode(fan.maximum)
        }
    }

    /// Per-fan mode bytes (`F%dmd`) and, optionally, the `Ftst` unlock key.
    static func appleSilicon(
        fans: [Fan] = [Fan(minimum: 1_200, maximum: 6_000, actual: 1_500), Fan(minimum: 1_300, maximum: 6_500, actual: 1_600)],
        modeKeyFormat: String = "F%dmd",
        forceTest: Bool = true
    ) -> FakeSMC {
        let smc = FakeSMC(fans: fans, encoding: .float32)
        for index in fans.indices {
            smc.keys[String(format: modeKeyFormat, index)] = value([0])
        }
        if forceTest {
            smc.keys["Ftst"] = value([0])
        }
        return smc
    }

    /// Older Intel Macs: one `FS! ` bitmask for every fan, fpe2 RPM values.
    static func intelForceMask(
        fans: [Fan] = [Fan(minimum: 1_200, maximum: 5_500, actual: 1_800), Fan(minimum: 1_000, maximum: 5_000, actual: 1_700)]
    ) -> FakeSMC {
        let smc = FakeSMC(fans: fans, encoding: .fpe2)
        smc.keys[SMCFanDriver.forceMaskKey] = value([0, 0])
        return smc
    }

    /// A Mac exposing fan readings but no way to switch to manual mode.
    static func withoutModeKey() -> FakeSMC {
        FakeSMC(fans: [Fan(minimum: 1_200, maximum: 6_000, actual: 1_500)], encoding: .float32)
    }

    // MARK: SMCKeyStore

    func read(_ name: String) throws -> FanBarSMCValue {
        try lock.withLock {
            if let code = readFailures[name] { throw FanHardwareError.operation(name, code) }
            if let failure = passingReadFailures[name], failure.remaining > 0 {
                passingReadFailures[name] = (failure.code, failure.remaining - 1)
                throw FanHardwareError.operation(name, failure.code)
            }
            guard let value = keys[name] else { throw FanHardwareError.operation(name, FanHardwareError.keyNotFoundCode) }
            return value
        }
    }

    func write(_ name: String, _ value: FanBarSMCValue) throws {
        try lock.withLock {
            let bytes = Self.bytes(of: value)
            log.append((name, bytes))
            if let code = failures[name] {
                throw FanHardwareError.operation(name, code)
            }
            if isModeKey(name), bytes.first == 1 {
                let unlocked = Self.bytes(of: keys["Ftst"] ?? Self.value([0])).first == 1
                if rejectsManualMode || (manualModeRequiresForceTest && !unlocked) {
                    throw FanHardwareError.operation(name, 130)
                }
            }
            keys[name] = value
        }
    }

    // MARK: Test controls and inspection

    func failWrites(to name: String, code: Int32) {
        lock.withLock { failures[name] = code }
    }

    /// Reads of `name` fail with `code`; a nil code lets them through again.
    func failReads(of name: String, code: Int32?) {
        lock.withLock { readFailures[name] = code }
    }

    /// Only the next `count` reads of `name` fail, as an SMC that is slow for a moment.
    func failNextReads(of name: String, count: Int, code: Int32) {
        lock.withLock { passingReadFailures[name] = (code, count) }
    }

    func set(_ name: String, bytes: [UInt8]) {
        lock.withLock { keys[name] = Self.value(bytes) }
    }

    func set(_ name: String, rpm: Float) {
        lock.withLock { keys[name] = encode(rpm) }
    }

    func bytes(_ name: String) -> [UInt8] {
        lock.withLock { keys[name].map(Self.bytes(of:)) ?? [] }
    }

    func rpm(_ name: String) -> Float {
        let raw = bytes(name)
        switch encoding {
        case .float32:
            return raw.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        case .fpe2:
            return Float(UInt16(raw[0]) << 8 | UInt16(raw[1])) / 4
        }
    }

    var forceMask: UInt16 {
        let raw = bytes(SMCFanDriver.forceMaskKey)
        return UInt16(raw[0]) << 8 | UInt16(raw[1])
    }

    var writtenKeys: [String] {
        lock.withLock { log.map(\.key) }
    }

    // MARK: Encoding

    private func isModeKey(_ name: String) -> Bool {
        name.count == 4 && name.hasPrefix("F") && (name.hasSuffix("md") || name.hasSuffix("Md"))
    }

    private func encode(_ rpm: Float) -> FanBarSMCValue {
        switch encoding {
        case .float32:
            return Self.value(withUnsafeBytes(of: rpm) { Array($0) })
        case .fpe2:
            let raw = UInt16(rpm * 4)
            return Self.value([UInt8(raw >> 8), UInt8(raw & 0xff)])
        }
    }

    static func value(_ bytes: [UInt8]) -> FanBarSMCValue {
        var value = FanBarSMCValue()
        value.data_size = UInt32(bytes.count)
        withUnsafeMutableBytes(of: &value.bytes) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
        }
        return value
    }

    static func bytes(of value: FanBarSMCValue) -> [UInt8] {
        withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.data_size))) }
    }
}
