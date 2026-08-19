import XCTest
@testable import FanBar

final class StorageTemperatureResolverTests: XCTestCase {
    /// Intel SMC readings remain authoritative and skip newer fallback APIs.
    func testSMCReadingsWinAndAreAveraged() {
        var embeddedWasRead = false
        var smartWasRead = false

        let temperature = StorageTemperatureResolver.resolve(
            smcValues: [40, 44],
            embeddedNVMe: {
                embeddedWasRead = true
                return 50
            },
            smart: {
                smartWasRead = true
                return 60
            }
        )

        XCTAssertEqual(temperature, 42)
        XCTAssertFalse(embeddedWasRead)
        XCTAssertFalse(smartWasRead)
    }

    /// Apple Silicon uses the embedded NAND sensor before the legacy SMART API.
    func testEmbeddedNVMeWinsWhenSMCIsUnavailable() {
        var smartWasRead = false

        let temperature = StorageTemperatureResolver.resolve(
            smcValues: [],
            embeddedNVMe: { 47 },
            smart: {
                smartWasRead = true
                return 55
            }
        )

        XCTAssertEqual(temperature, 47)
        XCTAssertFalse(smartWasRead)
    }

    /// Intel NVMe and older systems can still fall back to standard SMART.
    func testSMARTIsFinalFallback() {
        let temperature = StorageTemperatureResolver.resolve(
            smcValues: [],
            embeddedNVMe: { nil },
            smart: { 51 }
        )

        XCTAssertEqual(temperature, 51)
    }
}
