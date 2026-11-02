// Missing sensor or collection evidence is intentionally distinct from false.
// swiftlint:disable discouraged_optional_boolean
import Darwin
import Foundation

/// A deliberately narrow inventory. Never query serials, UUIDs, users or host names.
struct CompatibilityDevice: Codable, Equatable {
    let modelIdentifier: String
    let processor: String
    let macOSVersion: String
    let appVersion: String
    let helperVersion: String

    static func current(helperVersion: String) -> Self {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return Self(
            modelIdentifier: systemString("hw.model") ?? "unknown",
            processor: systemString("machdep.cpu.brand_string") ?? architecture,
            macOSVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            appVersion: version,
            helperVersion: helperVersion
        )
    }

    var displayName: String {
        Self.modelNames[modelIdentifier] ?? modelIdentifier
    }

    private static let modelNames: [String: String] = {
        guard let url = FanBarResources.url(forResource: "mac-model-names", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return names
    }()

    private static var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }

    private static func systemString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 1024 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        let contents = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: contents, encoding: .utf8)
    }
}

enum CompatibilityStatus: String, Codable {
    case available
    case notApplicable
    case notDetected
    case temporarilyUnavailable
    case requiresAuthorization
    case unverified
    case requestSucceeded
    case requestFailed

    /// A hands-on confirmation may accompany an untested control (used on an earlier
    /// version, for example), but never a result showing control could not run here.
    /// The compatibility service rejects any other combination.
    var acceptsHandsOnConfirmation: Bool {
        self == .requestSucceeded || self == .unverified
    }
}

enum CompatibilityCapability: String, CaseIterable, Codable, Identifiable {
    case cpuTemperature
    case gpuTemperature
    case ssdTemperature
    case batteryTemperature
    case fanReadings
    case manualControl
    case smartCooling

    var id: String { rawValue }
}

struct CompatibilityResult: Codable, Equatable, Identifiable {
    let capability: CompatibilityCapability
    let status: CompatibilityStatus
    let reasonCode: String
    var userConfirmedWorking: Bool?
    /// Only on a failed control request; the service rejects it anywhere else.
    var failure: CompatibilityControlFailure?
    var id: CompatibilityCapability { capability }
}

/// Why a control request failed. Reports cannot be followed up with the submitter,
/// so this has to say enough on its own: fixed codes and bounded numbers, never error text.
struct CompatibilityControlFailure: Codable, Equatable {
    enum Code: String, Codable {
        case smcConnectionFailed = "SMC_CONNECTION_FAILED"
        case smcOperationFailed = "SMC_OPERATION_FAILED"
        case smcInvalidValue = "SMC_INVALID_VALUE"
        case unlockTimeout = "UNLOCK_TIMEOUT"
        case modeKeyMissing = "MODE_KEY_MISSING"
        case invalidRequest = "INVALID_REQUEST"
        case helperTimeout = "HELPER_TIMEOUT"
        case helperConnectionFailed = "HELPER_CONNECTION_FAILED"
        /// The write was accepted, but the fans did not read back as manual.
        case readbackNotManual = "READBACK_NOT_MANUAL"
        /// An older helper's plain-text reply, or an error from outside the helper.
        case helperErrorUnclassified = "HELPER_ERROR_UNCLASSIFIED"
    }

    let code: Code
    var smcKey: String?
    var resultCode: Int32?
    var fanIndex: Int?
    var durationMS: Int?
    var readbackManual: [Bool]?
    var restoredAutomatic: Bool?

    init(code: Code, smcKey: String? = nil, resultCode: Int32? = nil, fanIndex: Int? = nil,
         durationMS: Int? = nil, readbackManual: [Bool]? = nil, restoredAutomatic: Bool? = nil) {
        self.code = code
        self.smcKey = smcKey
        self.resultCode = resultCode
        self.fanIndex = fanIndex
        self.durationMS = durationMS
        // The service requires 1–8 values; an empty readback is omitted rather than sent as [].
        self.readbackManual = readbackManual.flatMap { $0.isEmpty ? nil : Array($0.prefix(8)) }
        self.restoredAutomatic = restoredAutomatic
    }

    init(error: Error) {
        guard let error = error as? HelperClientError else {
            self.init(code: .helperErrorUnclassified)
            return
        }
        if let failure = error.failure {
            self.init(
                code: Code(rawValue: failure.code.rawValue) ?? .helperErrorUnclassified,
                smcKey: failure.smcKey, resultCode: failure.resultCode,
                fanIndex: failure.fanIndex, durationMS: failure.durationMS
            )
        } else {
            let code: Code = error.isTimeout ? .helperTimeout
                : error.isConnectionFailure ? .helperConnectionFailed : .helperErrorUnclassified
            self.init(code: code, resultCode: error.diagnosticCode.flatMap(Int32.init(exactly:)))
        }
    }

    static func readbackNotManual(_ readings: [FanReading]) -> Self {
        Self(code: .readbackNotManual, readbackManual: readings.sorted { $0.index < $1.index }.map(\.isManual))
    }
}

/// One fresh sample; missing values never inherit earlier successful readings.
struct CompatibilityObservation: Equatable {
    let sampledAt: Date
    let thermal: ThermalReading?
    let fanCount: Int?
    let connectionFailed: Bool
}

/// A successful helper reply is evidence of a request, not proof of physical RPM.
enum CompatibilityControlEvidence: String, Codable {
    case unverified
    case requestSucceeded
    case requestFailed
}

struct CompatibilitySnapshot: Equatable {
    let device: CompatibilityDevice
    let checkedAt: Date
    let fanCount: Int?
    let curveSensor: FanCurveSensor
    let results: [CompatibilityResult]

    // Bounded orchestration is covered by failure, cancellation, and restoration tests.
    // swiftlint:disable:next function_body_length
    static func make(
        device: CompatibilityDevice,
        observation: CompatibilityObservation,
        helperState: FanController.HelperState,
        manualEvidence: CompatibilityControlEvidence,
        curveEvidence: CompatibilityControlEvidence,
        manualFailure: CompatibilityControlFailure? = nil,
        curveFailure: CompatibilityControlFailure? = nil,
        curveSensor: FanCurveSensor = .maxChip
    ) -> Self {
        let thermal = observation.thermal
        let readings: [(CompatibilityCapability, Double?)] = [
            (.cpuTemperature, thermal?.cpuCelsius),
            (.gpuTemperature, thermal?.gpuCelsius),
            (.ssdTemperature, thermal?.ssdCelsius),
            (.batteryTemperature, thermal?.batteryCelsius),
        ]
        var results = readings.map { capability, value in
            if capability == .batteryTemperature, thermal?.hasBuiltInBattery == false {
                return CompatibilityResult(capability: capability, status: .notApplicable, reasonCode: "NO_BUILT_IN_BATTERY")
            }
            return CompatibilityResult(
                capability: capability,
                status: value.map { $0.isFinite && (10...120).contains($0) } == true
                    ? .available : observation.connectionFailed ? .temporarilyUnavailable : .notDetected,
                reasonCode: value.map { $0.isFinite && (10...120).contains($0) } == true
                    ? "SENSOR_READ_SUCCEEDED" : observation.connectionFailed ? "SMC_CONNECTION_FAILED" : "SENSOR_NOT_DETECTED"
            )
        }
        results.append(CompatibilityResult(
            capability: .fanReadings,
            status: observation.fanCount.map { $0 > 0 ? .available : .notDetected } ?? .temporarilyUnavailable,
            reasonCode: observation.fanCount.map { $0 > 0 ? "FAN_READ_SUCCEEDED" : "NO_FANS_REPORTED" }
                ?? (observation.connectionFailed ? "SMC_CONNECTION_FAILED" : "FAN_READ_FAILED")
        ))
        for (capability, evidence, failure) in [
            (CompatibilityCapability.manualControl, manualEvidence, manualFailure),
            (.smartCooling, curveEvidence, curveFailure),
        ] {
            let status: CompatibilityStatus
            let reason: String
            if helperState == .unavailable {
                status = .temporarilyUnavailable
                reason = "HELPER_MISSING"
            } else if helperState != .enabled {
                status = .requiresAuthorization
                reason = "HELPER_AUTHORIZATION_REQUIRED"
            } else if observation.fanCount == nil || observation.fanCount == 0 {
                status = .unverified
                reason = "NO_CURRENT_FAN_EVIDENCE"
            } else if capability == .smartCooling,
                      !hasCurveTemperature(curveSensor, results: results) {
                status = .unverified
                reason = "NO_CURVE_SENSOR_EVIDENCE"
            } else {
                switch evidence {
                case .unverified:
                    status = .unverified
                    reason = "CONTROL_NOT_ATTEMPTED"
                case .requestSucceeded:
                    status = .requestSucceeded
                    reason = "CONTROL_REQUEST_SUCCEEDED"
                case .requestFailed:
                    status = .requestFailed
                    reason = "CONTROL_REQUEST_FAILED"
                }
            }
            results.append(CompatibilityResult(capability: capability, status: status, reasonCode: reason,
                failure: status == .requestFailed ? failure : nil))
        }
        return Self(
            device: device, checkedAt: observation.sampledAt, fanCount: observation.fanCount,
            curveSensor: curveSensor, results: results
        )
    }

    private static func hasCurveTemperature(_ sensor: FanCurveSensor, results: [CompatibilityResult]) -> Bool {
        let required: [CompatibilityCapability]
        switch sensor {
        case .maxChip: required = [.cpuTemperature, .gpuTemperature]
        case .cpu: required = [.cpuTemperature]
        case .gpu: required = [.gpuTemperature]
        case .ssd: required = [.ssdTemperature]
        case .battery: required = [.batteryTemperature]
        }
        return results.contains { required.contains($0.capability) && $0.status == .available }
    }
}

/// Closed schema: export cannot accidentally include arbitrary logs or hardware identifiers.
struct CompatibilityReport: Codable {
    let schemaVersion: Int
    let reportID: UUID
    let device: CompatibilityDevice
    let fanCount: Int?
    var capabilities: [CompatibilityResult]
    let selectedTemperatureSource: FanCurveSensor

    init(snapshot: CompatibilitySnapshot) {
        schemaVersion = 1
        reportID = UUID()
        device = snapshot.device
        fanCount = snapshot.fanCount
        capabilities = snapshot.results
        selectedTemperatureSource = snapshot.curveSensor
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct CompatibilityRecord: Codable, Equatable {
    let device: CompatibilityDevice
    let verifiedOn: String
    let source: String
    let notes: String
}

struct CompatibilityCatalog: Codable {
    let schemaVersion: Int
    let records: [CompatibilityRecord]

    static func load() -> Self {
        guard let url = FanBarResources.url(forResource: "compatibility", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.schemaVersion == 1 else {
            return Self(schemaVersion: 1, records: [])
        }
        return catalog
    }

    /// Exact model/OS/app/helper versions prevent a nearby record implying support.
    func matching(_ device: CompatibilityDevice) -> [CompatibilityRecord] {
        records.filter {
            $0.device.modelIdentifier == device.modelIdentifier
                && $0.device.macOSVersion == device.macOSVersion
                && $0.device.appVersion == device.appVersion
                && $0.device.helperVersion == device.helperVersion
        }
    }
}

/// Locates the SwiftPM resource bundle without `Bundle.module`, which traps when the
/// bundle is missing. Single-architecture `swift build` products only search beside
/// the .app and the CI build directory, never Contents/Resources (issue #86).
enum FanBarResources {
    private final class BundleFinder {}

    static let bundle: Bundle? = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            // `swift test` places the bundle beside the .xctest product.
            Bundle(for: BundleFinder.self).bundleURL.deletingLastPathComponent(),
        ]
        for case let directory? in candidates {
            if let bundle = Bundle(url: directory.appendingPathComponent("FanBar_FanBar.bundle")) {
                return bundle
            }
        }
        return nil
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle?.url(forResource: name, withExtension: ext)
    }
}

// swiftlint:enable discouraged_optional_boolean
