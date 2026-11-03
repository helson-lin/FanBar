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

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
    }

    /// Only app launch starts background checks. Rendering Settings in a test
    /// or preview must not start Sparkle against the test runner's bundle.
    func start() {
        updaterController.startUpdater()
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
    }
}
