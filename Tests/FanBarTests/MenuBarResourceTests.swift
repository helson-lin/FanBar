import XCTest
@testable import FanBar

final class MenuBarResourceTests: XCTestCase {
    func testUnavailableAndNonFiniteReadingsUsePlaceholder() {
        var usage = SystemUsage()
        XCTAssertEqual(MenuBarResource.cpu.text(for: usage), "CPU —")
        XCTAssertEqual(MenuBarResource.memory.text(for: usage), "MEM —")
        usage.gpuFraction = .nan
        XCTAssertEqual(MenuBarResource.gpu.text(for: usage), "GPU —")
    }

    func testStylesFormatValuesIndependently() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.24
        XCTAssertEqual(MenuBarResource.cpu.text(for: usage, style: .label), "CPU 24%")
        XCTAssertEqual(MenuBarResource.cpu.text(for: usage, style: .icon), "24%")
        XCTAssertNil(MenuBarResourceStyle(rawValue: "value"))
        XCTAssertNotEqual(MenuBarResource.cpu.stylePreferenceKey, MenuBarResource.gpu.stylePreferenceKey)
    }

    func testPercentagesRoundAndStayWithinDisplayRange() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.246
        usage.gpuFraction = 1.2
        XCTAssertEqual(MenuBarResource.cpu.text(for: usage), "CPU 25%")
        XCTAssertEqual(MenuBarResource.gpu.text(for: usage), "GPU 100%")
        usage.cpuFraction = -0.1
        XCTAssertEqual(MenuBarResource.cpu.text(for: usage), "CPU 0%")
    }
}
