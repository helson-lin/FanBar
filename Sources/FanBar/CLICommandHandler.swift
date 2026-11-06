import FanBarShared
import Foundation

/// Runs one `fanbar` request against the live controller.
///
/// Mode changes go through the same entry points as the menu panel, so the
/// CLI inherits their guards, feedback and curve handling. Those entry points
/// return immediately and finish in a task, so the handler waits for `isBusy`
/// to clear before it reports success or failure.
///
/// Replies are plain English: the CLI is for scripts, whose output should not
/// change with the app language. Failures raised by the controller keep the
/// controller's own localized wording.
@MainActor
enum CLICommandHandler {
    static func handle(
        _ request: FanBarCLIRequest,
        controller: FanController,
        commandTimeout: TimeInterval = FanBarCLIContract.commandTimeout
    ) async -> FanBarCLIResponse {
        // One budget for the whole request, so the reply always arrives inside
        // the CLI's `replyTimeout` however the time splits between the waits.
        let deadline = Date().addingTimeInterval(commandTimeout)
        guard request.version == FanBarCLIContract.version else {
            return FanBarCLIResponse(
                ok: false,
                message: "This fanbar tool and FanBar.app are different versions. Use the tool inside the running app."
            )
        }
        switch request.action {
        case .status:
            return FanBarCLIResponse(ok: true, message: summary(of: controller), status: status(of: controller))
        case .listPresets:
            return FanBarCLIResponse(ok: true, message: "", presets: presets(of: controller))
        case .setPreset:
            guard let query = request.preset,
                  let preset = resolvePreset(query, in: controller.allPresets) else {
                let names = presets(of: controller).map(\.key).joined(separator: ", ")
                return FanBarCLIResponse(
                    ok: false,
                    message: "Unknown preset \"\(request.preset ?? "")\". Available: \(names)"
                )
            }
            return await run(request, controller: controller, deadline: deadline) {
                controller.setCoolingPreset(preset)
            } succeeded: {
                controller.mode == .temperatureCurve && controller.curveCoolingPreset == preset
            }
        case .curve:
            return await run(request, controller: controller, deadline: deadline) {
                controller.setTemperatureCurveEnabled(true)
            } succeeded: {
                controller.mode == .temperatureCurve
            }
        case .fixed:
            guard let rpm = request.rpm else {
                return FanBarCLIResponse(ok: false, message: "Missing RPM.")
            }
            return await run(request, controller: controller, deadline: deadline) {
                controller.setCustomFixedRPM(rpm)
            } succeeded: {
                controller.mode == .fixed(rpm)
            }
        case .automatic:
            return await run(request, controller: controller, deadline: deadline) {
                controller.setAutomatic()
            } succeeded: {
                controller.mode == .automatic
            }
        }
    }

    private static func run(
        _ request: FanBarCLIRequest,
        controller: FanController,
        deadline: Date,
        action: () -> Void,
        succeeded: () -> Bool
    ) async -> FanBarCLIResponse {
        // A switch already in flight would make the controller drop this one.
        guard await waitUntilIdle(controller, until: deadline) else {
            return FanBarCLIResponse(ok: false, message: "FanBar is busy switching modes. Try again.")
        }
        controller.clearModeActionFeedback()
        action()
        guard await waitUntilIdle(controller, until: deadline) else {
            return FanBarCLIResponse(ok: false, message: "Timed out waiting for the fans to respond.")
        }
        if let feedback = controller.modeActionFeedback, feedback.kind == .failure {
            return FanBarCLIResponse(ok: false, message: feedback.message, status: status(of: controller))
        }
        guard succeeded() else {
            return FanBarCLIResponse(ok: false, message: controller.message, status: status(of: controller))
        }
        if controller.mode != .automatic {
            // Without --hold the session follows the Settings default, even if
            // the panel or an earlier --hold changed this session's duration.
            controller.setAutomaticRestoreDuration(
                request.hold ? .never : controller.defaultAutomaticRestoreDuration
            )
        }
        return FanBarCLIResponse(ok: true, message: summary(of: controller), status: status(of: controller))
    }

    private static func waitUntilIdle(_ controller: FanController, until deadline: Date) async -> Bool {
        while controller.isBusy {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }

    // MARK: - Pure mapping

    /// Matches a token (`builtin:2`), a built-in key (`performance`), or a
    /// preset title in the current language, ignoring case and spacing.
    static func resolvePreset(_ query: String, in presets: [CoolingPresetSummary]) -> CoolingPresetID? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = CoolingPresetID(token: trimmed), presets.contains(where: { $0.id == token }) {
            return token
        }
        let wanted = normalized(trimmed)
        guard !wanted.isEmpty else { return nil }
        if let builtIn = FanCoolingPreset.allCases.first(where: { $0.cliKey == wanted }) {
            return .builtIn(builtIn)
        }
        return presets.first { normalized($0.title) == wanted }?.id
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    static func presets(of controller: FanController) -> [FanBarCLIPreset] {
        controller.allPresets.map { summary in
            FanBarCLIPreset(
                id: summary.id.token,
                key: summary.id.builtInPreset?.cliKey ?? summary.title,
                name: summary.title,
                builtIn: summary.isBuiltIn,
                selected: summary.id == controller.curveCoolingPreset
            )
        }
    }

    static func status(of controller: FanController) -> FanBarCLIStatus {
        let mode: FanBarCLIStatus.Mode
        var fixedRPM: Int?
        switch controller.mode {
        case .automatic: mode = .automatic
        case .temperatureCurve: mode = .curve
        case .fixed(let rpm):
            mode = .fixed
            fixedRPM = rpm
        }
        let reading = controller.temperatureHistory.last
        return FanBarCLIStatus(
            mode: mode,
            preset: controller.curveCoolingPreset.token,
            presetName: controller.presetTitle(for: controller.curveCoolingPreset),
            fixedRPM: fixedRPM,
            curveOutputPercent: mode == .curve ? controller.curveOutputFraction.map { Double($0) * 100 } : nil,
            restoresAt: controller.automaticRestoreDeadline,
            helperEnabled: controller.helperState == .enabled,
            fans: controller.fans.map {
                FanBarCLIStatus.Fan(
                    index: $0.index,
                    currentRPM: $0.currentRPM,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM
                )
            },
            cpuCelsius: reading?.cpuCelsius,
            gpuCelsius: reading?.gpuCelsius,
            ssdCelsius: reading?.ssdCelsius
        )
    }

    private static func summary(of controller: FanController) -> String {
        switch controller.mode {
        case .automatic:
            return "macOS automatic control"
        case .temperatureCurve:
            return "Preset \(controller.presetTitle(for: controller.curveCoolingPreset)) (curve)" + holdSuffix(controller)
        case .fixed(let rpm):
            return "Fixed \(rpm) RPM" + holdSuffix(controller)
        }
    }

    private static func holdSuffix(_ controller: FanController) -> String {
        guard let deadline = controller.automaticRestoreDeadline else { return ", held until changed" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return ", macOS control returns at \(formatter.string(from: deadline))"
    }
}

extension FanCoolingPreset {
    /// Language-independent name accepted by `fanbar preset set`.
    var cliKey: String {
        switch self {
        case .silent: "silent"
        case .balanced: "balanced"
        case .performance: "performance"
        case .extreme: "extreme"
        }
    }
}
