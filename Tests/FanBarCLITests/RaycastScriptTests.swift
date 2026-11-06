import Foundation
import Testing

/// Runs the Raycast script commands in `integrations/raycast` against a fake
/// `fanbar`, so no test ever switches real fans.
struct RaycastScriptTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/raycast", isDirectory: true)

    private static var scripts: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    private struct Run {
        let output: String
        let status: Int32
        /// Arguments the fake fanbar received, one invocation per line.
        let calls: [String]
    }

    /// `fakeOutput` and `fakeStatus` script the fake tool's answer.
    private func run(
        _ name: String,
        _ arguments: [String] = [],
        fakeOutput: String = "ok",
        fakeStatus: Int32 = 0
    ) throws -> Run {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("calls")
        let fake = root.appendingPathComponent("fanbar")
        try """
        #!/bin/bash
        echo "$*" >> '\(log.path)'
        printf '%s\\n' '\(fakeOutput)'
        exit \(fakeStatus)
        """.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let process = Process()
        process.executableURL = Self.directory.appendingPathComponent(name)
        process.arguments = arguments
        // Raycast's environment: no shell profile, a bare PATH.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": root.path, "FANBAR_CLI": fake.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let calls = (try? String(contentsOf: log, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        return Run(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            status: process.terminationStatus,
            calls: calls
        )
    }

    @Test func everyScriptIsAValidExecutableRaycastCommand() throws {
        #expect(Self.scripts.count == 4)
        for script in Self.scripts {
            let text = try String(contentsOf: script, encoding: .utf8)
            #expect(FileManager.default.isExecutableFile(atPath: script.path), "\(script.lastPathComponent)")
            for key in ["@raycast.schemaVersion 1", "@raycast.title ", "@raycast.mode ", "@raycast.packageName FanBar"] {
                #expect(text.contains(key), "\(script.lastPathComponent) lacks \(key)")
            }
            // Raycast rejects argument metadata that is not valid JSON.
            for line in text.split(separator: "\n") where line.contains("@raycast.argument") {
                let json = line.drop { $0 != "{" }
                #expect(throws: Never.self, "\(script.lastPathComponent)") {
                    try JSONSerialization.jsonObject(with: Data(json.utf8))
                }
            }
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/bin/bash")
            check.arguments = ["-n", script.path]
            try check.run()
            check.waitUntilExit()
            #expect(check.terminationStatus == 0, "\(script.lastPathComponent) has a syntax error")
        }
    }

    @Test func presetPassesHoldOnlyWhenChosen() throws {
        #expect(try run("fanbar-preset.sh", ["silent"]).calls == ["preset set silent"])
        #expect(try run("fanbar-preset.sh", ["performance", "timer"]).calls == ["preset set performance"])
        #expect(try run("fanbar-preset.sh", ["extreme", "hold"]).calls == ["preset set extreme --hold"])
    }

    @Test func failuresReachTheHudAndTheExitStatus() throws {
        let result = try run("fanbar-preset.sh", ["silent"], fakeOutput: "fanbar: Enable the control service", fakeStatus: 1)
        #expect(result.output == "fanbar: Enable the control service")
        #expect(result.status == 1)
    }

    @Test func fixedValidatesBeforeCallingFanbar() throws {
        #expect(try run("fanbar-fixed.sh", ["3000", "hold"]).calls == ["mode fixed 3000 --hold"])
        let rejected = try run("fanbar-fixed.sh", ["fast"])
        #expect(rejected.calls.isEmpty)
        #expect(rejected.status == 1)
    }

    @Test func automaticHandsBackToMacOS() throws {
        #expect(try run("fanbar-auto.sh").calls == ["mode auto"])
    }

    @Test func temperaturesFitOnOneInlineLineWithoutLaunching() throws {
        let readings = "CPU:     58.8 °C\nGPU:     52.3 °C\nSSD:     41.0 °C"
        let result = try run("fanbar-temperatures.sh", fakeOutput: readings)
        #expect(result.output == "CPU 59° · GPU 52° · SSD 41°")
        #expect(result.calls == ["temps --no-launch"])

        let stopped = try run("fanbar-temperatures.sh", fakeOutput: "fanbar: FanBar is not running.", fakeStatus: 3)
        #expect(stopped.output == "FanBar is not running")
        #expect(stopped.status == 0)
    }
}
