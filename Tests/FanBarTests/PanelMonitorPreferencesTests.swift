import XCTest
@testable import FanBar

final class PanelMonitorPreferencesTests: XCTestCase {
    func testMissingKeyMeansDefaultAndEmptyMeansNone() {
        XCTAssertEqual(PanelMonitorPreferences.modules(from: nil), [.cpu, .memory, .gpu, .disk])
        XCTAssertEqual(PanelMonitorPreferences.modules(from: ""), [])
    }

    func testOrderIsKeptAndUnknownOrRepeatedTokensAreSkipped() {
        XCTAssertEqual(PanelMonitorPreferences.modules(from: "disk,cpu"), [.disk, .cpu])
        XCTAssertEqual(PanelMonitorPreferences.modules(from: "network, memory,cpu,memory"), [.memory, .cpu])
    }

    func testRawValueRoundTrips() {
        let modules: [PanelMonitorModule] = [.gpu, .disk, .cpu]
        let raw = PanelMonitorPreferences.rawValue(for: modules)
        XCTAssertEqual(raw, "gpu,disk,cpu")
        XCTAssertEqual(PanelMonitorPreferences.modules(from: raw), modules)
        XCTAssertEqual(PanelMonitorPreferences.rawValue(for: []), "")
    }

    func testMovingIntoAnotherModulesPlace() {
        let all = PanelMonitorPreferences.defaultModules
        XCTAssertEqual(PanelMonitorPreferences.moving(.disk, to: .memory, in: all), [.cpu, .disk, .memory, .gpu])
        XCTAssertEqual(PanelMonitorPreferences.moving(.cpu, to: .gpu, in: all), [.memory, .gpu, .cpu, .disk])
        XCTAssertEqual(PanelMonitorPreferences.moving(.cpu, to: .cpu, in: all), all)
        XCTAssertEqual(PanelMonitorPreferences.moving(.gpu, to: .disk, in: [.cpu]), [.cpu])
    }

    func testMovingOneStepStopsAtEitherEnd() {
        let all = PanelMonitorPreferences.defaultModules
        XCTAssertEqual(PanelMonitorPreferences.moving(.gpu, by: -1, in: all), [.cpu, .gpu, .memory, .disk])
        XCTAssertEqual(PanelMonitorPreferences.moving(.gpu, by: 1, in: all), [.cpu, .memory, .disk, .gpu])
        XCTAssertNil(PanelMonitorPreferences.moving(.cpu, by: -1, in: all))
        XCTAssertNil(PanelMonitorPreferences.moving(.disk, by: 1, in: all))
    }

    func testOddCountGivesTheLastModuleARowOfItsOwn() {
        XCTAssertEqual(PanelMonitorPreferences.rows([]), [])
        XCTAssertEqual(PanelMonitorPreferences.rows([.memory]), [[.memory]])
        XCTAssertEqual(PanelMonitorPreferences.rows([.cpu, .memory, .disk]), [[.cpu, .memory], [.disk]])
        XCTAssertEqual(PanelMonitorPreferences.rows(PanelMonitorPreferences.defaultModules),
                       [[.cpu, .memory], [.gpu, .disk]])
    }

    func testMissingListsModulesNotShownInCanonicalOrder() {
        XCTAssertEqual(PanelMonitorPreferences.missing(from: [.disk, .cpu]), [.memory, .gpu])
        XCTAssertEqual(PanelMonitorPreferences.missing(from: PanelMonitorPreferences.defaultModules), [])
    }
}
