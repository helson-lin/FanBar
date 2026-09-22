import XCTest
@testable import FanBar

/// Covers the sampling-gap handling described in issue reports about the
/// temperature curve drawing a straight line (and blending averages) across
/// gaps left by sleep, a locked screen, or an app relaunch.
@MainActor
final class TemperatureChartSegmentTests: XCTestCase {
    private func dates(offsetsInSeconds offsets: [TimeInterval]) -> [Date] {
        let base = Date(timeIntervalSince1970: 0)
        return offsets.map { base.addingTimeInterval($0) }
    }

    func testEmptyInputProducesNoSegments() {
        XCTAssertEqual(TemperatureChart.segments(for: []), [])
    }

    func testEvenlySampledRunStaysOneSegment() {
        let samples = dates(offsetsInSeconds: [0, 2, 4, 6, 8])
        XCTAssertEqual(TemperatureChart.segments(for: samples), [0...4])
    }

    func testGapWiderThanThresholdSplitsIntoSegments() {
        // A 20 second hole (lock screen, sleep) after the third sample.
        let samples = dates(offsetsInSeconds: [0, 2, 4, 24, 26, 28])
        XCTAssertEqual(TemperatureChart.segments(for: samples), [0...2, 3...5])
    }

    func testGapExactlyAtThresholdDoesNotSplit() {
        let samples = dates(offsetsInSeconds: [0, 15])
        XCTAssertEqual(TemperatureChart.segments(for: samples), [0...1])
    }

    func testMultipleGapsProduceMultipleSegments() {
        let samples = dates(offsetsInSeconds: [0, 2, 30, 32, 60, 62])
        XCTAssertEqual(TemperatureChart.segments(for: samples), [0...1, 2...3, 4...5])
    }

    func testSingleSampleIsItsOwnSegment() {
        let samples = dates(offsetsInSeconds: [0])
        XCTAssertEqual(TemperatureChart.segments(for: samples), [0...0])
    }
}
