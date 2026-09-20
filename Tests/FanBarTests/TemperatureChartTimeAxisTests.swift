import XCTest
@testable import FanBar

final class TemperatureChartTimeAxisTests: XCTestCase {
    private let timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    /// Issue #15: a window ending at 17:09:52 must keep the hour, not render
    /// as `59:52  04:52  09:52`.
    func testLabelsKeepHourWhenWindowCrossesHourBoundary() {
        let end = date(hour: 17, minute: 9, second: 52)
        let start = end.addingTimeInterval(-TemperatureChartTimeAxis.historyDuration)
        let labels = TemperatureChartTimeAxis.labels(
            in: start...end,
            timeZone: timeZone
        )

        XCTAssertEqual(labels, ["16:59:52", "17:04:52", "17:09:52"])
    }

    func testTickDatesCoverTenMinuteWindow() {
        let end = date(hour: 17, minute: 9, second: 52)
        let start = end.addingTimeInterval(-TemperatureChartTimeAxis.historyDuration)
        let ticks = TemperatureChartTimeAxis.tickDates(in: start...end)

        XCTAssertEqual(ticks.count, 3)
        XCTAssertEqual(ticks[0], start)
        XCTAssertEqual(ticks[1].timeIntervalSince(start), 5 * 60, accuracy: 0.001)
        XCTAssertEqual(ticks[2], end)
    }

    func testDisplayRangeAlwaysCoversTenMinutesForShortHistory() {
        let last = date(hour: 18, minute: 4, second: 10)
        let range = TemperatureChartTimeAxis.displayRange(
            lastSample: last
        )

        XCTAssertEqual(
            range.lowerBound.timeIntervalSince(last.addingTimeInterval(-10 * 60)),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(range.upperBound, last)
        XCTAssertEqual(
            TemperatureChartTimeAxis.labels(in: range, timeZone: timeZone),
            ["17:54:10", "17:59:10", "18:04:10"]
        )
    }

    func testDisplayRangeKeepsRollingTenMinutesOnceHistoryIsFull() {
        let last = date(hour: 18, minute: 4, second: 0)
        let range = TemperatureChartTimeAxis.displayRange(
            lastSample: last
        )

        XCTAssertEqual(
            range.lowerBound.timeIntervalSince(last.addingTimeInterval(-10 * 60)),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(range.upperBound, last)
    }

    func testHistoryStoreRoundTripDropsSamplesOlderThanTenMinutes() {
        let defaults = UserDefaults(suiteName: "fanbar.tests.temperatureHistory")!
        defaults.removePersistentDomain(forName: "fanbar.tests.temperatureHistory")
        let now = date(hour: 18, minute: 4, second: 0)
        let samples = [
            ThermalReading(
                sampledAt: now.addingTimeInterval(-12 * 60),
                cpuCelsius: 40,
                gpuCelsius: nil
            ),
            ThermalReading(
                sampledAt: now.addingTimeInterval(-2 * 60),
                cpuCelsius: 50,
                gpuCelsius: 55
            )
        ]

        TemperatureHistoryStore.save(samples, to: defaults)
        let loaded = TemperatureHistoryStore.load(from: defaults, now: now)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.cpuCelsius, 50)
    }

    private func date(hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                year: 2026,
                month: 9,
                day: 20,
                hour: hour,
                minute: minute,
                second: second
            )
        )!
    }
}
