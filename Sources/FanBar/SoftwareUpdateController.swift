import Foundation
import Sparkle

/// Owns Sparkle for the full app lifetime and exposes only the update controls
/// used by FanBar's settings UI. Update verification remains inside Sparkle.
@MainActor
final class SoftwareUpdateController {
    static let shared = SoftwareUpdateController()

    private let updaterController: SPUStandardUpdaterController
    // Sparkle holds its delegate weakly, so the controller keeps it alive.
    // swiftlint:disable:next weak_delegate
    private let feedDelegate = UsageFeedDelegate(statistics: .shared)
    private var isStarted = false
    /// Opting in asked for a report while another check was running.
    private var wantsUsageReport = false

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
        feedDelegate.onUpdateCycleFinished = { [weak self] in
            // Only a report deferred by a busy updater retries here, once; a failed
            // check never loops. Sparkle allows the next check after this returns.
            guard self?.wantsUsageReport == true else { return }
            DispatchQueue.main.async { self?.reportUsageIfPending() }
        }
    }

    /// Only app launch starts background checks. Rendering Settings in a test
    /// or preview must not start Sparkle against the test runner's bundle.
    func start() {
        updaterController.startUpdater()
        isStarted = true
    }

    /// Sends this week's opt-in report right away instead of at the next scheduled
    /// check, up to a day later. Otherwise a new install that opts in during onboarding
    /// misses its install week: Sparkle's first check runs at launch, before the
    /// toggle. Respects the automatic-check switch: with it off, nothing is sent.
    func reportUsageIfPending() {
        guard isStarted, UsageStatistics.shared.hasPendingReport,
              updaterController.updater.automaticallyChecksForUpdates else {
            wantsUsageReport = false
            return
        }
        guard updaterController.updater.canCheckForUpdates,
              !updaterController.updater.sessionInProgress else {
            wantsUsageReport = true
            return
        }
        wantsUsageReport = false
        updaterController.updater.checkForUpdatesInBackground()
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }

    var currentVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
}

/// Thin Sparkle adapter: every decision lives in `UsageStatistics`.
@MainActor
final class UsageFeedDelegate: NSObject, SPUUpdaterDelegate {
    private let statistics: UsageStatistics
    var onUpdateCycleFinished: (() -> Void)?

    init(statistics: UsageStatistics) {
        self.statistics = statistics
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        statistics.feedParameters()
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        statistics.appcastDidLoad()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        statistics.checkDidFail()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if error != nil { statistics.checkDidFail() }
        onUpdateCycleFinished?()
    }
}
