import XCTest
@testable import FanBar

/// Covers persisting the temperature trace across relaunches, so the chart
/// doesn't start blank again right after the app reopens.
final class TemperatureHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TemperatureHistoryStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func reading(secondsAgo: TimeInterval, from now: Date) -> ThermalReading {
        ThermalReading(
            sampledAt: now.addingTimeInterval(-secondsAgo),
            cpuCelsius: 42,
            gpuCelsius: 41,
            ssdCelsius: 30,
            batteryCelsius: 28
        )
    }

    func testLoadWithoutSavedDataReturnsEmpty() {
        XCTAssertEqual(TemperatureHistoryStore.load(from: defaults), [])
    }

    func testSaveThenLoadRoundTrips() {
        let now = Date()
        let samples = [reading(secondsAgo: 4, from: now), reading(secondsAgo: 2, from: now)]

        TemperatureHistoryStore.save(samples, to: defaults)
        let loaded = TemperatureHistoryStore.load(from: defaults, now: now)

        XCTAssertEqual(loaded, samples)
    }

    func testLoadDropsSamplesOlderThanHistoryDuration() {
        let now = Date()
        let stale = reading(secondsAgo: TemperatureChart.historyDuration + 60, from: now)
        let fresh = reading(secondsAgo: 30, from: now)

        TemperatureHistoryStore.save([stale, fresh], to: defaults)
        let loaded = TemperatureHistoryStore.load(from: defaults, now: now)

        XCTAssertEqual(loaded, [fresh])
    }

    func testLoadWithCorruptedDataReturnsEmpty() {
        defaults.set(Data([0xFF, 0x00, 0x12]), forKey: TemperatureHistoryStore.preferenceKey)
        XCTAssertEqual(TemperatureHistoryStore.load(from: defaults), [])
    }
}
