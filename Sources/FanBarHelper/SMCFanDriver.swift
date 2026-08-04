import AppleSMC
import FanBarShared
import Foundation

enum FanHardwareError: LocalizedError {
    case unavailable(Int32)
    case operation(String, Int32)
    case invalidValue(String)
    case unlockTimeout(Int)

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
        }
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
    private let modeKeyFormat: String
    private let hasForceTest: Bool

    init() throws {
        let result = fanbar_smc_open()
        guard result == 0 else { throw FanHardwareError.unavailable(result) }
        modeKeyFormat = SMCFanDriver.detectModeKey()
        hasForceTest = (try? SMCFanDriver.read("Ftst")) != nil
    }

    deinit {
        // Returning to system policy is more important than preserving a manual preset.
        try? restoreAutomatic()
        fanbar_smc_close()
    }

    func fans() throws -> [HardwareFan] {
        let countValue = try Self.read("FNum")
        let count = Int(Self.bytes(of: countValue).first ?? 0)
        guard (1...8).contains(count) else {
            throw FanHardwareError.invalidValue("FNum")
        }

        return try (0..<count).map { index in
            let mode = try Self.read(modeKey(index))
            return HardwareFan(
                index: index,
                actual: try Self.readFloat("F\(index)Ac"),
                target: try Self.readFloat("F\(index)Tg"),
                minimum: try Self.readFloat("F\(index)Mn"),
                maximum: try Self.readFloat("F\(index)Mx"),
                isManual: (Self.bytes(of: mode).first ?? 0) == 1
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
        guard fraction.isFinite, (0.30...1.00).contains(fraction) else {
            throw FanHardwareError.invalidValue(fanBarText("散热比例", "cooling fraction"))
        }
        let snapshot = try fans()
        try setFans(snapshot) { fan in
            // Each fan has its own maximum; round to a stable whole-RPM target.
            min(
                max((fan.maximum * fraction).rounded(), fan.minimum),
                fan.maximum
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
                try Self.writeFloat("F\(fan.index)Tg", value: target(fan))
            }
        } catch {
            // A partial multi-fan transition is unsafe; roll the whole machine back.
            try? restoreAutomatic()
            throw error
        }
    }

    func restoreAutomatic() throws {
        let countValue = try Self.read("FNum")
        let count = Int(Self.bytes(of: countValue).first ?? 0)
        guard (1...8).contains(count) else {
            throw FanHardwareError.invalidValue("FNum")
        }

        var firstError: Error?
        for index in 0..<count {
            do {
                try Self.writeBytes(modeKey(index), bytes: [0])
                try Self.writeFloat("F\(index)Tg", value: 0)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if hasForceTest {
            do {
                try Self.writeBytes("Ftst", bytes: [0])
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func enableManualMode(fan index: Int) throws {
        let key = modeKey(index)
        if (try? Self.writeBytes(key, bytes: [1])) != nil {
            return
        }
        guard hasForceTest else {
            throw FanHardwareError.operation(key, -1)
        }

        try Self.writeBytes("Ftst", bytes: [1])
        Thread.sleep(forTimeInterval: 0.5)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? Self.writeBytes(key, bytes: [1])) != nil {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw FanHardwareError.unlockTimeout(index)
    }

    private func modeKey(_ index: Int) -> String {
        String(format: modeKeyFormat, index)
    }

    private static func detectModeKey() -> String {
        for format in ["F%dmd", "F%dMd"] {
            let candidate = String(format: format, 0)
            if (try? read(candidate)) != nil {
                return format
            }
        }
        return "F%dMd"
    }

    private static func key(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func read(_ name: String) throws -> FanBarSMCValue {
        var value = FanBarSMCValue()
        let result = fanbar_smc_read(key(name), &value)
        guard result == 0 else { throw FanHardwareError.operation(name, result) }
        return value
    }

    private static func bytes(of value: FanBarSMCValue) -> [UInt8] {
        withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(min(value.data_size, 32))))
        }
    }

    private static func readFloat(_ name: String) throws -> Float {
        let value = try read(name)
        let raw = bytes(of: value)
        if value.data_size == 4, raw.count >= 4 {
            return raw.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }
        if value.data_size == 2, raw.count >= 2 {
            return Float(UInt16(raw[0]) << 8 | UInt16(raw[1])) / 4
        }
        throw FanHardwareError.invalidValue(name)
    }

    private static func writeFloat(_ name: String, value: Float) throws {
        let metadata = try read(name)
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

    private static func writeBytes(_ name: String, bytes: [UInt8]) throws {
        let metadata = try read(name)
        try write(name, metadata: metadata, bytes: bytes)
    }

    private static func write(
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
        let result = fanbar_smc_write(key(name), &value)
        guard result == 0 else { throw FanHardwareError.operation(name, result) }
    }
}
