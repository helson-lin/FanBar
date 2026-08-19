import AppKit
import FanBarShared
import Foundation
import UserNotifications

/// Determines whether launchd still points at the current embedded helper.
/// Moving an app invalidates a BundleProgram registration just as surely as
/// replacing its helper binary, even when the build number stays unchanged.
enum HelperMigrationPolicy {
    static func requiresMigration(
        currentBuildVersion: String,
        currentBundlePath: String,
        savedBuildVersion: String?,
        savedBundlePath: String?
    ) -> Bool {
        savedBuildVersion != currentBuildVersion || savedBundlePath != currentBundlePath
    }
}

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
        /// Temperature-curve control using the selected panel cooling preset’s curve.
        case temperatureCurve
        case fixed(Int)
    }

    /// Drives the menu-bar icon animation for user-visible mode switches.
    /// Silent re-applies (e.g. after wake) never emit these signals.
    enum SwitchFeedbackSignal: Equatable {
        case began
        case ended(successfully: Bool)
    }

    /// Feedback scoped to the mode controls. The global header keeps the same
    /// message as a fallback, while this state lets the menu present it beside
    /// the preset that caused the action.
    struct ModeActionFeedback: Equatable {
        enum Kind: Equatable {
            case inProgress
            case failure
        }

        let kind: Kind
        let message: String
        /// Connection failures can be resolved from Login Items settings.
        let offersHelperSettings: Bool

        init(kind: Kind, message: String, offersHelperSettings: Bool = false) {
            self.kind = kind
            self.message = message
            self.offersHelperSettings = offersHelperSettings
        }
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
    /// Active smart-cooling curve (user-editable; persisted via FanCurvePreferences).
    @Published private(set) var curveProfile: FanCurveProfile
    /// Panel cooling preset whose curve is active for editing / smart mode.
    @Published private(set) var curveCoolingPreset: FanCoolingPreset
    /// Per–panel-preset stored curves.
    private var curvePresetSlots: [FanCoolingPreset: FanCurveProfile]
    @Published private(set) var highTemperatureNotificationsEnabled: Bool
    @Published private(set) var isRequestingHighTemperatureNotificationPermission = false
    @Published private(set) var switchFeedback: SwitchFeedbackSignal?
    @Published private(set) var modeActionFeedback: ModeActionFeedback?

    private var localClient: SMCClient?
    private let helperClient = HelperClient()
    private let helperService = FanBarServiceManager()
    private let loginItemService = FanBarLoginItemManager()
    private var refreshTimer: Timer?
    private var automaticRestoreTask: Task<Void, Never>?
    private var curveUpdateTask: Task<Void, Never>?
    /// When a profile edit arrives while a hardware write is in flight, re-apply once it finishes.
    private var pendingCurveHardwareApply = false
    private var curveMissingTemperatureSamples = 0
    private var wakeObserver: NSObjectProtocol?
    private var helperMigrationAttempted = false
    private var highTemperatureNotificationRequestID = 0
    private var thermalAlertMonitor = ThermalAlertMonitor(
        thresholdCelsius: ThermalAlertSettings.thresholdCelsius
    )
    /// Optional for unit-test hosts that are not application bundles; the app
    /// always uses the system notification center through the default value.
    private let notificationCenter: UNUserNotificationCenter?
    private let notificationDelegate = ThermalNotificationDelegate()
    private let automaticRestoreTestInterval: TimeInterval?
    // Ten minutes of readings at the two-second refresh cadence used below.
    private let maximumTemperatureSamples = 300
    private let automaticRestorePreferenceKey = "fanbar.automaticRestoreDuration"
    private let helperBuildVersionPreferenceKey = "fanbar.helperBuildVersion"
    private let helperBundlePathPreferenceKey = "fanbar.helperBundlePath"
    private let helperBuildVersion: String
    private let helperBundlePath: String
    private let curveUpdateDeadband: Float = 0.02

    var statusIcon: String {
        mode == .automatic ? "fan" : "fan.fill"
    }

    init(
        automaticRestoreTestInterval: TimeInterval? = nil,
        notificationCenter: UNUserNotificationCenter? = UNUserNotificationCenter.current()
    ) {
        self.automaticRestoreTestInterval = automaticRestoreTestInterval
        self.notificationCenter = notificationCenter
        let curveSnapshot = FanCurvePreferences.load()
        curveProfile = curveSnapshot.profile
        curveCoolingPreset = curveSnapshot.coolingPreset
        curvePresetSlots = curveSnapshot.slots
        highTemperatureNotificationsEnabled = UserDefaults.standard.bool(
            forKey: ThermalAlertSettings.notificationsEnabledKey
        )
        helperBuildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        helperBundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        if let savedValue = UserDefaults.standard.object(
            forKey: automaticRestorePreferenceKey
        ) as? Int,
            let savedDuration = AutomaticRestoreDuration(rawValue: savedValue)
        {
            automaticRestoreDuration = savedDuration
        }
        notificationCenter?.delegate = notificationDelegate
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
            let failure = fanBarText(
                "请先启用并批准控制服务",
                "Enable and approve the control service first"
            )
            message = failure
            failModeAction(failure)
            return
        }
        isBusy = true
        if resetsAutomaticRestore { switchFeedback = .began }
        let progress = fanBarFormat("正在切换到 %d RPM…", "Switching to %d RPM…", rpm)
        message = progress
        beginModeAction(progress)
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
                clearModeActionFeedback()
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: true) }
            } catch {
                let failure = fanBarFormat(
                    "控制失败：%@",
                    "Control failed: %@",
                    error.localizedDescription
                )
                message = failure
                failModeAction(
                    failure,
                    offersHelperSettings: helperSettingsActionNeeded(for: error)
                )
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: false) }
            }
            isBusy = false
        }
    }

    /// Activates a panel cooling preset by running its temperature curve (menu entry).
    func setCoolingPreset(_ preset: FanCoolingPreset) {
        selectCoolingCurvePreset(preset, enableControl: true, resetsAutomaticRestore: true)
    }

    func setAutomatic() {
        restoreAutomatic(triggeredByTimer: false)
    }

    /// Enables smart curve control for the currently selected panel preset.
    func setTemperatureCurveEnabled(_ enabled: Bool) {
        if enabled {
            selectCoolingCurvePreset(
                curveCoolingPreset,
                enableControl: true,
                resetsAutomaticRestore: true
            )
        } else {
            setAutomatic()
        }
    }

    /// Updates the active panel preset’s curve in place and persists that slot.
    func setCurveProfile(_ profile: FanCurveProfile) {
        setCurveProfile(profile, for: curveCoolingPreset)
    }

    /// Returns a preset's latest curve without changing which preset is shown.
    func curveProfile(for preset: FanCoolingPreset) -> FanCurveProfile {
        if preset == curveCoolingPreset {
            return curveProfile
        }
        return (curvePresetSlots[preset] ?? preset.factoryCurve).sanitized()
    }

    /// Replaces one stored preset without unexpectedly switching the editor.
    /// This is used by Undo when the user has moved to another preset meanwhile.
    func setCurveProfile(_ profile: FanCurveProfile, for preset: FanCoolingPreset) {
        let sanitized = profile.sanitized()
        curvePresetSlots[preset] = sanitized
        if preset == curveCoolingPreset {
            curveProfile = sanitized
        }
        FanCurvePreferences.save(slots: curvePresetSlots, selection: curveCoolingPreset)
        if preset == curveCoolingPreset {
            scheduleCurveHardwareApply()
        }
    }

    /// Applies a curve replacement and registers its inverse so the standard
    /// macOS Undo/Redo commands remain available after an automatic save.
    func replaceCurveProfile(
        _ profile: FanCurveProfile,
        for preset: FanCoolingPreset,
        registeringUndoWith undoManager: UndoManager?,
        actionName: String
    ) {
        let previous = curveProfile(for: preset)
        let replacement = profile.sanitized()
        guard previous != replacement else { return }

        setCurveProfile(replacement, for: preset)
        guard let undoManager else { return }
        // NSUndoManager runs this @Sendable handler on the registering thread
        // (main for UI). Assume the main actor so Swift 6 accepts the hop.
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.replaceCurveProfile(
                    previous,
                    for: preset,
                    registeringUndoWith: undoManager,
                    actionName: actionName
                )
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Switch which panel preset’s curve is being edited (settings). Optionally start control.
    func selectCoolingCurvePreset(
        _ preset: FanCoolingPreset,
        enableControl: Bool = false,
        resetsAutomaticRestore: Bool = false
    ) {
        let targetProfile = curveProfile(for: preset)
        if enableControl || mode == .temperatureCurve {
            enableTemperatureCurve(
                preset: preset,
                profile: targetProfile,
                resetsAutomaticRestore: resetsAutomaticRestore
            )
        } else {
            completeCurveActivation(
                preset: preset,
                profile: targetProfile,
                succeeded: true
            )
        }
    }

    /// Commits a prepared curve selection only after its hardware activation
    /// succeeds. Kept internal so the transaction boundary remains testable.
    func completeCurveActivation(
        preset: FanCoolingPreset,
        profile: FanCurveProfile,
        succeeded: Bool
    ) {
        guard succeeded, preset != curveCoolingPreset else { return }
        curvePresetSlots[curveCoolingPreset] = curveProfile.sanitized()
        let sanitized = profile.sanitized()
        curveCoolingPreset = preset
        curveProfile = sanitized
        curvePresetSlots[preset] = sanitized
        FanCurvePreferences.save(slots: curvePresetSlots, selection: preset)
    }

    /// Restores the factory curve for the active panel preset only.
    func resetActiveCurvePresetToFactory(
        undoManager: UndoManager? = nil,
        actionName: String = ""
    ) {
        let preset = curveCoolingPreset
        replaceCurveProfile(
            curveProfile.resettingCurveToFactory(for: preset),
            for: preset,
            registeringUndoWith: undoManager,
            actionName: actionName
        )
    }

    func setCurveHysteresisCelsius(_ value: Double) {
        var next = curveProfile
        next.hysteresisCelsius = value
        setCurveProfile(next)
    }

    func setCurveMaxFractionStep(_ value: Float) {
        var next = curveProfile
        next.maxFractionStepPerUpdate = value
        setCurveProfile(next)
    }

    private func scheduleCurveHardwareApply() {
        guard mode == .temperatureCurve, !isBusy else { return }
        if curveUpdateTask != nil {
            pendingCurveHardwareApply = true
            return
        }
        if let reading = latestThermalReading() {
            updateTemperatureCurve(using: reading, force: true)
        }
    }

    func setCurveSensor(_ sensor: FanCurveSensor) {
        var next = curveProfile
        next.sensor = sensor
        setCurveProfile(next)
    }

    func updateCurvePoint(id: UUID, celsius: Double? = nil, fraction: Float? = nil) {
        var next = curveProfile
        guard let index = next.points.firstIndex(where: { $0.id == id }) else { return }
        if let celsius { next.points[index].celsius = celsius }
        if let fraction { next.points[index].fraction = fraction }
        setCurveProfile(next)
    }

    func addCurvePoint() {
        var next = curveProfile
        guard next.points.count < FanCurveProfile.maximumPointCount else { return }
        let last = next.points.max(by: { $0.celsius < $1.celsius })
        let celsius = min(
            (last?.celsius ?? 60) + 5,
            FanCurveProfile.maximumCelsius
        )
        let fraction = min(
            max(last?.fraction ?? 0.5, FanCurveProfile.minimumFraction),
            FanCurveProfile.maximumFraction
        )
        next.points.append(FanCurvePoint(celsius: celsius, fraction: fraction))
        setCurveProfile(next)
    }

    func removeCurvePoint(id: UUID) {
        var next = curveProfile
        guard next.points.count > FanCurveProfile.minimumPointCount else { return }
        next.points.removeAll { $0.id == id }
        setCurveProfile(next)
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
        guard let notificationCenter else {
            isRequestingHighTemperatureNotificationPermission = false
            highTemperatureNotificationsEnabled = false
            return
        }
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

    private func enableTemperatureCurve(
        preset: FanCoolingPreset,
        profile: FanCurveProfile,
        resetsAutomaticRestore: Bool = true
    ) {
        guard helperState == .enabled, !isBusy else {
            let failure = fanBarText(
                "请先启用并批准控制服务",
                "Enable and approve the control service first"
            )
            message = failure
            failModeAction(failure)
            return
        }
        guard let reading = latestThermalReading(),
              let temperature = controlTemperature(from: reading, profile: profile) else {
            let failure = fanBarFormat(
                "未读取到可用于%@温控的温度来源",
                "No temperature is available for %@ curve control",
                profile.sensor.title
            )
            message = failure
            failModeAction(failure)
            return
        }

        // Initial activation intentionally skips hysteresis and rate limiting.
        let fraction = profile.fraction(at: temperature)
        isBusy = true
        if resetsAutomaticRestore { switchFeedback = .began }
        let progress = fanBarFormat(
            "正在切换到%@温控…",
            "Switching to %@ curve…",
            preset.title
        )
        message = progress
        beginModeAction(progress)
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setCoolingFraction(fraction)
                completeCurveActivation(
                    preset: preset,
                    profile: profile,
                    succeeded: true
                )
                mode = .temperatureCurve
                curveTemperatureCelsius = temperature
                curveOutputFraction = fraction
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                updateCurveMessage()
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
                clearModeActionFeedback()
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: true) }
            } catch {
                clearTemperatureCurveState()
                let failure = fanBarFormat(
                    "%@温控开启失败：%@",
                    "Unable to enable %@ curve: %@",
                    preset.title,
                    error.localizedDescription
                )
                message = failure
                failModeAction(
                    failure,
                    offersHelperSettings: helperSettingsActionNeeded(for: error)
                )
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: false) }
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

        let fraction = targetCurveFraction(for: temperature, force: force)
        curveTemperatureCelsius = temperature
        if !force,
           let previous = curveOutputFraction,
           abs(fraction - previous) < curveUpdateDeadband {
            updateCurveMessage()
            return
        }

        curveUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.curveUpdateTask = nil
                if self.pendingCurveHardwareApply {
                    self.pendingCurveHardwareApply = false
                    self.scheduleCurveHardwareApply()
                }
            }
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

    /// Applies persistent falling-edge hysteresis, then rate-limits the step.
    /// `force` skips both for profile edits and wake re-application.
    private func targetCurveFraction(for temperature: Double, force: Bool) -> Float {
        FanCurveControlTarget.fraction(
            profile: curveProfile,
            temperature: temperature,
            previousFraction: curveOutputFraction,
            force: force
        )
    }

    private func controlTemperature(
        from reading: ThermalReading,
        profile: FanCurveProfile? = nil
    ) -> Double? {
        switch (profile ?? curveProfile).sensor {
        case .maxChip:
            return [reading.cpuCelsius, reading.gpuCelsius].compactMap { $0 }.max()
        case .cpu:
            return reading.cpuCelsius
        case .gpu:
            return reading.gpuCelsius
        case .ssd:
            return reading.ssdCelsius
        }
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
        notificationCenter?.add(request) { error in
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
            "%@：%.0f°C · %.0f%%",
            "%@: %.0f°C · %.0f%%",
            curveCoolingPreset.title,
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
        switchFeedback = .began
        let progress = fanBarText("正在恢复系统控制…", "Restoring system control…")
        message = progress
        beginModeAction(progress)
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
                clearModeActionFeedback()
                switchFeedback = .ended(successfully: true)
            } catch {
                let failure = fanBarFormat(
                    "恢复失败：%@",
                    "Restore failed: %@",
                    error.localizedDescription
                )
                message = failure
                failModeAction(
                    failure,
                    offersHelperSettings: helperSettingsActionNeeded(for: error)
                )
                switchFeedback = .ended(successfully: false)
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

    /// Starts/replaces local mode feedback so a second attempt immediately
    /// supersedes an older error instead of stacking transient banners.
    func beginModeAction(_ message: String) {
        modeActionFeedback = ModeActionFeedback(kind: .inProgress, message: message)
    }

    func failModeAction(_ message: String, offersHelperSettings: Bool = false) {
        modeActionFeedback = ModeActionFeedback(
            kind: .failure,
            message: message,
            offersHelperSettings: offersHelperSettings
        )
    }

    /// Only transport failures point to authorization. SMC validation errors
    /// remain ordinary failures and should not send users to System Settings.
    private func helperSettingsActionNeeded(for error: Error) -> Bool {
        (error as? HelperClientError)?.isConnectionFailure == true
    }

    func clearModeActionFeedback() {
        modeActionFeedback = nil
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
        let savedBundlePath = UserDefaults.standard.string(
            forKey: helperBundlePathPreferenceKey
        )
        guard HelperMigrationPolicy.requiresMigration(
            currentBuildVersion: helperBuildVersion,
            currentBundlePath: helperBundlePath,
            savedBuildVersion: savedVersion,
            savedBundlePath: savedBundlePath
        ) else {
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
            UserDefaults.standard.set(
                helperBundlePath,
                forKey: helperBundlePathPreferenceKey
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
                UserDefaults.standard.set(
                    self.helperBundlePath,
                    forKey: self.helperBundlePathPreferenceKey
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
