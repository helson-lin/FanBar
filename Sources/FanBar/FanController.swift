import AppKit
import FanBarShared
import Foundation
import UserNotifications

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
            case .fifteenMinutes: fanBarText("15 分钟", "15 minutes")
            case .thirtyMinutes: fanBarText("30 分钟", "30 minutes")
            case .oneHour: fanBarText("1 小时", "1 hour")
            case .never: fanBarText("不自动恢复", "Never")
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
            case .enabled: fanBarText("控制服务已启用", "Control service enabled")
            case .requiresApproval: fanBarText("等待系统批准控制服务", "Waiting for control service approval")
            case .notRegistered: fanBarText("尚未启用控制服务", "Control service is not enabled")
            case .unavailable: fanBarText("应用包缺少控制服务", "Control service is missing from the app bundle")
            }
        }
    }

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var mode: Mode = .automatic
    @Published private(set) var message = fanBarText("正在读取风扇…", "Reading fans…")
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
    @Published private(set) var highTemperatureNotificationsEnabled: Bool
    @Published private(set) var isRequestingHighTemperatureNotificationPermission = false

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
    private var highTemperatureNotificationRequestID = 0
    private var thermalAlertMonitor = ThermalAlertMonitor(
        thresholdCelsius: ThermalAlertSettings.thresholdCelsius
    )
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationDelegate = ThermalNotificationDelegate()
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
        highTemperatureNotificationsEnabled = UserDefaults.standard.bool(
            forKey: ThermalAlertSettings.notificationsEnabledKey
        )
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
        notificationCenter.delegate = notificationDelegate
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
            evaluateThermalAlerts(using: thermal)
            if mode == .temperatureCurve {
                updateTemperatureCurve(using: thermal)
            }
            isAvailable = true
            if mode == .automatic {
                // Permission state has its own actionable row; keep the header focused on fan mode.
                message = fanBarText("由 macOS 自动管理", "Managed automatically by macOS")
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
                message = fanBarText("请在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions")
            }
        } catch {
            refreshLaunchAtLoginStatus()
            message = fanBarFormat(
                "无法更新登录项：%@",
                "Unable to update login item: %@",
                error.localizedDescription
            )
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
                message = fanBarText("请在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions")
                helperService.openSettings()
            } else {
                message = helperState.title
            }
        } catch {
            refreshHelperStatus()
            message = fanBarFormat(
                "无法注册控制服务：%@",
                "Unable to register control service: %@",
                error.localizedDescription
            )
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
            message = fanBarText("请先启用并批准控制服务", "Enable and approve the control service first")
            return
        }
        isBusy = true
        message = fanBarFormat("正在切换到 %d RPM…", "Switching to %d RPM…", rpm)
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setAllFans(rpm: rpm)
                mode = .fixed(rpm)
                clearTemperatureCurveState()
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                message = fanBarFormat("固定目标：%d RPM", "Fixed target: %d RPM", rpm)
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = fanBarFormat("控制失败：%@", "Control failed: %@", error.localizedDescription)
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
            message = fanBarText("请先启用并批准控制服务", "Enable and approve the control service first")
            return
        }
        isBusy = true
        message = fanBarFormat(
            "正在切换到%@模式…",
            "Switching to %@ mode…",
            preset.title
        )
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setCoolingPreset(preset)
                mode = .preset(preset)
                clearTemperatureCurveState()
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                message = fanBarFormat(
                    "%@模式：最大转速的 %@",
                    "%@ mode: %@ of maximum RPM",
                    preset.title,
                    preset.percentageText
                )
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = fanBarFormat("控制失败：%@", "Control failed: %@", error.localizedDescription)
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

    func setHighTemperatureNotificationsEnabled(_ enabled: Bool) {
        highTemperatureNotificationRequestID += 1
        let requestID = highTemperatureNotificationRequestID

        guard enabled else {
            highTemperatureNotificationsEnabled = false
            isRequestingHighTemperatureNotificationPermission = false
            thermalAlertMonitor.reset()
            UserDefaults.standard.set(
                false,
                forKey: ThermalAlertSettings.notificationsEnabledKey
            )
            return
        }

        isRequestingHighTemperatureNotificationPermission = true
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard requestID == self.highTemperatureNotificationRequestID else { return }
                self.isRequestingHighTemperatureNotificationPermission = false

                guard granted else {
                    self.highTemperatureNotificationsEnabled = false
                    UserDefaults.standard.set(
                        false,
                        forKey: ThermalAlertSettings.notificationsEnabledKey
                    )
                    self.message = fanBarText(
                        "未获得通知权限，请在系统设置中允许 FanBar 发送通知",
                        "Notification permission was not granted. Allow FanBar notifications in System Settings."
                    )
                    return
                }

                self.highTemperatureNotificationsEnabled = true
                self.thermalAlertMonitor.reset()
                UserDefaults.standard.set(
                    true,
                    forKey: ThermalAlertSettings.notificationsEnabledKey
                )
                if let latest = self.latestThermalReading() {
                    self.evaluateThermalAlerts(using: latest)
                }
            }
        }
    }

    private func enableTemperatureCurve() {
        guard helperState == .enabled, !isBusy else {
            message = fanBarText("请先启用并批准控制服务", "Enable and approve the control service first")
            return
        }
        guard let reading = latestThermalReading(),
              let temperature = controlTemperature(from: reading) else {
            message = fanBarText("未读取到可用于智能温控的芯片温度", "No chip temperature is available for smart cooling")
            return
        }

        let fraction = temperatureCurve.fraction(at: temperature)
        isBusy = true
        message = fanBarText("正在开启智能温控…", "Enabling smart cooling…")
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
                message = fanBarFormat(
                    "智能温控开启失败：%@",
                    "Unable to enable smart cooling: %@",
                    error.localizedDescription
                )
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
                message = fanBarText("温度传感器不可用，正在恢复系统控制…", "Temperature sensor unavailable; restoring system control…")
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
                self.message = fanBarFormat(
                    "智能温控更新失败：%@",
                    "Smart cooling update failed: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func controlTemperature(from reading: ThermalReading) -> Double? {
        [reading.cpuCelsius, reading.gpuCelsius].compactMap { $0 }.max()
    }

    private func evaluateThermalAlerts(using reading: ThermalReading) {
        guard highTemperatureNotificationsEnabled,
              !isRequestingHighTemperatureNotificationPermission else {
            thermalAlertMonitor.reset()
            return
        }

        let alerts = thermalAlertMonitor.alerts(for: reading)
        guard !alerts.isEmpty else { return }

        let details = alerts.map {
            fanBarFormat(
                "%@ %.0f°C",
                "%@ %.0f°C",
                $0.sensor.title,
                $0.temperatureCelsius
            )
        }.joined(separator: fanBarText("、", ", "))
        let content = UNMutableNotificationContent()
        content.title = fanBarText("FanBar 高温预警", "FanBar High Temperature Warning")
        content.body = fanBarFormat(
            "检测到 %@，已达到 %.0f°C 高温阈值。请检查当前负载和散热。",
            "%@ reached the high-temperature threshold of %.0f°C. Check the current workload and cooling.",
            details,
            ThermalAlertSettings.thresholdCelsius
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ThermalAlertSettings.notificationIdentifierPrefix).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { error in
            if let error {
                NSLog("FanBar high-temperature notification failed: %@", error.localizedDescription)
            }
        }
    }

    private func latestThermalReading() -> ThermalReading? {
        if let latest = temperatureHistory.last { return latest }
        return localClient?.thermalReading()
    }

    private func updateCurveMessage() {
        guard let temperature = curveTemperatureCelsius,
              let fraction = curveOutputFraction else { return }
        message = fanBarFormat(
            "智能温控：%.0f°C · 最大转速 %.0f%%",
            "Smart cooling: %.0f°C · %.0f%% maximum RPM",
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
        message = fanBarText("正在恢复系统控制…", "Restoring system control…")
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.restoreAutomatic()
                mode = .automatic
                clearTemperatureCurveState()
                clearAutomaticRestore()
                message = triggeredByTimer
                    ? fanBarText("定时结束，已恢复 macOS 自动控制", "Timer ended; macOS automatic control restored")
                    : fanBarText("已恢复 macOS 自动控制", "macOS automatic control restored")
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
            } catch {
                message = fanBarFormat("恢复失败：%@", "Restore failed: %@", error.localizedDescription)
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
                    self.message = fanBarText("请在系统设置中批准新版控制服务", "Approve the updated control service in System Settings")
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
                self.message = fanBarText("控制服务更新失败，请重新打开 FanBar", "Control service update failed; reopen FanBar")
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
        guard reading.cpuCelsius != nil
            || reading.gpuCelsius != nil
            || reading.ssdCelsius != nil
            || reading.batteryCelsius != nil else { return }
        temperatureHistory.append(reading)
        let earliestSampleDate = reading.sampledAt.addingTimeInterval(-TemperatureChart.historyDuration)
        temperatureHistory.removeAll { $0.sampledAt < earliestSampleDate }
        if temperatureHistory.count > maximumTemperatureSamples {
            temperatureHistory.removeFirst(temperatureHistory.count - maximumTemperatureSamples)
        }
    }
}
