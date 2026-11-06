import XCTest
@testable import FanBar

final class SystemUsageReaderTests: XCTestCase {
    func testCPUFractionIsBusyShareOfTickDelta() {
        let previous = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let current = CPUTicks(user: 130, system: 60, idle: 900, nice: 10)

        // Busy +50 (user 30, system 10, nice 10) out of +150 total ticks.
        XCTAssertEqual(
            SystemUsageReader.cpuFraction(previous: previous, current: current) ?? -1,
            50.0 / 150.0,
            accuracy: 1e-9
        )
    }

    func testCPUFractionHandlesCounterWraparound() {
        let previous = CPUTicks(user: UInt32.max - 4, system: 0, idle: UInt32.max - 9, nice: 0)
        let current = CPUTicks(user: 5, system: 0, idle: 10, nice: 0)

        // Wrapped deltas are user +10 and idle +20.
        XCTAssertEqual(
            SystemUsageReader.cpuFraction(previous: previous, current: current) ?? -1,
            10.0 / 30.0,
            accuracy: 1e-9
        )
    }

    func testCPUFractionIsNilWithoutElapsedTicks() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        XCTAssertNil(SystemUsageReader.cpuFraction(previous: ticks, current: ticks))
    }

    func testMemoryBreakdownFollowsActivityMonitorCategories() {
        var stats = vm_statistics64()
        stats.internal_page_count = 60
        stats.purgeable_count = 10
        stats.wire_count = 20
        stats.external_page_count = 15
        stats.compressor_page_count = 5

        let memory = SystemUsageReader.memoryBreakdown(
            statistics: stats,
            pageSize: 100,
            totalBytes: 20_000,
            swapUsedBytes: 0
        )

        // App = (internal 60 − purgeable 10) + wired 20; cache = external 15 + purgeable 10.
        XCTAssertEqual(memory.appBytes, 7_000)
        XCTAssertEqual(memory.cachedBytes, 2_500)
        XCTAssertEqual(memory.compressedBytes, 500)
        XCTAssertEqual(memory.usedBytes, 7_500)
        XCTAssertEqual(memory.freeBytes, 10_000)
        XCTAssertEqual(SystemUsage(memory: memory).memoryFraction ?? -1, 0.375, accuracy: 1e-9)
    }

    func testDiskFractionIsCapacityWeighted() {
        let usage = SystemUsage(disks: [
            DiskVolumeUsage(id: "/", name: "Macintosh HD", isInternal: true, usedBytes: 300, totalBytes: 1_000),
            DiskVolumeUsage(id: "/Volumes/T7", name: "T7", isInternal: false, usedBytes: 90, totalBytes: 100)
        ])

        // 390 of 1,100 bytes, not the 63% average of 30% and 90%.
        XCTAssertEqual(usage.diskFraction ?? -1, 390.0 / 1_100.0, accuracy: 1e-9)
        XCTAssertEqual(usage.diskTotalBytes, 1_100)
    }

    func testFractionsAreNilWithoutData() {
        let usage = SystemUsage()
        XCTAssertNil(usage.memoryFraction)
        XCTAssertNil(usage.diskFraction)
        XCTAssertNil(usage.diskUsedBytes)
    }

    func testSampleReadsMemoryAndBootVolume() {
        // The first sample has no CPU baseline, but memory and disks come from the system on every call.
        let reader = SystemUsageReader()
        let first = reader.sample()
        XCTAssertNil(first.cpuFraction)
        XCTAssertTrue(first.cpuCoreFractions.isEmpty)
        XCTAssertGreaterThan(first.memory?.totalBytes ?? 0, 0)
        XCTAssertEqual(first.disks.first?.id, "/")

        let second = reader.sample()
        XCTAssertEqual(second.cpuCoreFractions.count, second.cpuCoreCount)
    }
}

final class TemperatureChartRangeTests: XCTestCase {
    func testRangesAreTenThirtyAndSixtyMinutes() {
        XCTAssertEqual(TemperatureChartRange.allCases.map(\.duration), [600, 1800, 3600])
    }

    func testRetainedHistoryCoversLongestRange() {
        XCTAssertGreaterThanOrEqual(
            TemperatureChartTimeAxis.retainedDuration,
            TemperatureChartRange.allCases.map(\.duration).max() ?? 0
        )
    }

    func testDisplayRangeFollowsSelectedDuration() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        let range = TemperatureChartTimeAxis.displayRange(
            lastSample: end,
            duration: TemperatureChartRange.oneHour.duration
        )
        XCTAssertEqual(range.lowerBound, end.addingTimeInterval(-3600))
        XCTAssertEqual(range.upperBound, end)
    }
}

final class HyperThreadMergingTests: XCTestCase {
    func testSiblingThreadsAverageIntoOneCore() {
        let merged = SystemUsageReader.mergingHyperThreadPairs([0.2, 0.4, 1.0, 0.0])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0], 0.3, accuracy: 1e-9)
        XCTAssertEqual(merged[1], 0.5, accuracy: 1e-9)
    }

    func testOddCountKeepsTheLastThread() {
        let merged = SystemUsageReader.mergingHyperThreadPairs([0.2, 0.4, 0.9])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1], 0.9, accuracy: 1e-9)
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue(SystemUsageReader.mergingHyperThreadPairs([]).isEmpty)
    }
}
