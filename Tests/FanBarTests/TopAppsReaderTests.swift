import XCTest
@testable import FanBar

final class TopAppsReaderTests: XCTestCase {
    func testHelpersCountTowardTheOutermostApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework"
            + "/Versions/131/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        XCTAssertEqual(TopAppsReader.bundlePath(forExecutable: helper), "/Applications/Google Chrome.app")
        XCTAssertEqual(TopAppsReader.bundlePath(forExecutable: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
                       "/Applications/Xcode.app")
        XCTAssertEqual(TopAppsReader.bundlePath(forExecutable: "/System/Library/CoreServices/Finder.app"),
                       "/System/Library/CoreServices/Finder.app")
    }

    func testProcessesOutsideAnAppStandAlone() {
        XCTAssertNil(TopAppsReader.bundlePath(forExecutable: "/opt/homebrew/bin/node"))
        XCTAssertNil(TopAppsReader.bundlePath(forExecutable: "/usr/libexec/applessd"))
    }

    func testFirstSampleIsBaselineThenAppsAreRankedAndCapped() throws {
        let reader = TopAppsReader()
        XCTAssertNil(reader.sample(now: 1_000_000_000))
        // Burn a little CPU so at least this test process shows up.
        var sum = 0.0
        for index in 0..<3_000_000 {
            sum += Double(index).squareRoot()
        }
        XCTAssertGreaterThan(sum, 0)
        let snapshot = try XCTUnwrap(reader.sample(now: 1_500_000_000))
        XCTAssertGreaterThan(snapshot.processCount, 0)
        XCTAssertFalse(snapshot.apps.isEmpty)
        XCTAssertLessThanOrEqual(snapshot.apps.count, TopAppsReader.limit)
        XCTAssertEqual(snapshot.apps.map(\.percent), snapshot.apps.map(\.percent).sorted(by: >))
        XCTAssertEqual(Set(snapshot.apps.map(\.id)).count, snapshot.apps.count)
    }

    func testResetStartsOverWithABaseline() {
        let reader = TopAppsReader()
        _ = reader.sample(now: 1_000_000_000)
        reader.reset()
        XCTAssertNil(reader.sample(now: 2_000_000_000))
    }
}
