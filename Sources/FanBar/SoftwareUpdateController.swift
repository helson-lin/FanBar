import Foundation
import Sparkle

/// Owns Sparkle for the full app lifetime and exposes only the update controls
/// used by FanBar's settings UI. Update verification remains inside Sparkle.
@MainActor
final class SoftwareUpdateController {
    static let shared = SoftwareUpdateController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
