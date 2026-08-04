import AppKit
import FanBarShared
import Foundation

@MainActor
final class FanController: ObservableObject {
    enum AutomaticRestoreDuration: Int, CaseIterable, Identifiable {
        case fifteenMinutes = 900
        case thirtyMinutes = 1_800
        case oneHour = 3_600
        case never = 0

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .fifteenMinutes: "15 分钟"
            case .thirtyMinutes: "30 分钟"
            case .oneHour: "1 小时"
            case .never: "不自动恢复"
            }
        }
    }

    enum Mode: Equatable {
        case automatic
        case temperatureCurve
        case fixed(Int)
        case preset(FanCoolingPreset)
    }

    enum HelperState: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
        case unavailable

        var title: String {
            switch self {
            case .enabled: "控制服务已启用"
            case .requiresApproval: "等待系统批准控制服务"
            case .notRegistered: "尚未启用控制服务"
            case .unavailable: "应用包缺少控制服务"
            }
        }
    }

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var mode: Mode = .automatic
    @Published private(set) var message = "正在读取风扇…"
    @Published private(set) var isAvailable = false
    @Published private(set) var isBusy = false
    @Published private(set) var helperState: HelperState = .notRegistered
    @Published private(set) var temperatureHistory: [ThermalReading] = []
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var automaticRestoreDuration: AutomaticRestoreDuration = .thirtyMinutes
    @Published private(set) var automaticRestoreDeadline: Date?
    @Published private(set) var curveTemperatureCelsius: Double?
    @Published private(set) var curveOutputFraction: Float?

    private var localClient: SMCClient?
    private let helperClient = HelperClient()
    private let helperService = FanBarServiceManager()
    private let loginItemService = FanBarLoginItemManager()
    private var refreshTimer: Timer?
    private var automaticRestoreTask: Task<Void, Never>?
    private var curveUpdateTask: Task<Void, Never>?
    private var curveMissingTemperatureSamples = 0
    private var wakeObserver: NSObjectProtocol?
    private var helperMigrationAttempted = false
    private let automaticRestoreTestInterval: TimeInterval?
    // Ten minutes of readings at the two-second refresh cadence used below.
    private let maximumTemperatureSamples = 300
    private let automaticRestorePreferenceKey = "fanbar.automaticRestoreDuration"
    private let helperBuildVersionPreferenceKey = "fanbar.helperBuildVersion"
    private let helperBuildVersion: String
    private let temperatureCurve = TemperatureFanCurve.standard
    private let curveUpdateDeadband: Float = 0.02

    var statusIcon: String {
        mode == .automatic ? "fan" : "fan.fill"
    }

    init(automaticRestoreTestInterval: TimeInterval? = nil) {
        self.automaticRestoreTestInterval = automaticRestoreTestInterval
        helperBuildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        if let savedValue = UserDefaults.standard.object(
            forKey: automaticRestorePreferenceKey
        ) as? Int,
            let savedDuration = AutomaticRestoreDuration(rawValue: savedValue)
        {
            automaticRestoreDuration = savedDuration
        }
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        connectAndRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let deadline = self.automaticRestoreDeadline, deadline <= Date() {
                    self.restoreAutomaticAfterTimer()
                    return
                }
                switch self.mode {
                case .automatic:
                    break
                case .temperatureCurve:
                    if let reading = self.latestThermalReading() {
                        self.updateTemperatureCurve(using: reading, force: true)
                    }
                case .fixed(let rpm):
                    self.applyFixedRPM(rpm, resetsAutomaticRestore: false)
                case .preset(let preset):
                    self.applyCoolingPreset(preset, resetsAutomaticRestore: false)
                }
            }
        }
    }

    func refresh() {
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        guard let localClient else { connectAndRefresh(); return }
        do {
            fans = try localClient.fans()
            let thermal = localClient.thermalReading()
            appendTemperature(thermal)
            if mode == .temperatureCurve {
                updateTemperatureCurve(using: thermal)
            }
            isAvailable = true
            if mode == .automatic {
                // Permission state has its own actionable row; keep the header focused on fan mode.
                message = "由 macOS 自动管理"
            }
        } catch {
            isAvailable = false
            message = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            refreshLaunchAtLoginStatus()
            if launchAtLoginRequiresApproval {
                message = "请在“登录项与扩展”中允许 FanBar"
            }
        } catch {
            refreshLaunchAtLoginStatus()
            message = "无法更新登录项：\(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() {
        FanBarServiceManager.openLoginItemsSettings()
    }

    func enableHelper() {
        do {
            try helperService.register()
            refreshHelperStatus()
            if helperState == .requiresApproval {
                message = "请在“登录项与扩展”中允许 FanBar"
                helperService.openSettings()
            } else {
                message = helperState.title
            }
        } catch {
            refreshHelperStatus()
            message = "无法注册控制服务：\(error.localizedDescription)"
            if helperState == .requiresApproval {
                helperService.openSettings()
            }
        }
    }

    func openHelperSettings() {
        helperService.openSettings()
    }

    func setFixedRPM(_ rpm: Int) {
        applyFixedRPM(rpm, resetsAutomaticRestore: true)
    }

    private func applyFixedRPM(_ rpm: Int, resetsAutomaticRestore: Bool) {
        guard helperState == .enabled, !isBusy else {
            message = "请先启用并批准控制服务"
            return
        }
        isBusy = true
        message = "正在切换到 \(rpm) RPM…"
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setAllFans(rpm: rpm)
                mode = .fixed(rpm)
                clearTemperatureCurveState()
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                message = "固定目标：\(rpm) RPM"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "控制失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func setCoolingPreset(_ preset: FanCoolingPreset) {
        applyCoolingPreset(preset, resetsAutomaticRestore: true)
    }

    private func applyCoolingPreset(
        _ preset: FanCoolingPreset,
        resetsAutomaticRestore: Bool
    ) {
        guard helperState == .enabled, !isBusy else {
            message = "请先启用并批准控制服务"
            return
        }
        isBusy = true
        message = "正在切换到\(preset.title)模式…"
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setCoolingPreset(preset)
                mode = .preset(preset)
                clearTemperatureCurveState()
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                message = "\(preset.title)模式：最大转速的 \(preset.percentageText)"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "控制失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func setAutomatic() {
        restoreAutomatic(triggeredByTimer: false)
    }

    func setTemperatureCurveEnabled(_ enabled: Bool) {
        if enabled {
            enableTemperatureCurve()
        } else {
            setAutomatic()
        }
    }

    private func enableTemperatureCurve() {
        guard helperState == .enabled, !isBusy else {
            message = "请先启用并批准控制服务"
            return
        }
        guard let reading = latestThermalReading(),
              let temperature = controlTemperature(from: reading) else {
            message = "未读取到可用于智能温控的芯片温度"
            return
        }

        let fraction = temperatureCurve.fraction(at: temperature)
        isBusy = true
        message = "正在开启智能温控…"
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setCoolingFraction(fraction)
                mode = .temperatureCurve
                curveTemperatureCelsius = temperature
                curveOutputFraction = fraction
                scheduleAutomaticRestore()
                updateCurveMessage()
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                clearTemperatureCurveState()
                message = "智能温控开启失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    private func updateTemperatureCurve(using reading: ThermalReading, force: Bool = false) {
        guard mode == .temperatureCurve,
              !isBusy,
              curveUpdateTask == nil else { return }
        guard let temperature = controlTemperature(from: reading) else {
            curveMissingTemperatureSamples += 1
            if curveMissingTemperatureSamples >= 3 {
                message = "温度传感器不可用，正在恢复系统控制…"
                restoreAutomatic(triggeredByTimer: false)
            }
            return
        }
        curveMissingTemperatureSamples = 0

        let fraction = temperatureCurve.fraction(at: temperature)
        curveTemperatureCelsius = temperature
        if !force,
           let previous = curveOutputFraction,
           abs(fraction - previous) < curveUpdateDeadband {
            updateCurveMessage()
            return
        }

        curveUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.curveUpdateTask = nil }
            do {
                try await self.helperClient.setCoolingFraction(fraction)
                guard self.mode == .temperatureCurve else { return }
                self.curveOutputFraction = fraction
                self.updateCurveMessage()
            } catch {
                guard self.mode == .temperatureCurve else { return }
                self.message = "智能温控更新失败：\(error.localizedDescription)"
            }
        }
    }

    private func controlTemperature(from reading: ThermalReading) -> Double? {
        [reading.cpuCelsius, reading.gpuCelsius].compactMap { $0 }.max()
    }

    private func latestThermalReading() -> ThermalReading? {
        if let latest = temperatureHistory.last { return latest }
        return localClient?.thermalReading()
    }

    private func updateCurveMessage() {
        guard let temperature = curveTemperatureCelsius,
              let fraction = curveOutputFraction else { return }
        message = String(
            format: "智能温控：%.0f°C · 最大转速 %.0f%%",
            temperature,
            fraction * 100
        )
    }

    private func finishPendingCurveUpdate() async {
        let pending = curveUpdateTask
        pending?.cancel()
        await pending?.value
        curveUpdateTask = nil
    }

    private func clearTemperatureCurveState() {
        curveTemperatureCelsius = nil
        curveOutputFraction = nil
        curveMissingTemperatureSamples = 0
    }

    func setAutomaticRestoreDuration(_ duration: AutomaticRestoreDuration) {
        automaticRestoreDuration = duration
        UserDefaults.standard.set(duration.rawValue, forKey: automaticRestorePreferenceKey)
        if mode != .automatic {
            scheduleAutomaticRestore()
        }
    }

    private func restoreAutomatic(triggeredByTimer: Bool) {
        guard !isBusy else {
            if triggeredByTimer {
                scheduleAutomaticRestoreRetry(after: 1)
            }
            return
        }
        guard helperState == .enabled else {
            mode = .automatic
            clearTemperatureCurveState()
            clearAutomaticRestore()
            message = helperState.title
            return
        }
        isBusy = true
        message = "正在恢复系统控制…"
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.restoreAutomatic()
                mode = .automatic
                clearTemperatureCurveState()
                clearAutomaticRestore()
                message = triggeredByTimer
                    ? "定时结束，已恢复 macOS 自动控制"
                    : "已恢复 macOS 自动控制"
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = "恢复失败：\(error.localizedDescription)"
                if triggeredByTimer {
                    scheduleAutomaticRestoreRetry(after: 5)
                }
            }
            isBusy = false
        }
    }

    private func scheduleAutomaticRestore() {
        automaticRestoreTask?.cancel()
        guard mode != .automatic, automaticRestoreDuration != .never else {
            automaticRestoreDeadline = nil
            automaticRestoreTask = nil
            return
        }

        let interval = automaticRestoreTestInterval
            ?? TimeInterval(automaticRestoreDuration.rawValue)
        let deadline = Date().addingTimeInterval(interval)
        automaticRestoreDeadline = deadline
        automaticRestoreTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.restoreAutomaticAfterTimer()
        }
    }

    private func restoreAutomaticAfterTimer() {
        guard mode != .automatic else {
            clearAutomaticRestore()
            return
        }
        restoreAutomatic(triggeredByTimer: true)
    }

    private func scheduleAutomaticRestoreRetry(after interval: TimeInterval) {
        automaticRestoreTask?.cancel()
        automaticRestoreTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.restoreAutomaticAfterTimer()
        }
    }

    private func clearAutomaticRestore() {
        automaticRestoreTask?.cancel()
        automaticRestoreTask = nil
        automaticRestoreDeadline = nil
    }

    func quit() {
        Task {
            await finishPendingCurveUpdate()
            if helperState == .enabled {
                try? await helperClient.restoreAutomatic()
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private func connectAndRefresh() {
        do {
            localClient = try SMCClient()
            refresh()
        } catch {
            isAvailable = false
            message = error.localizedDescription
        }
    }

    private func refreshHelperStatus() {
        helperService.refresh()
        switch helperService.status {
        case .enabled:
            helperState = .enabled
            migrateHelperIfNeeded()
        case .requiresApproval:
            helperState = .requiresApproval
        case .notRegistered:
            helperState = .notRegistered
        case .unavailable:
            helperState = .unavailable
        }
    }

    /// Re-registers the bundled daemon once after an app overwrite so the running
    /// XPC service uses the same protocol version as the visible UI.
    private func migrateHelperIfNeeded() {
        guard !helperMigrationAttempted else { return }
        guard helperBuildVersion != "unknown" else {
            helperMigrationAttempted = true
            return
        }
        let savedVersion = UserDefaults.standard.string(forKey: helperBuildVersionPreferenceKey)
        guard savedVersion != helperBuildVersion else {
            helperMigrationAttempted = true
            return
        }

        // Legacy launchd registration already required an administrator prompt.
        // Do not immediately ask for a second prompt on the first Big Sur setup;
        // later bundle-version changes still take the migration path below.
        if #unavailable(macOS 13.0), savedVersion == nil {
            UserDefaults.standard.set(
                helperBuildVersion,
                forKey: helperBuildVersionPreferenceKey
            )
            helperMigrationAttempted = true
            return
        }

        helperMigrationAttempted = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.reRegisterHelper()
                self.helperService.refresh()
                guard self.helperService.status == .enabled else {
                    self.message = "请在系统设置中批准新版控制服务"
                    self.refreshHelperStatus()
                    return
                }
                UserDefaults.standard.set(
                    self.helperBuildVersion,
                    forKey: self.helperBuildVersionPreferenceKey
                )
                self.refreshHelperStatus()
            } catch {
                // Keep the actionable permission state visible; the next launch retries.
                self.message = "控制服务更新失败，请重新打开 FanBar"
                self.refreshHelperStatus()
            }
        }
    }

    private func reRegisterHelper() async throws {
        try await helperService.unregister()
        // launchd needs a short moment to remove the old submission before the
        // same daemon label can be registered again.
        for attempt in 0..<3 {
            do {
                try helperService.register()
                return
            } catch {
                guard attempt < 2 else { throw error }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func refreshLaunchAtLoginStatus() {
        loginItemService.refresh()
        launchAtLoginEnabled = loginItemService.status == .enabled
        launchAtLoginRequiresApproval = loginItemService.status == .requiresApproval
    }

    private func appendTemperature(_ reading: ThermalReading) {
        guard reading.cpuCelsius != nil || reading.gpuCelsius != nil else { return }
        temperatureHistory.append(reading)
        let earliestSampleDate = reading.sampledAt.addingTimeInterval(-TemperatureChart.historyDuration)
        temperatureHistory.removeAll { $0.sampledAt < earliestSampleDate }
        if temperatureHistory.count > maximumTemperatureSamples {
            temperatureHistory.removeFirst(temperatureHistory.count - maximumTemperatureSamples)
        }
    }
}
