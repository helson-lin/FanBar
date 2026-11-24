import Foundation
import XCTest
@testable import FanBar

@MainActor
final class FixedRPMPreferenceTests: XCTestCase {
    func testAcceptedPresetAndCustomTargetsReplaceTheLastSavedValue() async throws {
        let name = "FixedRPMPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertNil(FixedRPMPreference.load(from: defaults))
        defaults.set(3_100, forKey: "fanbar.customFixedRPM")
        XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_100)
        try await FixedRPMPreference.apply(2_500, to: defaults) { _ in }
        XCTAssertEqual(FixedRPMPreference.load(from: defaults), 2_500)
        try await FixedRPMPreference.apply(3_500, to: defaults) { _ in }
        XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_500)
        try await FixedRPMPreference.apply(3_200, to: defaults) { _ in }
        XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_200)
    }

    func testFailedWriteKeepsPreviouslyAcceptedTarget() async throws {
        struct WriteFailure: Error {}
        let name = "FixedRPMPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3_200, forKey: FixedRPMPreference.key)

        do {
            try await FixedRPMPreference.apply(2_500, to: defaults) { _ in throw WriteFailure() }
            XCTFail("A failed write must propagate its error")
        } catch is WriteFailure {
            XCTAssertEqual(FixedRPMPreference.load(from: defaults), 3_200)
        }
    }
}
