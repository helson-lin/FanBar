import AppleSMC
import Foundation

enum SMCError: LocalizedError {
    case unavailable(Int32)
    case unsupportedKey(String, Int32)
    case writeFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable(let code): "无法连接 AppleSMC（错误 \(code)）。"
        case .unsupportedKey(let key, let code): "此 Mac 不支持 SMC 键 \(key)（错误 \(code)）。"
        case .writeFailed(let key, let code): "无法写入 \(key)（错误 \(code)）。"
        }
    }
}

struct FanReading: Identifiable {
    let index: Int
    let minimumRPM: Int
    let currentRPM: Int
    let maximumRPM: Int
    let isManual: Bool
    var id: Int { index }
}

struct ThermalReading {
    let sampledAt: Date
    let cpuCelsius: Double?
    let gpuCelsius: Double?
}

final class SMCClient {
    private var cpuTemperatureKeys: [String]?
    private var gpuTemperatureKeys: [String]?

    // Common Intel and Apple Silicon keys, derived from the MIT-licensed
    // exelban/Stats sensor catalogue.
    private static let cpuTemperatureCandidates = [
        "TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R",
        "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]

    private static let gpuTemperatureCandidates = [
        "TCGC", "TG0D", "TGDD", "TG0H", "TG0P",
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0k",
        "Tg0U", "Tg0X", "Tg0g", "Tg1Y", "Tg1c", "Tg1g"
    ]

    // AppleSMC keys use a four-byte ASCII code, such as F0Ac for fan 0 actual RPM.
    private func key(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    init() throws {
        let result = fanbar_smc_open()
        guard result == 0 else { throw SMCError.unavailable(result) }
    }

    deinit { fanbar_smc_close() }

    private func read(_ name: String) throws -> FanBarSMCValue {
        var value = FanBarSMCValue()
        let result = fanbar_smc_read(key(name), &value)
        guard result == 0 else { throw SMCError.unsupportedKey(name, result) }
        return value
    }

    // Apple Silicon uses native-endian Float32; Intel uses big-endian fpe2.
    private func rpm(_ value: FanBarSMCValue) throws -> Int {
        let bytes = withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(min(value.data_size, 32))))
        }
        if value.data_size == 4, bytes.count >= 4 {
            return Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }.rounded())
        }
        if value.data_size == 2, bytes.count >= 2 {
            return Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        }
        throw SMCError.unsupportedKey("RPM", -1)
    }

    private func temperature(_ value: FanBarSMCValue) -> Double? {
        let bytes = withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(min(value.data_size, 32))))
        }

        if value.data_type == key("flt "), bytes.count >= 4 {
            return Double(bytes.withUnsafeBytes {
                $0.loadUnaligned(as: Float.self)
            })
        }

        if value.data_type == key("sp78"), bytes.count >= 2 {
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        }

        return nil
    }

    private func validTemperature(for key: String) -> Double? {
        guard let value = try? read(key),
              let celsius = temperature(value),
              (10...120).contains(celsius) else {
            return nil
        }
        return celsius
    }

    private func temperatures(
        cachedKeys: inout [String]?,
        candidates: [String]
    ) -> [Double] {
        if cachedKeys == nil {
            // Probe once; later samples only touch sensors exposed by this Mac.
            cachedKeys = candidates.filter { validTemperature(for: $0) != nil }
        }
        return (cachedKeys ?? []).compactMap(validTemperature)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func fans() throws -> [FanReading] {
        let countValue = try read("FNum")
        let count = Int(countValue.bytes.0)
        guard (1...8).contains(count) else { throw SMCError.unsupportedKey("FNum", -1) }
        return try (0..<count).map { index in
            FanReading(index: index,
                       minimumRPM: try rpm(read("F\(index)Mn")),
                       currentRPM: try rpm(read("F\(index)Ac")),
                       maximumRPM: try rpm(read("F\(index)Mx")),
                       isManual: false)
        }
    }

    func thermalReading(at date: Date = Date()) -> ThermalReading {
        let cpuValues = temperatures(
            cachedKeys: &cpuTemperatureKeys,
            candidates: Self.cpuTemperatureCandidates
        )
        let gpuValues = temperatures(
            cachedKeys: &gpuTemperatureKeys,
            candidates: Self.gpuTemperatureCandidates
        )
        return ThermalReading(
            sampledAt: date,
            cpuCelsius: average(cpuValues),
            gpuCelsius: average(gpuValues)
        )
    }
}
