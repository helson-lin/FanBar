// Missing sensor or collection evidence is intentionally distinct from false.
// swiftlint:disable discouraged_optional_boolean
import FanBarShared
import Foundation

/// Only allowlisted sensor metadata; no arbitrary system log messages or device identifiers.
struct DiagnosticProbe: Codable, Equatable, Sendable {
    let sensor: String
    let key: String?
    let result: String
    var value: Double?
    var code: Int32?
    var source: String?
    var stage: String?
    var dataType: String?
    var dataSize: Int?
    var rawBytes: String?
    var recognized: Bool?
    /// Fixed HID Product label, e.g. "pACC MTR Temp Sensor0"; `key` stays SMC-only.
    var name: String?
}

struct DiagnosticReport: Encodable {
    let schemaVersion = 1
    /// Random per upload; reuses the compatibility report's ID when sent together with it.
    var diagnosticID: String
    let capturedAt: String
    let device: CompatibilityDevice
    let helperState: String
    var thermal: ThermalReading?
    var fanCount: Int?
    var connectionErrorCode: Int32?
    var probes: [DiagnosticProbe]
    var recentSamples: [DiagnosticSample]?
    var discovery: DiagnosticDiscovery?
    var runtimeEvents: [RuntimeDiagnosticEvent]?
    var crashes: [DiagnosticCrashSummary]?
    var helperLogAvailable: Bool?
    var runtimeContext: DiagnosticRuntimeContext?
    var crashLogAvailable: Bool?
    var helperStateSource: String?
    var runningHelper: DiagnosticRunningHelper?

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct DiagnosticSample: Codable {
    let sampledAt: Date
    let thermal: ThermalReading?
    let fanCount: Int?
    let errorCode: Int32?
    let stage: String
}

struct DiagnosticDiscovery: Codable, Sendable {
    var reportedKeyCount: Int?
    var temperatureKeys: [String] = []
    var scannedKeyCount = 0
    /// The SMC key scan stopped early (deadline or read error); temperatureKeys may be incomplete.
    var truncated = false
    /// The scan finished, but some unrecognized temperature keys were left out of the probe list.
    var probesTruncated = false
    var errorCode: Int32?
}

/// The build the running helper daemon reports, compared with the build this app bundles.
/// A mismatch means a stale daemon survived an update.
struct DiagnosticRunningHelper: Codable, Equatable, Sendable {
    /// reported, noReply, connectionFailed, or notQueried (helper not enabled).
    let status: String
    var build: String?
    var code: Int?

    init(_ query: HelperBuildQuery?) {
        switch query {
        case .reported(let build): status = "reported"; self.build = build
        case .noReply: status = "noReply"
        case .connectionFailed(let code): status = "connectionFailed"; self.code = code
        case nil: status = "notQueried"
        }
    }
}

/// Evidence that can take seconds to gather (unified log, crash files, SMC key scan).
/// Collected off the main actor so the menu bar and windows stay responsive.
struct DiagnosticBackgroundEvidence: Sendable {
    var helperEvents: [RuntimeDiagnosticEvent] = []
    var helperLogAvailable = false
    var crashes: [DiagnosticCrashSummary] = []
    var crashLogAvailable = false
    var thermal: ThermalReading?
    var fanCount: Int?
    var connectionErrorCode: Int32?
    var probes: [DiagnosticProbe] = []
    var discovery: DiagnosticDiscovery?

    /// `makeSource` creates a dedicated reader, so the main actor's client and its
    /// sensor caches are never touched from this thread.
    static func collect(makeSource: @Sendable () throws -> FanReadingSource) -> Self {
        var evidence = Self()
        let helperLogs = RuntimeDiagnostics.helperEvents()
        evidence.helperEvents = helperLogs.events
        evidence.helperLogAvailable = helperLogs.available
        evidence.crashes = DiagnosticCrashReader.summaries()
        evidence.crashLogAvailable = DiagnosticCrashReader.available
        do {
            let source = try makeSource()
            evidence.thermal = source.thermalReading()
            evidence.probes = source.diagnosticProbes()
            evidence.discovery = source.diagnosticDiscovery
            do { evidence.fanCount = try source.fans().count } catch SMCError.unsupportedKey(let key, let code) {
                evidence.probes.append(DiagnosticProbe(sensor: "fan", key: key.count == 4 ? key : nil, result: "readFailed",
                    code: code, source: "smc", stage: key.count == 4 ? "readBytes" : "decode"))
            } catch {
                evidence.probes.append(DiagnosticProbe(sensor: "fan", key: "FNum", result: "readFailed"))
            }
        } catch SMCError.unavailable(let code) {
            evidence.connectionErrorCode = code
        } catch {
            evidence.connectionErrorCode = -1
        }
        return evidence
    }
}

// swiftlint:enable discouraged_optional_boolean
