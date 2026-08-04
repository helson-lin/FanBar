import FanBarShared
import ServiceManagement
import SwiftUI

@main
struct FanBarApp: App {
    @StateObject private var controller: FanController

    init() {
        if CommandLine.arguments.contains("--register-helper") {
            Self.registerHelperAndExit()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            Self.runSmokeTestAndExit()
        }
        if CommandLine.arguments.contains("--telemetry-test") {
            Self.runTelemetryTestAndExit()
        }
        _controller = StateObject(wrappedValue: FanController())
    }

    var body: some Scene {
        MenuBarExtra {
            FanMenu(controller: controller)
        } label: {
            Image(systemName: controller.statusIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    /// A deterministic installer entry point for managed/local deployment.
    private static func registerHelperAndExit() -> Never {
        let service = SMAppService.daemon(plistName: FanBarService.helperPlistName)
        do {
            try service.register()
            switch service.status {
            case .enabled:
                print("helper-status=enabled")
                exit(EXIT_SUCCESS)
            case .requiresApproval:
                print("helper-status=requires-approval")
                SMAppService.openSystemSettingsLoginItems()
                exit(2)
            case .notRegistered:
                print("helper-status=not-registered")
                exit(3)
            case .notFound:
                print("helper-status=not-found")
                exit(4)
            @unknown default:
                print("helper-status=unknown")
                exit(5)
            }
        } catch {
            print("helper-register-error=\(error.localizedDescription)")
            exit(1)
        }
    }

    /// Exercises the exact signed XPC path used by the menu, then always restores auto.
    private static func runSmokeTestAndExit() -> Never {
        Task.detached {
            let client = HelperClient()
            do {
                let before = try await client.fans()
                print("before=\(before.map(\.currentRPM))")
                try await client.setAllFans(rpm: 3500)
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let afterFixed = try await client.fans()
                print("after-fixed=\(afterFixed.map(\.currentRPM))")
                try await client.setAllFansToEightyPercent()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let afterExtreme = try await client.fans()
                print("after-extreme=\(afterExtreme.map(\.currentRPM))")
                print(
                    "extreme-targets=\(afterExtreme.map { Int((Double($0.maximumRPM) * 0.8).rounded()) })"
                )
                try await client.restoreAutomatic()
                print("restore-auto=success")
                exit(EXIT_SUCCESS)
            } catch {
                try? await client.restoreAutomatic()
                print("smoke-test-error=\(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }

    /// Read-only diagnostic used to verify sensor discovery on the current Mac.
    private static func runTelemetryTestAndExit() -> Never {
        do {
            let client = try SMCClient()
            let fans = try client.fans()
            let thermal = client.thermalReading()
            print("fans=\(fans.map(\.currentRPM))")
            print("cpu-celsius=\(thermal.cpuCelsius.map { String(format: "%.1f", $0) } ?? "unavailable")")
            print("gpu-celsius=\(thermal.gpuCelsius.map { String(format: "%.1f", $0) } ?? "unavailable")")
            exit(EXIT_SUCCESS)
        } catch {
            print("telemetry-test-error=\(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }
}
