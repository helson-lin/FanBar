// swiftlint:disable file_length type_body_length
// Legacy size debt: split this file before removing the disable above.
import AppKit
import FanBarShared
import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

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

        /// What the failure banner's one button does.
        enum Recovery: Equatable {
            case retry(RetryTarget)
            case openHelperSettings
            case enableHelper
            case chooseTemperatureSource
        }

        enum RetryTarget: Equatable {
            case preset(CoolingPresetID)
            case fixed(Int)
            case restore
        }

        let kind: Kind
        /// The complete sentence, error included: the CLI and the status line use it.
        private let localizedMessage: LocalizedControlText
        var message: String { localizedMessage.text }
        /// The banner's first line, said in terms of the result.
        private let localizedTitle: LocalizedControlText?
        var title: String { localizedTitle?.text ?? message }
        /// The banner's second line: who is driving the fans now.
        private let localizedSafety: LocalizedControlText?
        var safety: String? { localizedSafety?.text }
        /// The fans were left where the user did not want them.
        let isRisk: Bool
        let recovery: Recovery?
        /// The underlying error, kept for the details popover and bug reports.
        let detail: String?
        /// Connection failures can be resolved from Login Items settings.
        var offersHelperSettings: Bool { recovery == .openHelperSettings }

        init(kind: Kind, message: String, offersHelperSettings: Bool = false) {
            self.init(
                kind: kind,
                localizedMessage: LocalizedControlText { message },
                offersHelperSettings: offersHelperSettings
            )
        }

        init(kind: Kind, localizedMessage: LocalizedControlText, offersHelperSettings: Bool = false) {
            self.init(
                kind: kind,
                localizedMessage: localizedMessage,
                recovery: offersHelperSettings ? .openHelperSettings : nil
            )
        }

        init(
            kind: Kind,
            localizedMessage: LocalizedControlText,
            title: LocalizedControlText? = nil,
            safety: LocalizedControlText? = nil,
            isRisk: Bool = false,
            recovery: Recovery? = nil,
            detail: String? = nil
        ) {
            self.kind = kind
            self.localizedMessage = localizedMessage
            localizedTitle = title
            localizedSafety = safety
            self.isRisk = isRisk
            self.recovery = recovery
            self.detail = detail
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

    @Published private(set) var compatibilityObservation: CompatibilityObservation?
    // Recorded only by user-started control and the compatibility test, so a routine
    // background curve write can never overwrite a deliberate result.
    @Published private(set) var manualControlEvidence: CompatibilityControlEvidence = .unverified {
        didSet { persistCompatibilityControlEvidence() }
    }

    @Published private(set) var curveControlEvidence: CompatibilityControlEvidence = .unverified {
        didSet { persistCompatibilityControlEvidence() }
    }

    // Assigned just before the matching evidence, whose didSet persists both.
    @Published private(set) var manualControlFailure: CompatibilityControlFailure?
    @Published private(set) var curveControlFailure: CompatibilityControlFailure?

    @Published private(set) var controlEvidenceRecordedAt: Date?
    private let compatibilityHistoryStore: CompatibilityControlHistoryStore?
    private var isLoadingControlHistory = true
    @Published private(set) var isTestingCompatibilityControl = false
    @Published private(set) var compatibilityControlNeedsRestore = false
    @Published private var compatibilityControlText: LocalizedControlText?
    var compatibilityControlMessage: String? { compatibilityControlText?.text }
    private var compatibilityControlTask: Task<Void, Never>?
    lazy var compatibilityDevice = CompatibilityDevice.current(helperVersion: helperBuildVersion)

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var mode: Mode = .automatic
    @Published private var messageText = LocalizedControlText { fanBarText("正在读取风扇…", "Reading fans…") }
    var message: String { messageText.text }
    @Published private(set) var isAvailable = false
    @Published private(set) var isBusy = false
    @Published private(set) var helperState: HelperState = .notRegistered
    @Published private(set) var temperatureHistory: [ThermalReading] = []
    @Published private(set) var usage = SystemUsage()
    /// CPU and GPU utilization over the last minute, oldest first, for the panel's trend lines.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    /// Persisted default applied each time control leaves Automatic.
    @Published private(set) var defaultAutomaticRestoreDuration: AutomaticRestoreDuration = .thirtyMinutes
    /// The current manual session's duration; panel edits change only this.
    @Published private(set) var automaticRestoreDuration: AutomaticRestoreDuration = .thirtyMinutes
    @Published private(set) var automaticRestoreDeadline: Date?
    @Published private(set) var curveTemperatureCelsius: Double?
    @Published private(set) var curveOutputFraction: Float?
    /// Active smart-cooling curve (user-editable; persisted via FanCurvePreferences).
    @Published private(set) var curveProfile: FanCurveProfile
    /// Preset (built-in or custom) whose curve is active for editing / smart mode.
    @Published private(set) var curveCoolingPreset: CoolingPresetID
    /// Stored curves of the built-in presets.
    private var curvePresetSlots: [FanCoolingPreset: FanCurveProfile]
    /// User-created presets in creation order; each carries its own curve.
    @Published private(set) var customPresets: [CustomCoolingPreset]
    @Published private(set) var highTemperatureNotificationsEnabled: Bool
    /// Last RPM the user entered by hand; offered again in the Fixed menu.
    @Published private(set) var customFixedRPM: Int? = {
        let stored = UserDefaults.standard.integer(forKey: FanController.customFixedRPMKey)
        return stored > 0 ? stored : nil
    }()

    @Published private(set) var highTemperatureThresholdCelsius = ThermalAlertSettings.thresholdCelsius
    @Published private(set) var highTemperatureAlertSound = ThermalAlertSettings.sound
    @Published private(set) var isRequestingHighTemperatureNotificationPermission = false
    @Published private(set) var switchFeedback: SwitchFeedbackSignal?
    @Published private(set) var modeActionFeedback: ModeActionFeedback?
    /// What FanBar did, or is about to do, on its own; shown under the mode strip.
    @Published private(set) var controlNotice: ControlNotice?
    /// Set once the helper reports that this Mac's SMC has no fan mode key.
    @Published private(set) var manualControlUnsupported = false
    @Published private(set) var handBackRemindersEnabled = HandBackNotification.remindersEnabled
    /// With the panel open, notices stay in the panel instead of becoming notifications.
    private(set) var isPanelVisible = false
    /// Opens the panel when a hand-back notification is clicked.
    var showPanel: (() -> Void)?

    /// Describes the per-fan target produced by the active curve output.
    /// A single range keeps the compact UI useful when fans have different
    /// hardware limits while making clear that this is a target, not a live
    /// RPM reading.
    var curveOutputSummary: String? {
        guard let fraction = curveOutputFraction,
              let range = Self.curveTargetRange(fraction: fraction, fans: fans) else {
            return nil
        }
        let minimum = range.lowerBound
        let maximum = range.upperBound
        let rpm = minimum == maximum
            ? fanBarFormat("%@ RPM", "%@ RPM", FanBarNumberFormatter.grouped(minimum))
            : fanBarFormat(
                "%@–%@ RPM",
                "%@–%@ RPM",
                FanBarNumberFormatter.grouped(minimum),
                FanBarNumberFormatter.grouped(maximum)
            )
        return fanBarFormat(
            "目标 %@（曲线输出 %.0f%%）",
            "Target %@ (curve output %.0f%%)",
            rpm,
            fraction * 100
        )
    }

    /// Lowest and highest per-fan target the helper will write for a curve
    /// fraction, using the same rule as the hardware driver.
    nonisolated static func curveTargetRange(
        fraction: Float,
        fans: [FanReading]
    ) -> ClosedRange<Int>? {
        let targets = fans.map {
            Int(FanCoolingTarget.targetRPM(
                fraction: fraction,
                minimum: Float($0.minimumRPM),
                maximum: Float($0.maximumRPM)
            ))
        }
        guard let minimum = targets.min(), let maximum = targets.max() else {
            return nil
        }
        return minimum...maximum
    }

    private let makeReadingSource: () throws -> FanReadingSource
    private let makeDiagnosticSource: @Sendable () throws -> FanReadingSource
    private let queryRunningHelperBuild: @Sendable () async -> HelperBuildQuery
    private var localClient: FanReadingSource?
    private let helperClient = HelperClient()
    private let helperService = FanBarServiceManager()
    private let loginItemService = FanBarLoginItemManager()
    private var refreshTimer: Timer?
    /// Optional CSV log fed by the same readings as the menu; see docs/design/temperature-logging.md.
    let temperatureLog = TemperatureLogRecorder()
    private var diagnosticSamples: [DiagnosticSample] = []
    private let widgetSnapshotDestination: WidgetSnapshotDestination
    private var lastWidgetTimelineReloadDate: Date?
    private var lastWidgetSnapshotPublishDate: Date?
    /// Last snapshot actually written to disk, ignoring `updatedAt`, so the
    /// 2s refresh timer does not re-write an unchanged snapshot every tick.
    private var lastPublishedWidgetSnapshot: FanBarWidgetSnapshot?
    private var automaticRestoreTask: Task<Void, Never>?
    /// Fires one minute before `automaticRestoreTask`.
    private var automaticRestoreWarningTask: Task<Void, Never>?
    /// Asked once per launch, when a timed manual mode first starts.
    private var requestedHandBackNotificationPermission = false
    private var curveUpdateTask: Task<Void, Never>?
    /// When a profile edit arrives while a hardware write is in flight, re-apply once it finishes.
    private var pendingCurveHardwareApply = false
    private var curveMissingTemperatureSamples = 0
    /// Consecutive hardware failures of the curve loop; drives the retry backoff.
    private var curveConsecutiveFailures = 0
    /// Next wall-clock time the curve loop may write again after a failure.
    private var curveRetryNotBefore = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    /// Time left on the restore timer when the Mac went to sleep; standby
    /// does not count toward the manual session.
    private var automaticRestoreRemainingAtSleep: TimeInterval?
    private var reapplyTask: Task<Void, Never>?
    private var helperMigrationAttempted = false
    private var highTemperatureNotificationRequestID = 0
    private var thermalAlertMonitor = ThermalAlertMonitor(
        thresholdCelsius: ThermalAlertSettings.thresholdCelsius
    )
    private var thermalAlertSoundGate = ThermalAlertSoundGate()
    /// Optional for unit-test hosts that are not application bundles; the app
    /// always uses the system notification center through the default value.
    private let notificationCenter: UNUserNotificationCenter?
    private let notificationDelegate = ThermalNotificationDelegate()
    private let automaticRestoreTestInterval: TimeInterval?
    // One hour of readings at the two-second refresh cadence used below.
    private let maximumTemperatureSamples = 2_000
    /// The full hour is about 1,800 samples, so persisting on every tick would rewrite
    /// the whole defaults entry every two seconds. Saving every 30 seconds loses at most
    /// that much history on a crash.
    private static let temperatureHistorySaveInterval: TimeInterval = 30
    private var lastTemperatureHistorySaveDate: Date?
    private let readUsage: () -> SystemUsage
    /// Sixty seconds at the two-second refresh cadence.
    static let usageHistorySampleCount = 30

    private static func appendUsage(_ value: Double?, to history: inout [Double]) {
        guard let value else { return }
        history.append(value)
        if history.count > usageHistorySampleCount {
            history.removeFirst(history.count - usageHistorySampleCount)
        }
    }

    private let automaticRestorePreferenceKey = "fanbar.automaticRestoreDuration"
    private let helperBuildVersionPreferenceKey = "fanbar.helperBuildVersion"
    private let helperBundlePathPreferenceKey = "fanbar.helperBundlePath"
    private let helperBuildVersion: String
    private let helperBundlePath: String
    private let curveUpdateDeadband: Float = 0.02

    /// Drives the solid-hub menu bar glyph: any mode other than macOS's own
    /// automatic control counts as FanBar being in charge.
    var isManualStatus: Bool {
        mode != .automatic
    }

    /// Where refresh ticks publish the widget snapshot. A test run must pass
    /// `.disabled` (or a temporary directory): the default writes into the
    /// real `~/Library/Group Containers` App Group container, and `swift test`
    /// must not leave anything behind outside the build directory.
    enum WidgetSnapshotDestination {
        case sharedContainer
        case directory(URL)
        case disabled
    }

    // Initializes the existing controller dependency graph and restores version-scoped evidence.
    // swiftlint:disable:next function_body_length
    init(
        automaticRestoreTestInterval: TimeInterval? = nil,
        notificationCenter: UNUserNotificationCenter? = UNUserNotificationCenter.current(),
        widgetSnapshotDestination: WidgetSnapshotDestination = .sharedContainer,
        makeReadingSource: @escaping () throws -> FanReadingSource = { try SMCClient() },
        makeDiagnosticSource: @escaping @Sendable () throws -> FanReadingSource = { try SMCClient() },
        queryRunningHelperBuild: @escaping @Sendable () async -> HelperBuildQuery = { await HelperClient.queryRunningBuild() },
        compatibilityHistoryStore: CompatibilityControlHistoryStore? = nil,
        readUsage: (() -> SystemUsage)? = nil,
        refreshInterval: TimeInterval? = 2
    ) {
        let usageReader = SystemUsageReader()
        self.readUsage = readUsage ?? { usageReader.sample() }
        self.makeReadingSource = makeReadingSource
        self.makeDiagnosticSource = makeDiagnosticSource
        self.queryRunningHelperBuild = queryRunningHelperBuild
        if let compatibilityHistoryStore {
            self.compatibilityHistoryStore = compatibilityHistoryStore
        } else if case .sharedContainer = widgetSnapshotDestination {
            self.compatibilityHistoryStore = CompatibilityControlHistoryStore(defaults: .standard)
        } else {
            self.compatibilityHistoryStore = nil
        }
        self.automaticRestoreTestInterval = automaticRestoreTestInterval
        self.notificationCenter = notificationCenter
        self.widgetSnapshotDestination = widgetSnapshotDestination
        CoolingPresetPreferences.migrateIfNeeded()
        let curveSnapshot = FanCurvePreferences.load()
        curveProfile = curveSnapshot.profile
        curveCoolingPreset = curveSnapshot.selection
        curvePresetSlots = curveSnapshot.slots
        customPresets = curveSnapshot.customPresets
        highTemperatureNotificationsEnabled = UserDefaults.standard.bool(
            forKey: ThermalAlertSettings.notificationsEnabledKey
        )
        helperBuildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        helperBundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let historyDevice = CompatibilityDevice.current(helperVersion: helperBuildVersion)
        let recoversFromReceipts: Bool
        if case .sharedContainer = widgetSnapshotDestination {
            recoversFromReceipts = true
        } else {
            recoversFromReceipts = false
        }
        let savedHistory = self.compatibilityHistoryStore.flatMap { store in
            Self.loadControlHistory(for: historyDevice, store: store, recoversFromReceipts: recoversFromReceipts) {
                try CompatibilityReceiptStore().receipts()
            }
        }
        if let saved = savedHistory {
            manualControlFailure = saved.manualFailure
            curveControlFailure = saved.curveFailure
            manualControlEvidence = saved.manual
            curveControlEvidence = saved.curve
            controlEvidenceRecordedAt = saved.recordedAt
        }
        isLoadingControlHistory = false
        if case .disabled = widgetSnapshotDestination {
            temperatureHistory = []
        } else {
            temperatureHistory = TemperatureHistoryStore.load()
        }
        if let savedValue = UserDefaults.standard.object(
            forKey: automaticRestorePreferenceKey
        ) as? Int,
            let savedDuration = AutomaticRestoreDuration(rawValue: savedValue) {
            defaultAutomaticRestoreDuration = savedDuration
            automaticRestoreDuration = savedDuration
        }
        notificationCenter?.delegate = notificationDelegate
        notificationDelegate.onResponse = { [weak self] actionIdentifier, requestIdentifier in
            Task { @MainActor in
                self?.handleNotificationResponse(action: actionIdentifier, request: requestIdentifier)
            }
        }
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        refresh()
        if let refreshInterval {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        helperClient.onConnectionReset = { [weak self] in
            Task { @MainActor in self?.scheduleReapplyCurrentMode(after: 1) }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseAutomaticRestoreForSleep()
                self?.releaseFansForSleep()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumeAutomaticRestoreAfterWake()
                // The SMC may reset fan modes during sleep and answers slowly
                // right after wake; give it a moment before writing again.
                self.scheduleReapplyCurrentMode(after: 2)
            }
        }
    }

    private func pauseAutomaticRestoreForSleep() {
        guard let deadline = automaticRestoreDeadline else { return }
        automaticRestoreRemainingAtSleep = max(0, deadline.timeIntervalSinceNow)
        automaticRestoreTask?.cancel()
        automaticRestoreTask = nil
        // Rescheduled from the remaining time on wake, warning included.
        automaticRestoreWarningTask?.cancel()
        automaticRestoreWarningTask = nil
    }

    private func resumeAutomaticRestoreAfterWake() {
        guard let remaining = automaticRestoreRemainingAtSleep else { return }
        automaticRestoreRemainingAtSleep = nil
        guard mode != .automatic, automaticRestoreDuration != .never else { return }
        scheduleAutomaticRestore(interval: remaining)
    }

    /// Hands the fans to macOS right before sleep, without changing the user's
    /// mode; the held mode is re-applied after wake by the didWake observer.
    /// Sleeping with a forced fan state has been observed to leave the SMC
    /// rejecting every fan write after wake until reboot (issue #114), so the
    /// forced state never crosses the sleep boundary. Best effort: an in-flight
    /// curve write may still be queued ahead of this in the helper.
    private func releaseFansForSleep() {
        guard mode != .automatic, helperState == .enabled else { return }
        Task { [helperClient] in
            try? await helperClient.restoreAutomatic()
        }
    }

    private func scheduleReapplyCurrentMode(after delay: TimeInterval) {
        reapplyTask?.cancel()
        reapplyTask = Task { @MainActor [weak self] in
            // Retry a few times; the first write after wake or a reset can time out.
            for attempt in 0..<3 {
                let wait = attempt == 0 ? delay : 2
                do {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                guard self.isBusy || self.curveUpdateTask != nil else {
                    self.reapplyCurrentMode()
                    return
                }
            }
        }
    }

    private func reapplyCurrentMode() {
        switch mode {
        case .automatic:
            break
        case .temperatureCurve:
            if let reading = latestThermalReading() {
                updateTemperatureCurve(using: reading, force: true)
            }
        case .fixed(let rpm):
            applyFixedRPM(rpm, resetsAutomaticRestore: false)
        }
    }

    /// Seconds between service-status checks once both services are settled.
    /// Each check is a synchronous XPC round trip to the system's service
    /// daemon on the main thread, so it is too costly for every 2 s tick.
    private static let settledServiceStatusInterval: TimeInterval = 30
    private var lastServiceStatusRefresh = Date.distantPast

    /// Re-reads the helper and login item status now, e.g. when the panel opens.
    func refreshServiceStatus() {
        refreshHelperStatus()
        refreshLaunchAtLoginStatus()
        lastServiceStatusRefresh = Date()
    }

    func refresh() {
        // While a service still needs setup or approval, keep polling every
        // tick so approving it in System Settings shows up right away.
        let isSettled = helperState == .enabled && !launchAtLoginRequiresApproval
        if !isSettled
            || Date().timeIntervalSince(lastServiceStatusRefresh) >= Self.settledServiceStatusInterval {
            refreshServiceStatus()
        }
        // Usage comes from public system counters, so it still updates while the helper is unavailable.
        usage = readUsage()
        Self.appendUsage(usage.cpuFraction, to: &cpuHistory)
        Self.appendUsage(usage.gpuFraction, to: &gpuHistory)
        if localClient == nil {
            do {
                localClient = try makeReadingSource()
            } catch {
                recordDiagnosticSample(error: error)
                compatibilityObservation = CompatibilityObservation(
                    sampledAt: Date(), thermal: nil, fanCount: nil, connectionFailed: true
                )
                isAvailable = false
                messageText = LocalizedControlText { error.localizedDescription }
                return
            }
        }
        guard let localClient else { return }
        let thermal = localClient.thermalReading()
        appendTemperature(thermal)
        do {
            fans = try localClient.fans()
            temperatureLog.record(thermal: thermal, fans: fans, mode: mode)
            recordDiagnosticSample(thermal: thermal, fanCount: fans.count)
            compatibilityObservation = CompatibilityObservation(
                sampledAt: thermal.sampledAt, thermal: thermal, fanCount: fans.count, connectionFailed: false
            )
            helperClient.setExpectedFanCount(fans.count)
            evaluateThermalAlerts(using: thermal)
            publishWidgetSnapshot(thermal: thermal)
            if mode == .temperatureCurve {
                updateTemperatureCurve(using: thermal)
            }
            isAvailable = true
            if mode == .automatic {
                // Permission state has its own actionable row; keep the header focused on fan mode.
                messageText = LocalizedControlText { fanBarText("由 macOS 自动管理", "Managed automatically by macOS") }
            }
        } catch {
            // Fanless Macs report no fan keys; the temperatures read above are still worth logging.
            temperatureLog.record(thermal: thermal, fans: [], mode: mode)
            recordDiagnosticSample(thermal: thermal, error: error)
            compatibilityObservation = CompatibilityObservation(
                sampledAt: thermal.sampledAt, thermal: thermal, fanCount: nil, connectionFailed: false
            )
            // The IOKit connection can go stale across sleep; reopen next tick.
            self.localClient = nil
            isAvailable = false
            publishUnavailableWidgetSnapshot()
            messageText = LocalizedControlText { error.localizedDescription }
        }
    }

    /// Read-only diagnostic path: never refresh modes, register services or issue helper writes.
    func detectCompatibility() {
        do {
            if localClient == nil { localClient = try makeReadingSource() }
            guard let source = localClient else { return }
            let thermal = source.thermalReading()
            let count = try? source.fans().count
            compatibilityObservation = CompatibilityObservation(
                sampledAt: thermal.sampledAt, thermal: thermal, fanCount: count, connectionFailed: false
            )
            if count == nil { localClient = nil }
        } catch {
            compatibilityObservation = CompatibilityObservation(
                sampledAt: Date(), thermal: nil, fanCount: nil, connectionFailed: true
            )
        }
    }

    private func recordDiagnosticSample(thermal: ThermalReading? = nil, fanCount: Int? = nil, error: Error? = nil) {
        let code: Int32?
        if let smcError = error as? SMCError {
            switch smcError {
            case .unavailable(let value), .unsupportedKey(_, let value), .writeFailed(_, let value): code = value
            }
        } else {
            code = error == nil ? nil : -1
        }
        diagnosticSamples.append(DiagnosticSample(sampledAt: Date(), thermal: thermal,
            fanCount: fanCount, errorCode: code,
            stage: thermal == nil ? "connect" : fanCount == nil ? "fanRead" : "sample"))
        diagnosticSamples = Array(diagnosticSamples.suffix(30))
    }

    /// Explicit collection only. Does not call refresh(), change fan modes, or request authorization.
    /// Slow evidence is gathered off the main actor with a dedicated read-only SMC reader.
    func collectDiagnosticReport() async -> DiagnosticReport {
        let state: String
        switch helperState {
        case .enabled: state = "enabled"
        case .requiresApproval: state = "requiresApproval"
        case .notRegistered: state = "notRegistered"
        case .unavailable: state = "unavailable"
        }
        var report = DiagnosticReport(diagnosticID: UUID().uuidString.lowercased(),
            capturedAt: ISO8601DateFormatter().string(from: Date()), device: compatibilityDevice,
            helperState: state, probes: [])
        report.helperStateSource = "runtime"
        report.runtimeContext = DiagnosticRuntimeContext.current()
        report.recentSamples = diagnosticSamples.filter { Date().timeIntervalSince($0.sampledAt) <= 60 }
        let makeSource = makeDiagnosticSource
        async let backgroundEvidence = Task.detached(priority: .userInitiated) {
            DiagnosticBackgroundEvidence.collect(makeSource: makeSource)
        }.value
        report.runningHelper = await Self.runningHelper(state: helperState, query: queryRunningHelperBuild)
        let evidence = await backgroundEvidence
        report.runtimeEvents = RuntimeDiagnostics.shared.snapshot() + evidence.helperEvents
        report.helperLogAvailable = evidence.helperLogAvailable
        report.crashes = evidence.crashes
        report.crashLogAvailable = evidence.crashLogAvailable
        report.thermal = evidence.thermal
        report.fanCount = evidence.fanCount
        report.connectionErrorCode = evidence.connectionErrorCode
        report.probes = evidence.probes
        report.discovery = evidence.discovery
        return report
    }

    /// Saved control evidence for this device/version. Recovering it from report receipts reads
    /// the Keychain, so that is tried once per device/version, not on every launch.
    static func loadControlHistory(
        for device: CompatibilityDevice, store: CompatibilityControlHistoryStore, recoversFromReceipts: Bool,
        loadReceipts: () throws -> [CompatibilitySavedReceipt]
    ) -> CompatibilityControlHistory? {
        if let saved = store.load(for: device) { return saved }
        guard recoversFromReceipts, store.needsRecovery(for: device) else { return nil }
        store.markRecoveryAttempted(for: device)
        guard let receipts = try? loadReceipts(),
              let recovered = CompatibilityControlHistoryStore.recover(from: receipts, for: device) else { return nil }
        store.save(recovered)
        return recovered
    }

    /// Restoration failure outranks a control error, which outranks cancellation.
    static func compatibilityControlMessage(for result: CompatibilityControlTestResult) -> String {
        guard result.restored else {
            return fanBarFormat("恢复系统控制失败：%@。请点击“恢复系统控制”重试。",
                "Restoring system control failed: %@. Retry Restore System Control.",
                result.currentRestoreError ?? result.currentControlError ?? "unknown")
        }
        if let error = result.currentControlError {
            return fanBarFormat("控制测试失败：%@。已恢复系统自动控制。",
                "Control test failed: %@. System automatic control restored.", error)
        }
        if result.cancelled {
            return fanBarText("控制测试已取消，已恢复系统自动控制。", "Control test cancelled. System automatic control restored.")
        }
        return fanBarText("控制测试结束，已恢复系统自动控制。请查看各项结果。",
            "Control test finished; system automatic control restored. Review the results below.")
    }

    /// Ask only a registered, approved helper: diagnostics must never register or approve one.
    /// The query can make launchd start an enabled helper on demand, which changes no fan state.
    static func runningHelper(
        state: HelperState, query: @Sendable () async -> HelperBuildQuery
    ) async -> DiagnosticRunningHelper {
        DiagnosticRunningHelper(state == .enabled ? await query() : nil)
    }

    private func persistCompatibilityControlEvidence() {
        guard !isLoadingControlHistory, !isTestingCompatibilityControl, let compatibilityHistoryStore else { return }
        let record = CompatibilityControlHistory(device: compatibilityDevice, manual: manualControlEvidence,
            curve: curveControlEvidence, manualFailure: manualControlFailure, curveFailure: curveControlFailure,
            recordedAt: Date())
        compatibilityHistoryStore.save(record)
        controlEvidenceRecordedAt = record.recordedAt
    }

    /// Tests start only from system control, so restoration has one unambiguous target.
    func testCompatibilityControl() {
        guard !isBusy, helperState == .enabled, mode == .automatic else { return }
        isBusy = true
        isTestingCompatibilityControl = true
        compatibilityControlText = LocalizedControlText { fanBarText("正在测试控制能力并恢复系统控制…", "Testing control and restoring system control…") }
        compatibilityControlTask = Task {
            await finishPendingCurveUpdate()
            let fraction = latestThermalReading().flatMap { reading in
                controlTemperature(from: reading, profile: curveProfile).map { curveProfile.fraction(at: $0) }
            }
            let result = await CompatibilityControlTest.run(client: helperClient, curveFraction: fraction)
            compatibilityControlNeedsRestore = !result.restored
            if !Task.isCancelled {
                if result.manual != .unverified {
                    manualControlFailure = result.manualFailure
                    manualControlEvidence = result.manual
                }
                if result.curve != .unverified {
                    curveControlFailure = result.curveFailure
                    curveControlEvidence = result.curve
                }
            }
            compatibilityControlText = LocalizedControlText { Self.compatibilityControlMessage(for: result) }
            isTestingCompatibilityControl = false
            if !Task.isCancelled, result.manual != .unverified || result.curve != .unverified {
                persistCompatibilityControlEvidence()
            }
            isBusy = false
            compatibilityControlTask = nil
            detectCompatibility()
        }
    }

    func cancelCompatibilityControlTest() {
        compatibilityControlTask?.cancel()
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
                messageText = LocalizedControlText { fanBarText("请在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions") }
            }
        } catch {
            refreshLaunchAtLoginStatus()
            messageText = LocalizedControlText {
                fanBarFormat("无法更新登录项：%@", "Unable to update login item: %@", error.localizedDescription)
            }
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
                messageText = LocalizedControlText { fanBarText("请在“登录项与扩展”中允许 FanBar", "Allow FanBar in Login Items & Extensions") }
                helperService.openSettings()
            } else {
                messageText = LocalizedControlText { [state = helperState] in state.title }
            }
        } catch {
            refreshHelperStatus()
            messageText = LocalizedControlText {
                fanBarFormat("无法注册控制服务：%@", "Unable to register control service: %@", error.localizedDescription)
            }
            if helperState == .requiresApproval {
                helperService.openSettings()
            }
        }
    }

    func openHelperSettings() {
        helperService.openSettings()
    }

    static let customFixedRPMKey = "fanbar.customFixedRPM"
    static let fixedRPMPresets = [2500, 3500, 4500, 5500]

    /// The RPM range every fan can hold: from the highest fan minimum to the
    /// lowest fan maximum, so one target is valid for all fans. Nil until the
    /// fans have been read or when their ranges do not overlap.
    var fixedRPMRange: ClosedRange<Int>? {
        guard let lower = fans.map(\.minimumRPM).max(),
              let upper = fans.map(\.maximumRPM).min(),
              lower > 0, lower <= upper else { return nil }
        return lower...upper
    }

    func setFixedRPM(_ rpm: Int) {
        controlNotice = nil
        applyFixedRPM(rpm, resetsAutomaticRestore: true)
    }

    /// Applies a hand-entered RPM. Values outside the hardware range are
    /// rejected here too, not only in the editor.
    func setCustomFixedRPM(_ rpm: Int) {
        guard let range = fixedRPMRange, range.contains(rpm) else {
            let failure = LocalizedControlText { fanBarText("转速超出风扇支持的范围", "That RPM is outside the fans' supported range") }
            messageText = failure
            let title = fixedRPMRange.map { range in
                LocalizedControlText {
                    fanBarFormat(
                        "转速需在 %@–%@ RPM 之间",
                        "Choose %@–%@ RPM",
                        FanBarNumberFormatter.grouped(range.lowerBound),
                        FanBarNumberFormatter.grouped(range.upperBound)
                    )
                }
            }
            modeActionFeedback = ModeActionFeedback(
                kind: .failure,
                localizedMessage: failure,
                title: title,
                safety: LocalizedControlText { fanBarText("风扇保持原转速", "Fans keep their current speed") }
            )
            return
        }
        setFixedRPM(rpm)
    }

    private func applyFixedRPM(_ rpm: Int, resetsAutomaticRestore: Bool) {
        guard helperState == .enabled, !isBusy else {
            rejectSwitchBeforeRequest()
            return
        }
        isBusy = true
        if resetsAutomaticRestore { switchFeedback = .began }
        let progress = LocalizedControlText { fanBarFormat("正在切换到 %d RPM…", "Switching to %d RPM…", rpm) }
        messageText = progress
        beginModeAction(progress)
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setAllFans(rpm: rpm)
                manualControlFailure = nil
                manualControlEvidence = .requestSucceeded
                mode = .fixed(rpm)
                // Remember hand-entered values only once they actually applied.
                if !Self.fixedRPMPresets.contains(rpm) {
                    customFixedRPM = rpm
                    UserDefaults.standard.set(rpm, forKey: Self.customFixedRPMKey)
                }
                clearTemperatureCurveState()
                if resetsAutomaticRestore {
                    scheduleAutomaticRestore()
                }
                messageText = LocalizedControlText { fanBarFormat("固定目标：%d RPM", "Fixed target: %d RPM", rpm) }
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
                clearModeActionFeedback()
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: true) }
            } catch {
                manualControlFailure = CompatibilityControlFailure(error: error)
                manualControlEvidence = .requestFailed
                let failure = LocalizedControlText {
                    fanBarFormat("控制失败：%@", "Control failed: %@", error.localizedDescription)
                }
                messageText = failure
                failSwitch(
                    error: error,
                    message: failure,
                    title: LocalizedControlText {
                        fanBarText("风扇没有响应，固定转速未生效", "The fans didn't respond; the fixed speed didn't apply")
                    },
                    retry: .fixed(rpm)
                )
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: false) }
            }
            isBusy = false
        }
    }

    /// Activates a cooling preset by running its temperature curve (menu entry).
    func setCoolingPreset(_ preset: CoolingPresetID) {
        controlNotice = nil
        selectCoolingCurvePreset(preset, enableControl: true, resetsAutomaticRestore: true)
    }

    func setAutomatic() {
        controlNotice = nil
        restoreAutomatic(trigger: .user)
    }

    // MARK: Notices and recovery

    func dismissControlNotice() {
        if case .handBackSoon = controlNotice {
            removeDeliveredHandBackNotification(HandBackNotification.soonIdentifier)
        }
        controlNotice = nil
    }

    /// Turns a handed-back mode on again for `duration`, as "Turn on again" and "Try again" do.
    func turnOnAgain(_ resumable: ResumableMode, for duration: AutomaticRestoreDuration) {
        guard mode == .automatic else { return }
        removeDeliveredHandBackNotification(HandBackNotification.endedIdentifier)
        automaticRestoreDuration = duration
        switch resumable {
        case .preset(let preset): setCoolingPreset(preset)
        case .fixed(let rpm):
            controlNotice = nil
            setFixedRPM(rpm)
        }
    }

    /// Runs the failure banner's button.
    func performRecovery(_ recovery: ModeActionFeedback.Recovery) {
        switch recovery {
        case .retry(.preset(let preset)): setCoolingPreset(preset)
        case .retry(.fixed(let rpm)): setFixedRPM(rpm)
        case .retry(.restore): setAutomatic()
        case .openHelperSettings: openHelperSettings()
        case .enableHelper: enableHelper()
        case .chooseTemperatureSource:
            // The source picker lives with the curve in Settings.
            clearModeActionFeedback()
            SettingsWindowPresenter.shared.show(controller: self)
        }
    }

    #if DEBUG
    /// Puts the panel into states that otherwise need real fans or a running timer.
    func setControlStateForTesting(
        notice: ControlNotice?,
        feedback: ModeActionFeedback? = nil,
        unsupported: Bool = false
    ) {
        controlNotice = notice
        modeActionFeedback = feedback
        manualControlUnsupported = unsupported
    }
    #endif

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        // Whatever the panel now shows needs no banner of its own.
        if visible { removeDeliveredHandBackNotification(HandBackNotification.soonIdentifier) }
    }

    func setHandBackRemindersEnabled(_ enabled: Bool) {
        handBackRemindersEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: HandBackNotification.remindersEnabledKey)
        if enabled { requestHandBackNotificationPermissionIfNeeded(force: true) }
    }

    /// Asked when a timed manual mode starts, while the user is looking at
    /// FanBar, rather than in the middle of whatever they do next.
    private func requestHandBackNotificationPermissionIfNeeded(force: Bool = false) {
        guard handBackRemindersEnabled, let notificationCenter,
              force || !requestedHandBackNotificationPermission else { return }
        requestedHandBackNotificationPermission = true
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a hand-back notice as a notification, only while the panel is closed.
    private func postHandBackNotification(_ notice: ControlNotice, identifier: String) {
        guard !isPanelVisible, handBackRemindersEnabled, let notificationCenter else { return }
        let sessionDuration: AutomaticRestoreDuration
        switch notice {
        case .handBackSoon(_, let duration, _), .handedBack(_, _, let duration, _):
            sessionDuration = duration
        }
        notificationCenter.setNotificationCategories(HandBackNotification.categories(sessionDuration: sessionDuration))
        let request = UNNotificationRequest(
            identifier: identifier,
            content: ControlNoticeText.notificationContent(for: notice, controller: self),
            trigger: nil
        )
        notificationCenter.add(request) { error in
            if let error {
                NSLog("FanBar hand-back notification failed: %@", error.localizedDescription)
            }
        }
    }

    private func removeDeliveredHandBackNotification(_ identifier: String) {
        notificationCenter?.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter?.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func handleNotificationResponse(action: String, request: String) {
        guard request.hasPrefix(HandBackNotification.threadIdentifier) else { return }
        switch action {
        case HandBackNotification.keepSameAction:
            guard mode != .automatic else { return }
            setAutomaticRestoreDuration(automaticRestoreDuration)
        case HandBackNotification.keepOnAction:
            guard mode != .automatic else { return }
            setAutomaticRestoreDuration(.never)
        case HandBackNotification.turnOnAgainAction:
            guard case .handedBack(let resumable, _, let duration, _) = controlNotice else { return }
            turnOnAgain(resumable, for: duration)
        default:
            // A click on the notification itself opens the panel, where the notice waits.
            showPanel?()
        }
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
    func curveProfile(for preset: CoolingPresetID) -> FanCurveProfile {
        if preset == curveCoolingPreset {
            return curveProfile
        }
        return storedCurveProfile(for: preset)
    }

    private func storedCurveProfile(for preset: CoolingPresetID) -> FanCurveProfile {
        switch preset {
        case .builtIn(let builtIn):
            return (curvePresetSlots[builtIn] ?? builtIn.factoryCurve).sanitized()
        case .custom(let id):
            return customPresets.first { $0.id == id }?.curve
                ?? FanCoolingPreset.balanced.factoryCurve.sanitized()
        }
    }

    /// Writes a curve into its slot without touching the active selection.
    private func storeCurveProfile(_ profile: FanCurveProfile, for preset: CoolingPresetID) {
        switch preset {
        case .builtIn(let builtIn):
            curvePresetSlots[builtIn] = profile
        case .custom(let id):
            guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
            customPresets[index].curve = profile
            CustomCoolingPresetStore.save(customPresets)
        }
    }

    /// Replaces one stored preset without unexpectedly switching the editor.
    /// This is used by Undo when the user has moved to another preset meanwhile.
    func setCurveProfile(_ profile: FanCurveProfile, for preset: CoolingPresetID) {
        guard presetExists(preset) else { return }
        let sanitized = profile.sanitized()
        storeCurveProfile(sanitized, for: preset)
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
        for preset: CoolingPresetID,
        registeringUndoWith undoManager: UndoManager?,
        actionName: String
    ) {
        guard presetExists(preset) else { return }
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
        _ preset: CoolingPresetID,
        enableControl: Bool = false,
        resetsAutomaticRestore: Bool = false
    ) {
        guard presetExists(preset) else { return }
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
        preset: CoolingPresetID,
        profile: FanCurveProfile,
        succeeded: Bool
    ) {
        guard succeeded, preset != curveCoolingPreset, presetExists(preset) else { return }
        storeCurveProfile(curveProfile.sanitized(), for: curveCoolingPreset)
        let sanitized = profile.sanitized()
        curveCoolingPreset = preset
        curveProfile = sanitized
        storeCurveProfile(sanitized, for: preset)
        FanCurvePreferences.save(slots: curvePresetSlots, selection: preset)
    }

    /// Restores the factory curve for the active panel preset only. Custom
    /// presets have no factory curve, so this does nothing for them.
    func resetActiveCurvePresetToFactory(
        undoManager: UndoManager? = nil,
        actionName: String = ""
    ) {
        guard let builtIn = curveCoolingPreset.builtInPreset else { return }
        replaceCurveProfile(
            curveProfile.resettingCurveToFactory(for: builtIn),
            for: curveCoolingPreset,
            registeringUndoWith: undoManager,
            actionName: actionName
        )
    }

    // MARK: - Preset catalog

    /// Built-ins first, then custom presets in creation order.
    var allPresets: [CoolingPresetSummary] {
        FanCoolingPreset.allCases.map {
            CoolingPresetSummary(id: .builtIn($0), title: $0.title, systemImage: $0.systemImage)
        } + customPresets.map {
            CoolingPresetSummary(id: .custom($0.id), title: $0.name, systemImage: $0.symbol.systemImage)
        }
    }

    func presetSummary(for preset: CoolingPresetID) -> CoolingPresetSummary {
        allPresets.first { $0.id == preset } ?? CoolingPresetSummary(
            id: .fallback,
            title: FanCoolingPreset.balanced.title,
            systemImage: FanCoolingPreset.balanced.systemImage
        )
    }

    func presetTitle(for preset: CoolingPresetID) -> String {
        presetSummary(for: preset).title
    }

    var canAddCustomPreset: Bool {
        customPresets.count < CustomPresetRules.maximumCount
    }

    private func presetExists(_ preset: CoolingPresetID) -> Bool {
        switch preset {
        case .builtIn: true
        case .custom(let id): customPresets.contains { $0.id == id }
        }
    }

    /// Names every other preset shows, for duplicate checks.
    func takenPresetNames(excluding preset: CoolingPresetID? = nil) -> [String] {
        allPresets.filter { $0.id != preset }.map(\.title)
    }

    func presetNameProblem(_ name: String, excluding preset: CoolingPresetID? = nil) -> CustomPresetRules.NameProblem? {
        CustomPresetRules.problem(with: name, takenNames: takenPresetNames(excluding: preset))
    }

    /// Creates a custom preset from another preset's curve and selects it for
    /// editing. Selecting never starts control on its own (same as a tile
    /// click), unless curve control is already running.
    @discardableResult
    func createCustomPreset(
        name: String,
        symbol: CustomPresetSymbol,
        copying source: CoolingPresetID
    ) -> CoolingPresetID? {
        guard canAddCustomPreset, presetNameProblem(name) == nil else { return nil }
        let preset = CustomCoolingPreset(
            name: CustomPresetRules.normalized(name),
            symbol: symbol,
            curve: curveProfile(for: source)
        )
        customPresets.append(preset)
        CustomCoolingPresetStore.save(customPresets)
        let id = CoolingPresetID.custom(preset.id)
        selectCoolingCurvePreset(id)
        return id
    }

    /// "Duplicate" / "Duplicate as Custom Preset": no dialog, a free copy name.
    @discardableResult
    func duplicatePreset(_ source: CoolingPresetID) -> CoolingPresetID? {
        guard presetExists(source) else { return nil }
        let summary = presetSummary(for: source)
        let symbol: CustomPresetSymbol
        if case .custom(let id) = source, let custom = customPresets.first(where: { $0.id == id }) {
            symbol = custom.symbol
        } else {
            symbol = .defaultSymbol
        }
        return createCustomPreset(
            name: CustomPresetRules.copyName(of: summary.title, takenNames: takenPresetNames()),
            symbol: symbol,
            copying: source
        )
    }

    /// Returns the problem when the name is rejected; the old name is kept.
    @discardableResult
    func renameCustomPreset(_ preset: CoolingPresetID, to name: String) -> CustomPresetRules.NameProblem? {
        guard case .custom(let id) = preset,
              let index = customPresets.firstIndex(where: { $0.id == id }) else { return nil }
        if let problem = presetNameProblem(name, excluding: preset) { return problem }
        customPresets[index].name = CustomPresetRules.normalized(name)
        CustomCoolingPresetStore.save(customPresets)
        if preset == curveCoolingPreset, mode == .temperatureCurve { updateCurveMessage() }
        return nil
    }

    func setCustomPresetSymbol(_ preset: CoolingPresetID, symbol: CustomPresetSymbol) {
        guard case .custom(let id) = preset,
              let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].symbol = symbol
        CustomCoolingPresetStore.save(customPresets)
    }

    /// Deletes a custom preset. While it is running, control moves to Balanced
    /// and stays on curve control so the fans do not jump; while it is only
    /// selected, the preset before it is selected instead.
    func deleteCustomPreset(_ preset: CoolingPresetID) {
        guard case .custom(let id) = preset,
              let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        CoolingPresetPreferences.removing(preset)
        if preset == curveCoolingPreset {
            let replacement: CoolingPresetID
            if mode == .temperatureCurve {
                replacement = .fallback
            } else {
                let ids = allPresets.map(\.id)
                let position = ids.firstIndex(of: preset) ?? 0
                replacement = ids[max(position - 1, 0)]
            }
            curveCoolingPreset = replacement
            curveProfile = storedCurveProfile(for: replacement)
        }
        customPresets.remove(at: index)
        CustomCoolingPresetStore.save(customPresets)
        FanCurvePreferences.save(slots: curvePresetSlots, selection: curveCoolingPreset)
        if mode == .temperatureCurve {
            updateCurveMessage()
            scheduleCurveHardwareApply()
        }
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

    /// Inserts a control point after `id` and returns the new point's id.
    @discardableResult
    func insertCurvePoint(after id: UUID) -> UUID? {
        guard let next = curveProfile.insertingPoint(after: id) else { return nil }
        let existing = Set(curveProfile.points.map(\.id))
        setCurveProfile(next)
        return next.points.first { !existing.contains($0.id) }?.id
    }

    func removeCurvePoint(id: UUID) {
        var next = curveProfile
        guard next.points.count > FanCurveProfile.minimumPointCount else { return }
        next.points.removeAll { $0.id == id }
        setCurveProfile(next)
    }

    func setHighTemperatureThreshold(_ celsius: Double) {
        let threshold = ThermalAlertSettings.clampedThreshold(celsius)
        guard threshold != highTemperatureThresholdCelsius else { return }
        highTemperatureThresholdCelsius = threshold
        UserDefaults.standard.set(threshold, forKey: ThermalAlertSettings.thresholdKey)
        // Keep the monitor's episode state: the slider calls this for every
        // degree while dragging, and resetting would re-alert at each step.
        // Re-checking drops sensors now below the threshold and alerts once
        // for sensors that newly exceed it.
        thermalAlertMonitor.thresholdCelsius = threshold
        if let latest = latestThermalReading() {
            evaluateThermalAlerts(using: latest)
        }
    }

    /// Choosing a system sound plays it, as the system Sound settings do.
    func setHighTemperatureAlertSound(_ sound: ThermalAlertSound) {
        highTemperatureAlertSound = sound
        if let storedValue = sound.storedValue {
            UserDefaults.standard.set(storedValue, forKey: ThermalAlertSettings.soundKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ThermalAlertSettings.soundKey)
        }
        previewHighTemperatureAlertSound()
    }

    func previewHighTemperatureAlertSound() {
        if let name = highTemperatureAlertSound.systemSoundName {
            ThermalAlertSoundPlayer.play(name)
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
        guard let notificationCenter else {
            isRequestingHighTemperatureNotificationPermission = false
            highTemperatureNotificationsEnabled = false
            return
        }
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self, requestID == self.highTemperatureNotificationRequestID else { return }
                self.isRequestingHighTemperatureNotificationPermission = false

                guard granted else {
                    self.highTemperatureNotificationsEnabled = false
                    UserDefaults.standard.set(
                        false,
                        forKey: ThermalAlertSettings.notificationsEnabledKey
                    )
                    self.messageText = LocalizedControlText {
                        fanBarText(
                            "未获得通知权限，请在系统设置中允许 FanBar 发送通知",
                            "Notification permission was not granted. Allow FanBar notifications in System Settings."
                        )
                    }
                    return
                }

                self.highTemperatureNotificationsEnabled = true
                self.thermalAlertMonitor.reset()
                // The first alert after switching on should be heard.
                self.thermalAlertSoundGate.reset()
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
        preset: CoolingPresetID,
        profile: FanCurveProfile,
        resetsAutomaticRestore: Bool = true
    ) {
        guard helperState == .enabled, !isBusy else {
            rejectSwitchBeforeRequest()
            return
        }
        guard let reading = latestThermalReading(),
              let temperature = controlTemperature(from: reading, profile: profile) else {
            failMissingTemperature(for: preset, profile: profile)
            return
        }

        // Initial activation intentionally skips hysteresis and rate limiting.
        let fraction = profile.fraction(at: temperature)
        isBusy = true
        if resetsAutomaticRestore { switchFeedback = .began }
        let progress = LocalizedControlText { [weak self = self] in
            guard let self else { return "" }
            return fanBarFormat("正在切换到%@温控…", "Switching to %@ curve…", self.presetTitle(for: preset))
        }
        messageText = progress
        beginModeAction(progress)
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.setCoolingFraction(fraction)
                curveControlFailure = nil
                curveControlEvidence = .requestSucceeded
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
                curveControlFailure = CompatibilityControlFailure(error: error)
                curveControlEvidence = .requestFailed
                clearTemperatureCurveState()
                failCurveActivation(error: error, preset: preset)
                if resetsAutomaticRestore { switchFeedback = .ended(successfully: false) }
            }
            isBusy = false
        }
    }

    private func updateTemperatureCurve(using reading: ThermalReading, force: Bool = false) {
        guard mode == .temperatureCurve,
              !isBusy,
              curveUpdateTask == nil,
              Date() >= curveRetryNotBefore else { return }
        if curveConsecutiveFailures > 0 {
            // The first write after a backoff must land even when the target
            // matches the last successful value: the SMC may never have seen
            // it, and deadband skipping would leave the stale state in place.
            curveOutputFraction = nil
        }
        guard let temperature = controlTemperature(from: reading) else {
            curveMissingTemperatureSamples += 1
            // Idle GPUs briefly drop out of the sensor list; only give up
            // after ~30 s with no usable chip temperature at all.
            if curveMissingTemperatureSamples >= 15 {
                messageText = LocalizedControlText {
                    fanBarText("温度传感器不可用，正在恢复系统控制…", "Temperature sensor unavailable; restoring system control…")
                }
                restoreAutomatic(trigger: .missingTemperature(curveProfile.sensor))
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
                self.curveConsecutiveFailures = 0
                self.curveRetryNotBefore = .distantPast
                self.updateCurveMessage()
            } catch {
                // A transient failure (sleep, helper restart) is not compatibility evidence.
                guard self.mode == .temperatureCurve else { return }
                self.curveConsecutiveFailures += 1
                self.curveRetryNotBefore = Date().addingTimeInterval(
                    Self.curveFailureBackoff(after: self.curveConsecutiveFailures)
                )
                self.messageText = LocalizedControlText {
                    // A wedge that survives an App restart leaves the SMC
                    // rejecting every fan write; only a reboot resets it (#114).
                    if self.curveConsecutiveFailures >= 5 {
                        fanBarText(
                            "风扇写入持续失败，SMC 可能已锁定；重启电脑可恢复。",
                            "Fan writes keep failing; the SMC may be locked until reboot."
                        )
                    } else {
                        fanBarFormat("智能温控更新失败：%@", "Smart cooling update failed: %@", error.localizedDescription)
                    }
                }
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
        (profile ?? curveProfile).sensor.temperature(in: reading)
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
            highTemperatureThresholdCelsius
        )
        let sound = highTemperatureAlertSound
        if sound != .silent, thermalAlertSoundGate.allowsSound(at: Date()) {
            content.sound = sound.deliver(playing: ThermalAlertSoundPlayer.play)
        }

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
        messageText = LocalizedControlText { [weak self = self] in
            guard let self else { return "" }
            return fanBarFormat(
                "%@：%.0f°C · %.0f%%",
                "%@: %.0f°C · %.0f%%",
                self.presetTitle(for: curveCoolingPreset),
                temperature,
                fraction * 100
            )
        }
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
        curveConsecutiveFailures = 0
        curveRetryNotBefore = .distantPast
    }

    /// Wait before the next curve write after `consecutiveFailures` straight
    /// failures, in seconds: 0, 2, 5, 10, 20, 40, then 60 s. A dead SMC
    /// channel used to produce a doomed write every couple of seconds.
    static func curveFailureBackoff(after consecutiveFailures: Int) -> TimeInterval {
        let steps: [TimeInterval] = [0, 2, 5, 10, 20, 40, 60]
        return steps[min(max(consecutiveFailures, 1) - 1, steps.count - 1)]
    }

    /// Changes the default from Settings and applies it to any in-progress
    /// manual session.
    func setDefaultAutomaticRestoreDuration(_ duration: AutomaticRestoreDuration) {
        defaultAutomaticRestoreDuration = duration
        UserDefaults.standard.set(duration.rawValue, forKey: automaticRestorePreferenceKey)
        // "Never" must mean never, including the session already running.
        setAutomaticRestoreDuration(duration)
    }

    /// Adjusts only the current manual session from the panel.
    func setAutomaticRestoreDuration(_ duration: AutomaticRestoreDuration) {
        automaticRestoreDuration = duration
        if mode != .automatic {
            scheduleAutomaticRestore()
        }
    }

    /// Why control is returning to macOS; only the user's own choice goes unannounced.
    enum RestoreTrigger: Equatable {
        case user
        case timer
        case missingTemperature(FanCurveSensor)

        var handBackReason: HandBackReason? {
            switch self {
            case .user: nil
            case .timer: .timer
            case .missingTemperature(let sensor): .missingTemperature(sensor)
            }
        }
    }

    /// The manual mode running now, in a form "Turn on again" can repeat.
    private var currentResumableMode: ResumableMode? {
        switch mode {
        case .automatic: nil
        case .temperatureCurve: .preset(curveCoolingPreset)
        case .fixed(let rpm): .fixed(rpm)
        }
    }

    // Restoring is one transaction: announce, request, then report the outcome.
    // swiftlint:disable:next function_body_length
    private func restoreAutomatic(trigger: RestoreTrigger) {
        let triggeredByTimer = trigger == .timer
        guard !isBusy else {
            if triggeredByTimer {
                scheduleAutomaticRestoreRetry(after: 1)
            }
            return
        }
        // Captured before the session is cleared, so the notice can offer the same mode back.
        let resumable = currentResumableMode
        let sessionDuration = automaticRestoreDuration
        guard helperState == .enabled else {
            mode = .automatic
            clearTemperatureCurveState()
            clearAutomaticRestore()
            messageText = LocalizedControlText { [state = helperState] in state.title }
            announceHandBack(of: resumable, trigger: trigger, duration: sessionDuration)
            return
        }
        isBusy = true
        switchFeedback = .began
        let progress = LocalizedControlText { fanBarText("正在恢复系统控制…", "Restoring system control…") }
        messageText = progress
        beginModeAction(progress)
        Task {
            do {
                await finishPendingCurveUpdate()
                try await helperClient.restoreAutomatic()
                mode = .automatic
                clearTemperatureCurveState()
                clearAutomaticRestore()
                messageText = LocalizedControlText {
                    triggeredByTimer
                        ? fanBarText("定时结束，已恢复 macOS 自动控制", "Timer ended; macOS automatic control restored")
                        : fanBarText("已恢复 macOS 自动控制", "macOS automatic control restored")
                }
                if let readings = try? await helperClient.fans() {
                    fans = readings
                }
                compatibilityControlNeedsRestore = false
                if compatibilityControlMessage != nil {
                    compatibilityControlText = LocalizedControlText { fanBarText("已恢复 macOS 自动控制", "macOS automatic control restored") }
                }
                clearModeActionFeedback()
                announceHandBack(of: resumable, trigger: trigger, duration: sessionDuration)
                switchFeedback = .ended(successfully: true)
            } catch {
                let failure = LocalizedControlText {
                    fanBarFormat("恢复失败：%@", "Restore failed: %@", error.localizedDescription)
                }
                messageText = failure
                if compatibilityControlMessage != nil { compatibilityControlText = failure }
                let isConnection = helperSettingsActionNeeded(for: error)
                modeActionFeedback = ModeActionFeedback(
                    kind: .failure,
                    localizedMessage: failure,
                    title: isConnection
                        ? Self.unreachableServiceTitle
                        : LocalizedControlText { fanBarText("没能交回 macOS", "Couldn't hand back to macOS") },
                    safety: safetyLine(),
                    isRisk: true,
                    recovery: isConnection ? .openHelperSettings : .retry(.restore),
                    detail: error.localizedDescription
                )
                switchFeedback = .ended(successfully: false)
                if triggeredByTimer {
                    scheduleAutomaticRestoreRetry(after: 5)
                }
            }
            isBusy = false
        }
    }

    /// Records a hand-back the user did not ask for, and tells them about it:
    /// in the panel when it is open, otherwise as a notification.
    private func announceHandBack(
        of resumable: ResumableMode?,
        trigger: RestoreTrigger,
        duration: AutomaticRestoreDuration
    ) {
        removeDeliveredHandBackNotification(HandBackNotification.soonIdentifier)
        guard let resumable, let reason = trigger.handBackReason else {
            controlNotice = nil
            return
        }
        let notice = ControlNotice.handedBack(mode: resumable, reason: reason, duration: duration, at: Date())
        controlNotice = notice
        postHandBackNotification(notice, identifier: HandBackNotification.endedIdentifier)
    }

    private func scheduleAutomaticRestore(interval overrideInterval: TimeInterval? = nil) {
        automaticRestoreTask?.cancel()
        cancelHandBackWarning()
        automaticRestoreRemainingAtSleep = nil
        guard mode != .automatic, automaticRestoreDuration != .never else {
            automaticRestoreDeadline = nil
            automaticRestoreTask = nil
            return
        }

        requestHandBackNotificationPermissionIfNeeded()
        let interval = overrideInterval
            ?? automaticRestoreTestInterval
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
        if let warningDelay = HandBackWarning.delay(untilDeadline: interval) {
            automaticRestoreWarningTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(warningDelay * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.warnBeforeHandBack(deadline: deadline)
            }
        }
    }

    /// The last minute: offer to extend before the fans go back to macOS.
    private func warnBeforeHandBack(deadline: Date) {
        guard mode != .automatic, automaticRestoreDeadline == deadline,
              let resumable = currentResumableMode else { return }
        let notice = ControlNotice.handBackSoon(mode: resumable, duration: automaticRestoreDuration, deadline: deadline)
        controlNotice = notice
        postHandBackNotification(notice, identifier: HandBackNotification.soonIdentifier)
    }

    /// Ends a pending warning: the session was extended, changed or is over.
    private func cancelHandBackWarning() {
        automaticRestoreWarningTask?.cancel()
        automaticRestoreWarningTask = nil
        if case .handBackSoon = controlNotice { controlNotice = nil }
        removeDeliveredHandBackNotification(HandBackNotification.soonIdentifier)
    }

    private func restoreAutomaticAfterTimer() {
        guard mode != .automatic else {
            clearAutomaticRestore()
            return
        }
        restoreAutomatic(trigger: .timer)
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
        cancelHandBackWarning()
        automaticRestoreRemainingAtSleep = nil
        automaticRestoreTask = nil
        automaticRestoreDeadline = nil
        // Back in Automatic: the next manual session starts from the default.
        automaticRestoreDuration = defaultAutomaticRestoreDuration
    }

    static let unreachableServiceTitle = LocalizedControlText {
        fanBarText("连不上控制服务", "Can't reach the control service")
    }

    /// The failure banner's second line: who is driving the fans after the request failed.
    private func safetyLine() -> LocalizedControlText {
        switch mode {
        case .automatic:
            return LocalizedControlText { fanBarText("风扇仍由 macOS 控制", "macOS is still controlling the fans") }
        case .fixed(let rpm):
            return LocalizedControlText {
                fanBarFormat("风扇仍保持 %@ RPM", "Fans are still held at %@ RPM", FanBarNumberFormatter.grouped(rpm))
            }
        case .temperatureCurve:
            let preset = curveCoolingPreset
            return LocalizedControlText { [weak self = self] in
                guard let self else { return "" }
                return fanBarFormat("风扇仍按%@运行", "Fans still follow %@", self.presetTitle(for: preset))
            }
        }
    }

    /// The helper refused to start a preset's curve.
    private func failCurveActivation(error: Error, preset: CoolingPresetID) {
        let failure = LocalizedControlText { [weak self = self] in
            guard let self else { return "" }
            return fanBarFormat(
                "%@温控开启失败：%@",
                "Unable to enable %@ curve: %@",
                self.presetTitle(for: preset),
                error.localizedDescription
            )
        }
        messageText = failure
        failSwitch(
            error: error,
            message: failure,
            title: LocalizedControlText { [weak self = self] in
                guard let self else { return "" }
                return fanBarFormat(
                    "风扇没有响应，%@未开启",
                    "The fans didn't respond; %@ didn't start",
                    self.presetTitle(for: preset)
                )
            },
            retry: .preset(preset)
        )
    }

    /// A curve that cannot start because its temperature source reads nothing.
    private func failMissingTemperature(for preset: CoolingPresetID, profile: FanCurveProfile) {
        let failure = LocalizedControlText {
            fanBarFormat("未读取到可用于%@温控的温度来源", "No temperature is available for %@ curve control", profile.sensor.title)
        }
        messageText = failure
        let sensor = profile.sensor
        modeActionFeedback = ModeActionFeedback(
            kind: .failure,
            localizedMessage: failure,
            title: LocalizedControlText { [weak self = self] in
                guard let self else { return "" }
                return fanBarFormat(
                    "读不到 %@ 温度，无法开启%@",
                    "Can't read the %@ temperature, so %@ can't start",
                    sensor.shortName,
                    self.presetTitle(for: preset)
                )
            },
            safety: safetyLine(),
            recovery: .chooseTemperatureSource
        )
    }

    /// A switch the controller refused before asking the helper.
    private func rejectSwitchBeforeRequest() {
        let failure = LocalizedControlText {
            fanBarText("请先启用并批准控制服务", "Enable and approve the control service first")
        }
        messageText = failure
        let title: LocalizedControlText
        let recovery: ModeActionFeedback.Recovery?
        if helperState == .enabled {
            // Only reachable while another switch is still in flight.
            title = LocalizedControlText { fanBarText("上一次切换还没完成", "The last switch hasn't finished yet") }
            recovery = nil
        } else {
            title = LocalizedControlText { fanBarText("控制服务未启用", "The control service is off") }
            switch helperState {
            case .notRegistered: recovery = .enableHelper
            case .requiresApproval: recovery = .openHelperSettings
            case .enabled, .unavailable: recovery = nil
            }
        }
        modeActionFeedback = ModeActionFeedback(
            kind: .failure,
            localizedMessage: failure,
            title: title,
            safety: safetyLine(),
            recovery: recovery
        )
    }

    /// Reports a helper request that failed, or marks the Mac as unable to
    /// take manual control at all when that is what the helper said.
    private func failSwitch(
        error: Error,
        message: LocalizedControlText,
        title: LocalizedControlText,
        retry: ModeActionFeedback.RetryTarget
    ) {
        if (error as? HelperClientError)?.indicatesMissingFanModeKey == true {
            // A permanent hardware limit, not a failed attempt: the panel
            // disables the mode strip and explains instead of failing each time.
            manualControlUnsupported = true
            clearModeActionFeedback()
            return
        }
        // A failed start from Automatic leaves no session whose duration to keep.
        if mode == .automatic { automaticRestoreDuration = defaultAutomaticRestoreDuration }
        let isConnection = helperSettingsActionNeeded(for: error)
        modeActionFeedback = ModeActionFeedback(
            kind: .failure,
            localizedMessage: message,
            title: isConnection ? Self.unreachableServiceTitle : title,
            safety: safetyLine(),
            recovery: isConnection ? .openHelperSettings : .retry(retry),
            detail: error.localizedDescription
        )
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

    private func beginModeAction(_ message: LocalizedControlText) {
        modeActionFeedback = ModeActionFeedback(kind: .inProgress, localizedMessage: message)
    }

    private func failModeAction(_ message: LocalizedControlText, offersHelperSettings: Bool = false) {
        modeActionFeedback = ModeActionFeedback(kind: .failure, localizedMessage: message, offersHelperSettings: offersHelperSettings)
    }

    func clearModeActionFeedback() {
        modeActionFeedback = nil
    }

    func quit() {
        // Our exit closes the XPC connection and the helper restores automatic
        // control itself, so a slow unlock reply must not hold Quit open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApplication.shared.terminate(nil)
        }
        Task {
            await finishPendingCurveUpdate()
            if helperState == .enabled {
                try? await helperClient.restoreAutomatic()
            }
            NSApplication.shared.terminate(nil)
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
                    self.messageText = LocalizedControlText {
                        fanBarText("请在系统设置中批准新版控制服务", "Approve the updated control service in System Settings")
                    }
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
                self.messageText = LocalizedControlText {
                    fanBarText("控制服务更新失败，请重新打开 FanBar", "Control service update failed; reopen FanBar")
                }
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

    /// Shared by `publishWidgetSnapshot` and `publishUnavailableWidgetSnapshot`
    /// so the fan-mode -> widget-mode mapping only lives in one place.
    private func widgetSnapshotMode(for mode: Mode) -> FanBarWidgetSnapshot.Mode {
        switch mode {
        case .automatic:
            return .automatic
        case .temperatureCurve:
            return .temperatureCurve
        case .fixed:
            return .fixed
        }
    }

    private func publishWidgetSnapshot(thermal: ThermalReading) {
        let snapshot = FanBarWidgetSnapshot(
            updatedAt: thermal.sampledAt,
            fans: fans.map {
                FanBarWidgetSnapshot.Fan(
                    index: $0.index,
                    currentRPM: $0.currentRPM,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM,
                    isManual: $0.isManual
                )
            },
            cpuCelsius: thermal.cpuDisplayCelsius,
            mode: widgetSnapshotMode(for: mode),
            isAvailable: true,
            language: FanBarLanguage.current
        )
        publishWidgetSnapshotIfNeeded(snapshot)
    }

    private func publishUnavailableWidgetSnapshot() {
        let snapshot = FanBarWidgetSnapshot(
            fans: fans.map {
                FanBarWidgetSnapshot.Fan(
                    index: $0.index,
                    currentRPM: $0.currentRPM,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM,
                    isManual: $0.isManual
                )
            },
            cpuCelsius: temperatureHistory.last?.cpuDisplayCelsius,
            mode: widgetSnapshotMode(for: mode),
            isAvailable: false,
            language: FanBarLanguage.current
        )
        publishWidgetSnapshotIfNeeded(snapshot)
    }

    /// The snapshot file must be current at the instant WidgetKit reloads the
    /// timeline, so the write is deliberately NOT tied to the reload cadence:
    /// gating both on the same multi-minute window made the widget render data
    /// that was already one full window old, which reads as "the RPM is stuck".
    /// The write is a ~300-byte atomic file write, so a short floor is enough
    /// to keep the 2s refresh timer from rewriting on every tick; only
    /// `reloadTimelines` stays throttled, because it draws on a WidgetKit
    /// budget. Availability transitions bypass the floor entirely.
    private static let widgetSnapshotMinimumWriteInterval: TimeInterval = 5
    /// While FanBar is running, ask WidgetKit to render a fresh snapshot at a
    /// useful telemetry cadence. WidgetKit may still coalesce requests, but a
    /// one-minute floor avoids the previous five-minute lag without sending a
    /// reload for every two-second sensor sample.
    private static let widgetTimelineMinimumReloadInterval: TimeInterval = 60

    private func publishWidgetSnapshotIfNeeded(_ snapshot: FanBarWidgetSnapshot) {
        if case .disabled = widgetSnapshotDestination { return }

        let previous = lastPublishedWidgetSnapshot
        let isAvailabilityTransition = previous?.isAvailable != snapshot.isAvailable
        let contentUnchanged = previous.map { isWidgetSnapshotContentEqual($0, snapshot) } ?? false

        guard isAvailabilityTransition || !contentUnchanged else { return }

        if !isAvailabilityTransition,
            let lastPublish = lastWidgetSnapshotPublishDate,
            Date().timeIntervalSince(lastPublish) < Self.widgetSnapshotMinimumWriteInterval {
            return
        }

        do {
            switch widgetSnapshotDestination {
            case .sharedContainer:
                try snapshot.save()
            case .directory(let containerDirectory):
                try snapshot.save(containerDirectory: containerDirectory)
            case .disabled:
                return
            }
        } catch {
            NSLog("FanBar widget snapshot save failed: %@", String(describing: error))
            return
        }
        lastPublishedWidgetSnapshot = snapshot
        lastWidgetSnapshotPublishDate = Date()
        if case .sharedContainer = widgetSnapshotDestination {
            let shouldReloadImmediately = previous == nil
                || isAvailabilityTransition
                || previous?.mode != snapshot.mode
                || previous?.language != snapshot.language
            requestWidgetTimelineReloadIfNeeded(force: shouldReloadImmediately)
        }
    }

    /// Compares snapshot content while ignoring `updatedAt`, which changes on
    /// every refresh tick and would otherwise defeat the write floor above.
    /// The CPU temperature is compared at the whole-degree precision the
    /// widget actually renders, so sensor noise below that does not count as
    /// a change worth writing.
    private func isWidgetSnapshotContentEqual(
        _ lhs: FanBarWidgetSnapshot,
        _ rhs: FanBarWidgetSnapshot
    ) -> Bool {
        lhs.fans == rhs.fans
            && lhs.cpuCelsius?.rounded() == rhs.cpuCelsius?.rounded()
            && lhs.mode == rhs.mode
            && lhs.isAvailable == rhs.isAvailable
            && lhs.language == rhs.language
    }

    private func requestWidgetTimelineReloadIfNeeded(force: Bool = false) {
#if canImport(WidgetKit)
        let now = Date()
        guard force
            || lastWidgetTimelineReloadDate == nil
            || now.timeIntervalSince(lastWidgetTimelineReloadDate!)
                >= Self.widgetTimelineMinimumReloadInterval else {
            return
        }
        lastWidgetTimelineReloadDate = now
        WidgetCenter.shared.reloadTimelines(ofKind: FanBarWidgetSnapshot.kind)
#endif
    }

    private func appendTemperature(_ reading: ThermalReading) {
        guard reading.cpuCelsius != nil
            || reading.gpuCelsius != nil
            || reading.ssdCelsius != nil
            || reading.batteryCelsius != nil else { return }
        temperatureHistory.append(reading)
        let earliestSampleDate = reading.sampledAt.addingTimeInterval(-TemperatureChartTimeAxis.retainedDuration)
        temperatureHistory.removeAll { $0.sampledAt < earliestSampleDate }
        if temperatureHistory.count > maximumTemperatureSamples {
            temperatureHistory.removeFirst(temperatureHistory.count - maximumTemperatureSamples)
        }
        persistTemperatureHistoryIfNeeded()
    }

    private func persistTemperatureHistoryIfNeeded(now: Date = Date()) {
        if case .disabled = widgetSnapshotDestination { return }
        if let lastSave = lastTemperatureHistorySaveDate,
           now.timeIntervalSince(lastSave) < Self.temperatureHistorySaveInterval {
            return
        }
        lastTemperatureHistorySaveDate = now
        TemperatureHistoryStore.save(temperatureHistory)
    }
}
