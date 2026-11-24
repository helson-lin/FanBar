import Foundation
import XCTest
@testable import FanBar

@MainActor
final class FixedRPMPreferenceTests: XCTestCase {
    private func makeTemporaryDefaults() throws -> UserDefaults {
        let name = "FixedRPMPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeController(
        defaults: UserDefaults?,
        readings: [FanReading] = FakeFanReadingSource().readings
    ) -> FanController {
        FanController(
            fixedRPMDefaults: defaults,
            notificationCenter: nil,
            widgetSnapshotDestination: .disabled,
            makeReadingSource: { FakeFanReadingSource(readings: readings) },
            readUsage: { SystemUsage() },
            refreshInterval: nil
        )
    }

    func testAcceptedPresetAndCustomTargetsReplaceTheLastSavedValue() async throws {
        let defaults = try makeTemporaryDefaults()

        XCTAssertNil(FixedRPMPreference.load(from: defaults))
        defaults.set(0, forKey: FixedRPMPreference.key)
        XCTAssertNil(FixedRPMPreference.load(from: defaults))
        defaults.set(-100, forKey: FixedRPMPreference.key)
        XCTAssertNil(FixedRPMPreference.load(from: defaults))

        defaults.set(3_100, forKey: "fanbar.customFixedRPM")
        XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_100)

        for target in [2_500, 3_500, 4_500, 5_500, 3_200] {
            let remembered = try await FixedRPMPreference.apply(target, to: defaults) { _ in }
            XCTAssertEqual(remembered, target)
            XCTAssertEqual(FixedRPMPreference.load(from: defaults), target)
        }
    }

    func testFailedWriteKeepsPreviouslyAcceptedTarget() async throws {
        struct WriteFailure: Error {}
        let defaults = try makeTemporaryDefaults()
        defaults.set(3_200, forKey: FixedRPMPreference.key)

        do {
            try await FixedRPMPreference.apply(2_500, to: defaults) { _ in throw WriteFailure() }
            XCTFail("A failed write must propagate its error")
        } catch is WriteFailure {
            XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_200)
        }
    }

    func testNonpositiveAcceptedTargetsDoNotEraseRememberedTarget() async throws {
        let defaults = try makeTemporaryDefaults()
        defaults.set(3_200, forKey: FixedRPMPreference.key)

        for rpm in [0, -1] {
            let remembered = try await FixedRPMPreference.apply(rpm, to: defaults) { _ in }
            XCTAssertEqual(remembered, 3_200)
            XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_200)
        }
    }

    func testNilDefaultsSkipsPersistenceWithoutTouchingStandardDefaults() async throws {
        let key = FixedRPMPreference.key
        let userValue = UserDefaults.standard.object(forKey: key) as? Int
        XCTAssertNil(FixedRPMPreference.load(from: nil))

        var writtenRPM: Int?
        let remembered = try await FixedRPMPreference.apply(3_500, to: nil) { writtenRPM = $0 }
        XCTAssertEqual(writtenRPM, 3_500)
        XCTAssertNil(remembered)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Int, userValue)
    }

    func testInitialTargetUsesSavedValueClampsAndFallsBack() {
        let presets = [2_500, 3_500, 4_500]
        let range = 3_000...4_000
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: 3_200, presets: presets, in: range), 3_200)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: 2_000, presets: presets, in: range), 3_000)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: 5_000, presets: presets, in: range), 4_000)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: 0, presets: presets, in: range), 3_500)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: -100, presets: presets, in: range), 3_500)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: nil, presets: presets, in: range), 3_500)
        XCTAssertEqual(FixedRPMPreference.initialTarget(saved: nil, presets: presets, in: 3_600...4_000), 3_600)
    }

    func testInitialTargetForControllerUsesInjectedPreferencesAndSharedFanRange() throws {
        let defaults = try makeTemporaryDefaults()
        defaults.set(3_500, forKey: FixedRPMPreference.key)

        let savedPresetController = makeController(defaults: defaults)
        XCTAssertEqual(savedPresetController.customFixedRPM, 3_500)
        XCTAssertEqual(FixedRPMPreference.initialTarget(for: savedPresetController), 3_500)

        defaults.set(5_500, forKey: FixedRPMPreference.key)
        let asymmetricFans = [
            FanReading(index: 0, minimumRPM: 1_500, currentRPM: 2_000, maximumRPM: 4_000, isManual: false),
            FanReading(index: 1, minimumRPM: 2_000, currentRPM: 2_200, maximumRPM: 5_000, isManual: false),
        ]
        let clampedController = makeController(defaults: defaults, readings: asymmetricFans)
        XCTAssertEqual(clampedController.customFixedRPM, 5_500)
        XCTAssertEqual(FixedRPMPreference.initialTarget(for: clampedController), 4_000)

        let unsetDefaults = try makeTemporaryDefaults()
        let fallbackController = makeController(defaults: unsetDefaults)
        XCTAssertNil(fallbackController.customFixedRPM)
        XCTAssertEqual(FixedRPMPreference.initialTarget(for: fallbackController), 2_500)

        let noFansController = makeController(defaults: defaults, readings: [])
        XCTAssertNil(FixedRPMPreference.initialTarget(for: noFansController))

        let nonOverlappingFans = [
            FanReading(index: 0, minimumRPM: 1_000, currentRPM: 1_500, maximumRPM: 2_000, isManual: false),
            FanReading(index: 1, minimumRPM: 2_500, currentRPM: 3_000, maximumRPM: 4_000, isManual: false),
        ]
        let disjointController = makeController(defaults: defaults, readings: nonOverlappingFans)
        XCTAssertNil(FixedRPMPreference.initialTarget(for: disjointController))
    }

    func testSmokeTestPreferencesLeaveUserTargetUntouched() async throws {
        let smokeDefaults = try XCTUnwrap(FixedRPMPreference.smokeTestDefaults())
        let key = FixedRPMPreference.key
        let oldSmokeValue = smokeDefaults.object(forKey: key) as? Int
        let userValue = UserDefaults.standard.object(forKey: key) as? Int
        defer {
            if let oldSmokeValue {
                smokeDefaults.set(oldSmokeValue, forKey: key)
            } else {
                smokeDefaults.removeObject(forKey: key)
            }
        }

        let remembered = try await FixedRPMPreference.apply(3_500, to: smokeDefaults) { _ in }
        XCTAssertEqual(remembered, 3_500)
        XCTAssertEqual(smokeDefaults.integer(forKey: key), 3_500)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Int, userValue)
    }
}
