import FanBarShared
import XCTest
@testable import FanBar

final class FanCurveEditingTests: XCTestCase {
    private func profile(_ points: [(Double, Float)]) -> FanCurveProfile {
        FanCurveProfile(
            sensor: .maxChip,
            points: points.map { FanCurvePoint(celsius: $0.0, fraction: $0.1) }
        )
    }

    // MARK: - insertingPoint(after:)

    func testInsertUsesMidpointBetweenNeighbors() throws {
        let original = profile([(40, 0.2), (60, 0.6)])
        let next = try XCTUnwrap(original.insertingPoint(after: original.points[0].id))

        XCTAssertEqual(next.points.map(\.celsius), [40, 50, 60])
        XCTAssertEqual(next.points[1].fraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(next.points[0].id, original.points[0].id)
        XCTAssertEqual(next.points[2].id, original.points[1].id)
    }

    func testInsertRefusesWhenNeighborsAreOneDegreeApart() {
        let original = profile([(40, 0.2), (41, 0.3), (80, 0.9)])
        XCTAssertNil(original.insertingPoint(after: original.points[0].id))
    }

    func testInsertAfterLastPointAddsFiveDegreesWithSameFraction() throws {
        let original = profile([(40, 0.2), (70, 0.6)])
        let next = try XCTUnwrap(original.insertingPoint(after: original.points[1].id))

        XCTAssertEqual(next.points.map(\.celsius), [40, 70, 75])
        XCTAssertEqual(next.points[2].fraction, 0.6)
    }

    func testInsertAfterLastPointIsCappedAtMaximumTemperature() throws {
        let original = profile([(40, 0.2), (98, 0.9)])
        let next = try XCTUnwrap(original.insertingPoint(after: original.points[1].id))
        XCTAssertEqual(next.points.last?.celsius, FanCurveProfile.maximumCelsius)
    }

    func testInsertAfterLastPointAtMaximumTemperatureIsRejected() {
        let original = profile([(40, 0.2), (100, 0.9)])
        XCTAssertNil(original.insertingPoint(after: original.points[1].id))
    }

    func testInsertIsRejectedWhenCurveIsFull() {
        let full = profile((0..<FanCurveProfile.maximumPointCount).map {
            (40 + Double($0) * 5, Float($0) / 10)
        })
        XCTAssertNil(full.insertingPoint(after: full.points[0].id))
    }

    func testInsertIsRejectedForUnknownPoint() {
        XCTAssertNil(profile([(40, 0.2), (60, 0.6)]).insertingPoint(after: UUID()))
    }

    // MARK: - Target RPM

    func testTargetRPMFollowsHardwareRules() {
        XCTAssertEqual(FanCoolingTarget.targetRPM(fraction: 0, minimum: 1_350, maximum: 5_000), 0)
        // A small share is lifted to the hardware minimum, not left below it.
        XCTAssertEqual(FanCoolingTarget.targetRPM(fraction: 0.1, minimum: 1_350, maximum: 5_000), 1_350)
        XCTAssertEqual(FanCoolingTarget.targetRPM(fraction: 0.5, minimum: 1_350, maximum: 5_000), 2_500)
        XCTAssertEqual(FanCoolingTarget.targetRPM(fraction: 1, minimum: 1_350, maximum: 5_000), 5_000)
    }

    func testCurveTargetRangeSpansFansWithDifferentLimits() {
        let fans = [
            FanReading(index: 0, minimumRPM: 1_350, currentRPM: 1_400, maximumRPM: 5_349, isManual: true),
            FanReading(index: 1, minimumRPM: 1_522, currentRPM: 1_500, maximumRPM: 5_777, isManual: true)
        ]

        XCTAssertEqual(FanController.curveTargetRange(fraction: 0.5, fans: fans), 2_675...2_889)
        XCTAssertEqual(FanController.curveTargetRange(fraction: 0.1, fans: fans), 1_350...1_522)
        XCTAssertEqual(FanController.curveTargetRange(fraction: 0, fans: fans), 0...0)
    }

    func testCurveTargetRangeIsNilWithoutFans() {
        XCTAssertNil(FanController.curveTargetRange(fraction: 0.5, fans: []))
    }
}
