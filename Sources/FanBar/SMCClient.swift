// Missing sensor or collection evidence is intentionally distinct from false.
// swiftlint:disable discouraged_optional_boolean
import AppleSMC
import FanBarShared
import Foundation

enum SMCError: LocalizedError {
    case unavailable(Int32)
    case unsupportedKey(String, Int32)
    case writeFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable(let code): fanBarFormat(
            "无法连接 AppleSMC（错误 %d）。",
            "Unable to connect to AppleSMC (error %d).",
            code
        )
        case .unsupportedKey(let key, let code): fanBarFormat(
            "此 Mac 不支持 SMC 键 %@（错误 %d）。",
            "This Mac does not support SMC key %@ (error %d).",
            key,
            code
        )
        case .writeFailed(let key, let code): fanBarFormat(
            "无法写入 %@（错误 %d）。",
            "Unable to write %@ (error %d).",
            key,
            code
        )
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

struct ThermalReading: Codable, Equatable, Sendable {
    let sampledAt: Date
    /// Average of the CPU sensors. Fan curves, alerts, and the CSV log use this
    /// steadier value, so the hottest-core reading cannot change control behavior.
    let cpuCelsius: Double?
    /// The hottest sampled CPU sensor. Display only;
    /// nil in history saved before it existed.
    let cpuHottestCelsius: Double?
    let gpuCelsius: Double?
    let ssdCelsius: Double?
    let batteryCelsius: Double?
    let hasBuiltInBattery: Bool?
    /// Whole-system power from SMC `PSTR`, already checked for plausibility.
    /// Nil on Macs without the key and in history saved before it existed.
    let systemWatts: Double?

    init(
        sampledAt: Date,
        cpuCelsius: Double?,
        gpuCelsius: Double?,
        ssdCelsius: Double? = nil,
        batteryCelsius: Double? = nil,
        hasBuiltInBattery: Bool? = nil,
        cpuHottestCelsius: Double? = nil,
        systemWatts: Double? = nil
    ) {
        self.sampledAt = sampledAt
        self.systemWatts = SystemPowerReadout.plausible(systemWatts)
        self.cpuCelsius = cpuCelsius
        self.cpuHottestCelsius = cpuHottestCelsius
        self.gpuCelsius = gpuCelsius
        self.ssdCelsius = ssdCelsius
        self.batteryCelsius = batteryCelsius
        self.hasBuiltInBattery = hasBuiltInBattery
    }

    /// The CPU temperature people see: the hottest core when known, else the average.
    var cpuDisplayCelsius: Double? { cpuHottestCelsius ?? cpuCelsius }

    var cpuTemperatureSummary: String {
        func label(_ value: Double?) -> String {
            value.map { "\(Int($0.rounded()))°C" } ?? "—"
        }
        return fanBarFormat(
            "CPU 平均 %@ · 最高 %@", "CPU average %@ · highest %@",
            label(cpuCelsius), label(cpuHottestCelsius)
        )
    }
}

/// Unprivileged fan and temperature readings. `SMCClient` reads the real SMC;
/// tests substitute fixed readings so the UI can run on Macs without fans.
protocol FanReadingSource: AnyObject {
    func fans() throws -> [FanReading]
    func thermalReading(at date: Date) -> ThermalReading
    func diagnosticProbes() -> [DiagnosticProbe]
    var diagnosticDiscovery: DiagnosticDiscovery? { get }
}

extension FanReadingSource {
    func diagnosticProbes() -> [DiagnosticProbe] {
        []
    }

    var diagnosticDiscovery: DiagnosticDiscovery? { nil }

    func thermalReading() -> ThermalReading {
        thermalReading(at: Date())
    }
}

final class SMCClient: FanReadingSource {
    private let cpuCandidates: [String]
    private var cpuTemperatureKeys: [String]?
    private var gpuTemperatureKeys: [String]?
    private var ssdTemperatureKeys: [String]?
    private var batteryTemperatureKeys: [String]?
    private var lastKeyProbe = Date.distantPast
    private var systemPowerPacer = SMCOptionalKeyPacer(retryInterval: emptyProbeRetryInterval)
    /// Sensors of a powered-down block can be missing at launch, so an empty
    /// probe result is retried instead of being cached for the whole session.
    private static let emptyProbeRetryInterval: TimeInterval = 30

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

    /// M4-family CPU thermal zones from the Stats catalogue. Never merge these
    /// with other generations: a readable key alone does not identify its role.
    static func cpuTemperatureCandidates(for processor: String) -> [String] {
        switch processor {
        case "Apple M4", "Apple M4 Pro", "Apple M4 Max":
            return [
                "Te05", "Te0S", "Te09", "Te0H",
                "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
            ]
        case let name where name.hasPrefix("Intel"):
            return intelCoreTemperatureKeys + cpuTemperatureCandidates
        default:
            return cpuTemperatureCandidates
        }
    }

    /// Intel per-core digital sensors, e.g. TC1C for core 1 on MacBookPro16,3.
    private static let intelCoreTemperatureKeys = (0..<10).map { "TC\($0)C" }

    /// Per-core sensors measure the dies themselves. When any are readable,
    /// package and proximity keys (TC0P sits beside the CPU) only dilute them.
    static func preferredCPUKeys(_ readable: [String]) -> [String] {
        let cores = readable.filter(intelCoreTemperatureKeys.contains)
        return cores.isEmpty ? readable : cores
    }

    private static let gpuTemperatureCandidates = [
        "TCGC", "TG0D", "TGDD", "TG0H", "TG0P",
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0k",
        "Tg0U", "Tg0X", "Tg0g", "Tg1Y", "Tg1c", "Tg1g"
    ]

    // These labels are not part of Apple's public SMC API. Intel generations
    // use different A/B/C/P/V suffixes, so probe the complete common family.
    private static let ssdTemperatureCandidates = (0..<10).flatMap { index in
        ["TH\(index)A", "TH\(index)B", "TH\(index)C", "TH\(index)P", "TH\(index)V"]
    }

    private static let batteryTemperatureCandidates = [
        "TB0T", "TB1T", "TB2T", "TB3T", "TB4T", "TB5T", "TB6T", "TB7T"
    ]

    // AppleSMC keys use a four-byte ASCII code, such as F0Ac for fan 0 actual RPM.
    private func key(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    init() throws {
        cpuCandidates = Self.cpuTemperatureCandidates(
            for: CompatibilityDevice.current(helperVersion: "unknown").processor
        )
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
        return try Self.rpm(dataSize: Int(value.data_size), bytes: bytes)
    }

    static func rpm(dataSize: Int, bytes: [UInt8]) throws -> Int {
        if dataSize == 4, bytes.count >= 4 {
            // Int(_:) traps on NaN or out-of-range values; treat them as a failed read.
            let rpm = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }.rounded()
            guard rpm.isFinite, (0...100_000).contains(rpm) else { throw SMCError.unsupportedKey("RPM", -1) }
            return Int(rpm)
        }
        if dataSize == 2, bytes.count >= 2 {
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

    private func isTemperatureKey(_ key: String) -> Bool {
        guard let value = try? read(key) else { return false }
        return temperature(value) != nil
    }

    private func temperatures(
        cachedKeys: inout [String]?,
        candidates: [String],
        select: ([String]) -> [String] = { $0 }
    ) -> [Double] {
        if cachedKeys?.isEmpty == true,
           Date().timeIntervalSince(lastKeyProbe) >= Self.emptyProbeRetryInterval {
            cachedKeys = nil
        }
        if cachedKeys == nil {
            // Keep any key that decodes as a temperature, even if the current
            // value is out of range (an idle GPU can read near 0 °C).
            cachedKeys = select(candidates.filter { isTemperatureKey($0) })
            lastKeyProbe = Date()
        }
        return (cachedKeys ?? []).compactMap(validTemperature)
    }

    /// Desktops and some Intel Macs have no `PSTR`; those read as nil.
    private func systemPowerWatts(at date: Date) -> Double? {
        guard systemPowerPacer.shouldRead(at: date) else { return nil }
        let watts = (try? read("PSTR")).flatMap { value in
            let bytes = withUnsafeBytes(of: value.bytes) {
                Array($0.prefix(Int(min(value.data_size, 32))))
            }
            return SMCPowerDecoder.watts(dataType: SMCPowerDecoder.typeName(value.data_type), bytes: bytes)
        }
        systemPowerPacer.record(found: watts != nil, at: date)
        return watts
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func nvmeTemperature() -> Double? {
        var celsius = 0.0
        guard fanbar_nvme_temperature(&celsius) == 0 else { return nil }
        return celsius
    }

    private func embeddedNVMeTemperature() -> Double? {
        var celsius = 0.0
        guard fanbar_embedded_nvme_temperature(&celsius) == 0 else { return nil }
        return celsius
    }

    private(set) var diagnosticDiscovery: DiagnosticDiscovery?

    // Only explicit diagnostics enumerate keys. Normal telemetry retains its existing fast path.
    // swiftlint:disable:next cyclomatic_complexity
    func diagnosticProbes() -> [DiagnosticProbe] {
        var probes: [DiagnosticProbe] = []
        var known = Set<String>()
        for (sensor, candidates) in [
            ("cpu", cpuCandidates), ("gpu", Self.gpuTemperatureCandidates),
            ("ssd", Self.ssdTemperatureCandidates), ("battery", Self.batteryTemperatureCandidates),
        ] {
            for name in candidates {
                known.insert(name)
                probes.append(diagnosticProbe(name, sensor: sensor, recognized: true))
            }
        }
        var discovery = DiagnosticDiscovery()
        var unrecognized: [DiagnosticProbe] = []
        do {
            let countValue = try read("#KEY")
            let bytes = withUnsafeBytes(of: countValue.bytes) { Array($0.prefix(4)) }
            let count = bytes.reduce(0) { ($0 << 8) | Int($1) }
            discovery.reportedKeyCount = count
            let started = ProcessInfo.processInfo.systemUptime
            for index in 0..<min(count, 4096) {
                if ProcessInfo.processInfo.systemUptime - started > 1.5 {
                    discovery.truncated = true
                    break
                }
                var code: UInt32 = 0
                let result = fanbar_smc_key_at_index(UInt32(index), &code)
                guard result == 0 else { discovery.errorCode = result; break }
                discovery.scannedKeyCount += 1
                let bytes = [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)]
                // Upload only temperature-key names, never arbitrary SMC inventory values.
                guard bytes.first == 84, bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
                      let name = String(bytes: bytes, encoding: .ascii) else { continue }
                if discovery.temperatureKeys.count < 512 { discovery.temperatureKeys.append(name) }
                if !known.contains(name) { unrecognized.append(diagnosticProbe(name, sensor: "unclassified", recognized: false)) }
            }
            if discovery.scannedKeyCount < count { discovery.truncated = true }
        } catch SMCError.unsupportedKey(_, let code) { discovery.errorCode = code } catch { discovery.errorCode = -1 }
        // Keep the complete bounded key-name inventory, prioritizing useful numeric evidence in the payload.
        let priority = ["available": 0, "unsupportedFormat": 1, "outOfRange": 2, "readFailed": 3]
        let remaining = max(0, 240 - probes.count)
        probes += unrecognized.sorted {
            let lhs = priority[$0.result] ?? 4, rhs = priority[$1.result] ?? 4
            return lhs == rhs ? ($0.key ?? "") < ($1.key ?? "") : lhs < rhs
        }.prefix(remaining)
        if unrecognized.count > remaining { discovery.probesTruncated = true }
        diagnosticDiscovery = discovery
        for (source, readTemperature) in [
            ("embeddedNVMe", fanbar_embedded_nvme_temperature), ("nvmeSMART", fanbar_nvme_temperature),
        ] {
            var value = 0.0
            let code = readTemperature(&value)
            probes.append(DiagnosticProbe(sensor: "ssd", key: nil, result: code == 0 ? "available" : "readFailed",
                value: code == 0 && value.isFinite ? value : nil, code: code, source: source, stage: "fallback"))
        }
        probes += BatteryTemperatureReader.diagnosticProbes()
        probes += Self.hidProbes(HIDTemperatureReader.all())
        return probes
    }

    /// HID sensors are listed by their fixed Product label, bounded to 64.
    static func hidProbes(_ sensors: [HIDTemperature]?) -> [DiagnosticProbe] {
        guard let sensors else {
            return [DiagnosticProbe(sensor: "unclassified", key: nil, result: "serviceMissing", source: "hid", stage: "serviceMatch")]
        }
        return sensors.filter { HIDTemperatureSelector.isUploadableName($0.name) }
            .sorted { $0.name < $1.name }
            .prefix(64)
            .map { sensor in
                let result: String
                if let celsius = sensor.celsius {
                    result = (10...120).contains(celsius) ? "available" : "outOfRange"
                } else { result = "readFailed" }
                var probe = DiagnosticProbe(sensor: HIDTemperatureSelector.category(of: sensor.name), key: nil, result: result,
                    value: sensor.celsius, source: "hid", stage: "readEvent",
                    recognized: HIDTemperatureSelector.isRecognized(sensor.name))
                probe.name = sensor.name
                return probe
            }
    }

    private func diagnosticProbe(_ name: String, sensor: String, recognized: Bool) -> DiagnosticProbe {
        var raw = FanBarSMCValue()
        var stage: Int32 = 0
        let code = fanbar_smc_read_diagnostic(key(name), &raw, &stage)
        let decoded = code == 0 ? temperature(raw) : nil
        let value = decoded.flatMap { $0.isFinite ? $0 : nil }
        let result: String
        if code != 0 { result = "readFailed" } else if let value {
            result = (10...120).contains(value) ? "available" : "outOfRange"
        } else { result = "unsupportedFormat" }
        let bytes = withUnsafeBytes(of: raw.bytes) { Array($0.prefix(Int(min(raw.data_size, 8)))) }
        return DiagnosticProbe(sensor: sensor, key: name, result: result, value: value, code: code,
            source: "smc", stage: stage == 1 ? "keyInfo" : "readBytes",
            dataType: stage == 2 ? String(format: "%08x", raw.data_type) : nil,
            dataSize: stage == 2 ? Int(raw.data_size) : nil,
            rawBytes: code == 0 ? bytes.map { String(format: "%02x", $0) }.joined() : nil, recognized: recognized)
    }

    func fans() throws -> [FanReading] {
        let countValue = try read("FNum")
        let count = Int(countValue.bytes.0)
        guard (0...8).contains(count) else { throw SMCError.unsupportedKey("FNum", -1) }
        return try (0..<count).map { index in
            FanReading(index: index,
                       minimumRPM: try rpm(read("F\(index)Mn")),
                       currentRPM: try rpm(read("F\(index)Ac")),
                       maximumRPM: try rpm(read("F\(index)Mx")),
                       isManual: false)
        }
    }

    func thermalReading(at date: Date = Date()) -> ThermalReading {
        var cpuValues = temperatures(
            cachedKeys: &cpuTemperatureKeys,
            candidates: cpuCandidates,
            select: Self.preferredCPUKeys
        )
        var gpuValues = temperatures(
            cachedKeys: &gpuTemperatureKeys,
            candidates: Self.gpuTemperatureCandidates
        )
        // Some Apple Silicon Macs expose no readable SMC CPU/GPU keys; their
        // HID sensors still answer. Only read them when SMC came up empty.
        if cpuValues.isEmpty || gpuValues.isEmpty, let sensors = HIDTemperatureReader.all() {
            if cpuValues.isEmpty { cpuValues = HIDTemperatureSelector.cpu(sensors) }
            if gpuValues.isEmpty { gpuValues = HIDTemperatureSelector.gpu(sensors) }
        }
        let ssdValues = temperatures(
            cachedKeys: &ssdTemperatureKeys,
            candidates: Self.ssdTemperatureCandidates
        )
        let batteryValues = temperatures(
            cachedKeys: &batteryTemperatureKeys,
            candidates: Self.batteryTemperatureCandidates
        )
        return ThermalReading(
            sampledAt: date,
            cpuCelsius: average(cpuValues),
            gpuCelsius: average(gpuValues),
            // Preserve Intel SMC readings, then use Apple Silicon's embedded
            // NAND HID sensors, with standard NVMe SMART as the final fallback.
            ssdCelsius: StorageTemperatureResolver.resolve(
                smcValues: ssdValues,
                embeddedNVMe: embeddedNVMeTemperature,
                smart: nvmeTemperature
            ),
            batteryCelsius: BatteryTemperatureResolver.resolve(
                smcValues: batteryValues,
                smartBattery: BatteryTemperatureReader.smartBattery,
                batteryPack: BatteryTemperatureReader.batteryPack
            ),
            hasBuiltInBattery: BatteryTemperatureReader.hasBuiltInBattery(),
            cpuHottestCelsius: cpuValues.max(),
            systemWatts: systemPowerWatts(at: date)
        )
    }
}

enum StorageTemperatureResolver {
    /// Keeps source selection deterministic across Intel and Apple Silicon,
    /// and avoids touching slower fallback APIs when an earlier source works.
    static func resolve(
        smcValues: [Double],
        embeddedNVMe: () -> Double?,
        smart: () -> Double?
    ) -> Double? {
        if !smcValues.isEmpty {
            return smcValues.reduce(0, +) / Double(smcValues.count)
        }
        return embeddedNVMe() ?? smart()
    }
}

// swiftlint:enable discouraged_optional_boolean
