// Missing sensor or collection evidence is intentionally distinct from false.
// swiftlint:disable discouraged_optional_boolean
import Darwin
import Foundation
import os

public enum DiagnosticRequestContext {
    @TaskLocal public static var id: String?
}

public struct RuntimeDiagnosticEvent: Codable, Sendable {
    public enum Component: String, Codable, Sendable { case app, service, xpc, control, helper }
    public enum Action: String, Codable, Sendable {
        case startup, controllerReady, menuReady, shutdown, previousExitUnknown
        case status, register, unregister, openSettings, connect, interrupted, invalidated, timeout
        case fixedRPM, preset, curve, restoreAutomatic, fanCount, fanRead, readback, recovery, authorize
    }

    public enum Outcome: String, Codable, Sendable {
        case observed, started, succeeded, failed, enabled, requiresApproval, notRegistered, unavailable, accepted, rejected
    }

    public let timestamp: Date
    public let sessionID: String
    public let requestID: String?
    public let component: Component
    public let action: Action
    public let outcome: Outcome
    public let code: Int?
    public let value: Double?
    public let durationMS: Double?
    public let fanIndex: Int?
    public let manual: Bool?
}

/// Bounded, sanitized, local-only evidence. No arbitrary error descriptions or paths.
public final class RuntimeDiagnostics: @unchecked Sendable {
    public static let shared = RuntimeDiagnostics()
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FanBar/Diagnostics/runtime.json")
    }

    private static let log = Logger(subsystem: "local.fanbar.diagnostics", category: "events")
    private let lock = NSLock()
    private let url: URL?
    private let sessionID = UUID().uuidString.lowercased()
    private var events: [RuntimeDiagnosticEvent]

    public init(url: URL? = Bundle.main.bundleIdentifier == "local.fanbar.app" ? RuntimeDiagnostics.defaultURL : nil) {
        self.url = url
        events = url.flatMap { url -> Data? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 131072 else { return nil }
            return try? Data(contentsOf: url)
        }.flatMap { try? JSONDecoder().decode([RuntimeDiagnosticEvent].self, from: $0) } ?? []
        events = Array(events.filter { Date().timeIntervalSince($0.timestamp) <= 86400 }.suffix(256))
    }

    public func record(_ component: RuntimeDiagnosticEvent.Component, _ action: RuntimeDiagnosticEvent.Action,
                       _ outcome: RuntimeDiagnosticEvent.Outcome, requestID: String? = nil, code: Int? = nil,
                       value: Double? = nil, durationMS: Double? = nil, fanIndex: Int? = nil, manual: Bool? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let event = RuntimeDiagnosticEvent(timestamp: Date(), sessionID: sessionID, requestID: requestID ?? DiagnosticRequestContext.id,
            component: component, action: action, outcome: outcome, code: code,
            value: value.flatMap { $0.isFinite ? $0 : nil }, durationMS: durationMS, fanIndex: fanIndex, manual: manual)
        events.append(event)
        if ["FanBar", "FanBarHelper", "local.fanbar.helper", "FanBarDiagnostics"].contains(ProcessInfo.processInfo.processName),
           let data = try? JSONEncoder().encode(event), let text = String(data: data, encoding: .utf8) {
            Self.log.notice("\(text, privacy: .public)")
        }
        // Keep launch markers even when repeated cooling requests fill the operation ring.
        // The service status is recorded only when it changes, so without this a run of
        // failed writes evicts it and the export reports the helper as unavailable.
        let markers: Set<RuntimeDiagnosticEvent.Action> = [.startup, .controllerReady, .menuReady, .shutdown,
                                                           .previousExitUnknown, .status]
        let recent = events.filter { Date().timeIntervalSince($0.timestamp) <= 86400 }
        events = (Array(recent.filter { markers.contains($0.action) }.suffix(32))
            + Array(recent.filter { !markers.contains($0.action) }.suffix(224))).sorted { $0.timestamp < $1.timestamp }
        guard let url, let data = try? JSONEncoder().encode(events), data.count <= 131072 else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* A diagnostics write must never prevent launch or fan restoration. */ }
    }

    /// Helper events kept from the whole last day: lifecycle markers and anything that failed.
    public static let importantHelperActions: Set<RuntimeDiagnosticEvent.Action> = [.startup, .shutdown, .recovery, .authorize]
    public static let importantHelperOutcomes: Set<RuntimeDiagnosticEvent.Outcome> = [.failed, .rejected]

    /// Read only this product's structured events; never return unified-log metadata or messages from other subsystems.
    /// A user often opens diagnostics long after the problem, so failures and lifecycle events are read from the
    /// last 24 hours. Routine curve writes could fill a day of logs, so the full stream covers only 10 minutes.
    public static func helperEvents() -> (events: [RuntimeDiagnosticEvent], available: Bool) {
        let base = "subsystem == \"local.fanbar.diagnostics\" AND category == \"events\" "
            + "AND eventMessage CONTAINS '\"component\":\"helper\"'"
        let important = (importantHelperOutcomes.map { "eventMessage CONTAINS '\"outcome\":\"\($0.rawValue)\"'" }
            + importantHelperActions.map { "eventMessage CONTAINS '\"action\":\"\($0.rawValue)\"'" })
            .sorted().joined(separator: " OR ")
        let recent = logEvents(last: "10m", predicate: base)
        let day = logEvents(last: "24h", predicate: "\(base) AND (\(important))")
        return (selectHelperEvents(recent: recent ?? [], important: day ?? []), recent != nil && day != nil)
    }

    /// Keeps up to `importantLimit` of the newest lifecycle/failure events, then fills the rest with the newest others,
    /// so a burst of routine writes cannot push out the event that explains a problem.
    public static func selectHelperEvents(recent: [RuntimeDiagnosticEvent], important: [RuntimeDiagnosticEvent],
                                          limit: Int = 64, importantLimit: Int = 32) -> [RuntimeDiagnosticEvent] {
        func key(_ event: RuntimeDiagnosticEvent) -> String {
            "\(event.timestamp.timeIntervalSinceReferenceDate)|\(event.sessionID)|\(event.requestID ?? "")|"
                + "\(event.action.rawValue)|\(event.outcome.rawValue)"
        }
        var seen = Set<String>()
        let unique = (important + recent).filter { $0.component == .helper && seen.insert(key($0)).inserted }
            .sorted { $0.timestamp < $1.timestamp }
        let kept = Array(unique.filter {
            importantHelperActions.contains($0.action) || importantHelperOutcomes.contains($0.outcome)
        }.suffix(importantLimit))
        let keptKeys = Set(kept.map(key))
        let rest = unique.filter { !keptKeys.contains(key($0)) }.suffix(max(0, limit - kept.count))
        return (kept + rest).sorted { $0.timestamp < $1.timestamp }
    }

    /// Parses `log show --style ndjson` output, keeping only messages that decode as helper events.
    public static func parseHelperLog(_ text: String) -> [RuntimeDiagnosticEvent] {
        text.split(separator: "\n").compactMap { line -> RuntimeDiagnosticEvent? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let message = object["eventMessage"] as? String,
                  let event = try? JSONDecoder().decode(RuntimeDiagnosticEvent.self, from: Data(message.utf8)),
                  event.component == .helper else { return nil }
            return event
        }
    }

    /// nil when the log could not be read in time or exceeded the output bound.
    private static func logEvents(last window: String, predicate: String) -> [RuntimeDiagnosticEvent]? {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: output) }
        guard let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--last", window, "--style", "ndjson", "--predicate", predicate]
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Collection runs off the main actor; a day of unified log can take several seconds to scan.
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning, Date() < deadline {
            if ((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 1048576 { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL); return nil }
        guard process.terminationStatus == 0,
              ((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max) <= 1048576,
              let data = try? Data(contentsOf: output), let text = String(data: data, encoding: .utf8) else { return nil }
        return parseHelperLog(text)
    }

    public func snapshot() -> [RuntimeDiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return events.filter { Date().timeIntervalSince($0.timestamp) <= 86400 }
    }

    public func beginLaunch() {
        let previous = snapshot().last { $0.action == .startup }
        if let previous, !snapshot().contains(where: { $0.sessionID == previous.sessionID && $0.action == .shutdown }) {
            record(.app, .previousExitUnknown, .failed)
        }
        record(.app, .startup, .started)
    }
}

public struct DiagnosticCrashSummary: Codable, Sendable {
    public struct Frame: Codable, Sendable { public let image: String; public let offset: Double }
    public let recordedAt: Date
    public let process: String
    public let exception: String
    public let signal: String
    public let terminationNamespace: String
    public let terminationCode: Int?
    public let frames: [Frame]
}

public enum DiagnosticCrashReader {
    public static var available: Bool {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
         URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")].allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    public static func summaries(directory: URL? = nil) -> [DiagnosticCrashSummary] {
        let userReports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let roots = directory.map { [$0] } ?? [userReports,
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let files = roots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: Array(keys))) ?? [] }
        return files.filter { ["ips", "crash"].contains($0.pathExtension) && ["FanBar-",
            "FanBar_", "FanBarHelper-", "FanBarHelper_", "local.fanbar.helper-",
            "local.fanbar.helper_"].contains(where: $0.lastPathComponent.hasPrefix)
        }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
            .prefix(3).compactMap { file in
                guard let info = try? file.resourceValues(forKeys: keys), let size = info.fileSize, size <= 2097152,
                      let date = info.contentModificationDate, Date().timeIntervalSince(date) <= 7 * 86400,
                      let data = try? Data(contentsOf: file) else { return nil }
                if file.pathExtension == "crash" { return legacySummary(data, recordedAt: date) }
                guard let newline = data.firstIndex(of: 10),
                      let object = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any],
                      let name = object["procName"] as? String,
                          ["FanBar", "FanBarHelper", "local.fanbar.helper"].contains(name) else { return nil }
                let exception = object["exception"] as? [String: Any] ?? [:]
                let termination = object["termination"] as? [String: Any] ?? [:]
                let allowedExceptions = ["EXC_BAD_ACCESS",
                    "EXC_BAD_INSTRUCTION", "EXC_CRASH", "EXC_RESOURCE", "EXC_BREAKPOINT",
                    "EXC_GUARD", "EXC_SOFTWARE"]
                let allowedSignals = ["SIGABRT", "SIGSEGV", "SIGBUS", "SIGILL", "SIGTRAP", "SIGKILL", "SIGTERM"]
                let allowedNamespaces = ["DYLD", "SIGNAL", "CODESIGNING", "TCC", "WATCHDOG", "RUNNINGBOARD", "LIBSYSTEM"]
                func allowed(_ value: Any?, _ choices: [String]) -> String {
                    let value = value as? String ?? ""; return choices.contains(value) ? value : "other"
                }
                let images = object["usedImages"] as? [[String: Any]] ?? []
                let threads = object["threads"] as? [[String: Any]] ?? []
                let index = object["faultingThread"] as? Int ?? -1
                let frames = threads.indices.contains(index) ? threads[index]["frames"] as? [[String: Any]] ?? [] : []
                let allowedImages = ["FanBar", "FanBarHelper",
                    "AppKit", "SwiftUI", "Foundation", "CoreFoundation", "libswiftCore.dylib",
                    "libsystem_kernel.dylib", "libsystem_pthread.dylib", "libsystem_c.dylib",
                    "libdispatch.dylib", "libobjc.A.dylib", "libswift_Concurrency.dylib",
                    "local.fanbar.helper", "dyld"]
                let safeFrames = frames.prefix(20).compactMap { frame -> DiagnosticCrashSummary.Frame? in
                    guard let imageIndex = frame["imageIndex"] as? Int, images.indices.contains(imageIndex),
                          let offset = frame["imageOffset"] as? Double, offset.isFinite, (0...1e12).contains(offset) else { return nil }
                    return .init(image: allowed(images[imageIndex]["name"], allowedImages), offset: offset)
                }
                return DiagnosticCrashSummary(recordedAt: date, process: name,
                    exception: allowed(exception["type"], allowedExceptions), signal: allowed(exception["signal"], allowedSignals),
                    terminationNamespace: allowed(termination["namespace"],
                        allowedNamespaces), terminationCode: termination["code"] as? Int,
                        frames: safeFrames)
            }
    }

    private static func legacySummary(_ data: Data, recordedAt: Date) -> DiagnosticCrashSummary? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        func capture(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        guard let name = capture(#"^Process:\s+(FanBar|FanBarHelper|local\.fanbar\.helper)\s+\["#) else { return nil }
        // Fixed regex literals describe the allowed crash categories.
        // swiftlint:disable:next line_length
        let exception = capture(#"^Exception Type:\s+(EXC_BAD_ACCESS|EXC_BAD_INSTRUCTION|EXC_CRASH|EXC_RESOURCE|EXC_BREAKPOINT|EXC_GUARD|EXC_SOFTWARE)\b"#) ?? "other"
        let signal = capture(#"^Exception Type:.*\((SIGABRT|SIGSEGV|SIGBUS|SIGILL|SIGTRAP|SIGKILL|SIGTERM)\)"#) ?? "other"
        // swiftlint:disable:next line_length
        let namespace = capture(#"^Termination Reason:.*Namespace (DYLD|SIGNAL|CODESIGNING|TCC|WATCHDOG|RUNNINGBOARD|LIBSYSTEM)\b"#) ?? "other"
        let code = capture(#"^Termination Reason:.*Code ([0-9]+)\b"#).flatMap(Int.init)
        return DiagnosticCrashSummary(recordedAt: recordedAt, process: name, exception: exception, signal: signal,
            terminationNamespace: namespace, terminationCode: code, frames: [])
    }
}

public struct DiagnosticRuntimeContext: Codable, Sendable {
    public let appBuild: String
    public let osBuild: String
    public let architecture: String
    public let bundleLocation: String
    public let helperPresent: Bool

    public static func current(bundle: Bundle = .main) -> Self {
        let path = bundle.bundleURL.path
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let location = path.contains("/AppTranslocation/") ? "translocated"
            : path.hasPrefix("/Applications/") ? "applications" : "other"
        let helperURL = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/local.fanbar.helper")
        return Self(appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osBuild: systemString("kern.osversion"), architecture: architecture,
            bundleLocation: location,
            helperPresent: FileManager.default.fileExists(atPath: helperURL.path))
    }

    public static func systemString(_ name: String) -> String {
        // Callers use only hw.model, machdep.cpu.brand_string, and kern.osversion.
        guard ["hw.model", "machdep.cpu.brand_string", "kern.osversion"].contains(name) else { return "unknown" }
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, (1...512).contains(size) else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "unknown"
    }
}

// swiftlint:enable discouraged_optional_boolean
