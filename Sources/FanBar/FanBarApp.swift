import FanBarShared
import SwiftUI

@main
struct FanBarApp: App {
    @StateObject private var controller: FanController
    @AppStorage(MenuBarDisplayMode.preferenceKey)
    private var menuBarDisplayModeRawValue = MenuBarDisplayMode.defaultMode.rawValue

    private var menuBarDisplayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: menuBarDisplayModeRawValue) ?? .defaultMode
    }

    init() {
        if CommandLine.arguments.contains("--register-helper") {
            Self.registerHelperAndExit()
        }
        if CommandLine.arguments.contains("--unregister-helper") {
            Self.unregisterHelperAndExit()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            Self.runSmokeTestAndExit()
        }
        if CommandLine.arguments.contains("--telemetry-test") {
            Self.runTelemetryTestAndExit()
        }
        if CommandLine.arguments.contains("--automatic-restore-smoke-test") {
            Self.runAutomaticRestoreSmokeTestAndExit()
        }
        if CommandLine.arguments.contains("--temperature-curve-smoke-test") {
            Self.runTemperatureCurveSmokeTestAndExit()
        }
        let controller = FanController()
        _controller = StateObject(wrappedValue: controller)
        LegacyStatusItemController.shared.install(controller: controller)
        if CommandLine.arguments.contains("--settings-window-smoke-test") {
            Self.runSettingsWindowSmokeTest(controller: controller)
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    /// Ensures the LSUIElement app can activate and present a key settings window.
    private static func runSettingsWindowSmokeTest(controller: FanController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let window = SettingsWindowPresenter.shared.show(controller: controller)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let pointer = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                    ?? NSScreen.main
                let centered = screen.map {
                    abs(window.frame.midX - $0.visibleFrame.midX) < 2
                        && abs(window.frame.midY - $0.visibleFrame.midY) < 2
                } ?? false
                let passed = window.isVisible
                    && window.isKeyWindow
                    && NSApplication.shared.isActive
                    && centered
                print("settings-window-visible=\(window.isVisible)")
                print("settings-window-key=\(window.isKeyWindow)")
                print("application-active=\(NSApplication.shared.isActive)")
                print("settings-window-centered=\(centered)")
                print("settings-window-center=\(window.frame.midX),\(window.frame.midY)")
                if let visibleFrame = screen?.visibleFrame {
                    print("settings-screen-center=\(visibleFrame.midX),\(visibleFrame.midY)")
                    print("settings-window-frame=\(NSStringFromRect(window.frame))")
                    print("settings-visible-frame=\(NSStringFromRect(visibleFrame))")
                }
                SettingsWindowPresenter.shared.close()
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }

    /// A deterministic installer entry point for managed/local deployment.
    private static func registerHelperAndExit() -> Never {
        let service = FanBarServiceManager()
        do {
            try service.register()
            switch service.status {
            case .enabled:
                print("helper-status=enabled")
                exit(EXIT_SUCCESS)
            case .requiresApproval:
                print("helper-status=requires-approval")
                service.openSettings()
                exit(2)
            case .notRegistered:
                print("helper-status=not-registered")
                exit(3)
            case .unavailable:
                print("helper-status=unknown")
                exit(5)
            }
        } catch {
            print("helper-register-error=\(error.localizedDescription)")
            exit(1)
        }
    }

    /// Cleanly removes a managed daemon before replacing it with a newer bundle version.
    private static func unregisterHelperAndExit() -> Never {
        let service = FanBarServiceManager()
        Task {
            do {
                try await service.unregister()
                print("helper-unregister=success")
                exit(EXIT_SUCCESS)
            } catch {
                print("helper-unregister-error=\(error.localizedDescription)")
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
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
                for preset in FanCoolingPreset.allCases {
                    try await client.setCoolingPreset(preset)
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    let readings = try await client.fans()
                    let targets = readings.map {
                        Int((Float($0.maximumRPM) * preset.maximumFraction).rounded())
                    }
                    print("preset-\(preset.rawValue)-actual=\(readings.map(\.currentRPM))")
                    print("preset-\(preset.rawValue)-targets=\(targets)")
                }
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

    /// Verifies the real controller timer path with a short test-only deadline.
    private static func runAutomaticRestoreSmokeTestAndExit() -> Never {
        Task { @MainActor in
            let controller = FanController(automaticRestoreTestInterval: 3)
            controller.setFixedRPM(3_500)

            let fixedDeadline = Date().addingTimeInterval(10)
            while controller.isBusy, Date() < fixedDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard controller.mode == .fixed(3_500),
                  controller.automaticRestoreDeadline != nil
            else {
                print("automatic-restore-test=failed-to-enter-fixed")
                exit(EXIT_FAILURE)
            }

            let restoreDeadline = Date().addingTimeInterval(10)
            while controller.mode != .automatic, Date() < restoreDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard controller.mode == .automatic else {
                try? await HelperClient().restoreAutomatic()
                print("automatic-restore-test=timeout")
                print("mode=\(controller.mode)")
                print("busy=\(controller.isBusy)")
                print("message=\(controller.message)")
                print("deadline=\(controller.automaticRestoreDeadline?.description ?? "none")")
                exit(EXIT_FAILURE)
            }

            let readings = try? await HelperClient().fans()
            print("automatic-restore-test=success")
            print("after-restore=\(readings?.map(\.currentRPM) ?? [])")
            exit(EXIT_SUCCESS)
        }
        dispatchMain()
    }

    /// Exercises interpolation plus the complete curve enable/disable controller path.
    private static func runTemperatureCurveSmokeTestAndExit() -> Never {
        Task { @MainActor in
            let curve = TemperatureFanCurve.standard
            let checks: [(Double, Float)] = [
                (40, 0.35), (52.5, 0.425), (60, 0.50), (75, 0.75), (90, 1.00)
            ]
            guard checks.allSatisfy({ abs(curve.fraction(at: $0.0) - $0.1) < 0.001 }) else {
                print("temperature-curve-test=interpolation-failed")
                exit(EXIT_FAILURE)
            }

            let controller = FanController()
            controller.setTemperatureCurveEnabled(true)
            let enableDeadline = Date().addingTimeInterval(15)
            while controller.isBusy, Date() < enableDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard controller.mode == .temperatureCurve,
                  let temperature = controller.curveTemperatureCelsius,
                  let fraction = controller.curveOutputFraction,
                  controller.automaticRestoreDeadline != nil else {
                try? await HelperClient().restoreAutomatic()
                print("temperature-curve-test=enable-failed")
                print("message=\(controller.message)")
                exit(EXIT_FAILURE)
            }

            let readings = try? await HelperClient().fans()
            print(String(format: "curve-temperature=%.1f", temperature))
            print(String(format: "curve-output=%.1f%%", fraction * 100))
            print("curve-fans=\(readings?.map(\.currentRPM) ?? [])")

            controller.setTemperatureCurveEnabled(false)
            let disableDeadline = Date().addingTimeInterval(15)
            while controller.isBusy, Date() < disableDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard controller.mode == .automatic else {
                try? await HelperClient().restoreAutomatic()
                print("temperature-curve-test=disable-failed")
                exit(EXIT_FAILURE)
            }
            print("temperature-curve-test=success")
            print("restore-auto=success")
            exit(EXIT_SUCCESS)
        }
        dispatchMain()
    }
}
