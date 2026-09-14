import FanBarShared
import XCTest

final class FanBarWidgetSnapshotTests: XCTestCase {
    private func makeTemporaryContainer() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FanBarWidgetSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testSnapshotRoundTripsThroughContainerDirectory() throws {
        let container = try makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let snapshot = FanBarWidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            fans: [
                FanBarWidgetSnapshot.Fan(
                    index: 0,
                    currentRPM: 2_100,
                    minimumRPM: 1_200,
                    maximumRPM: 5_000,
                    isManual: true
                )
            ],
            cpuCelsius: 62.5,
            mode: .fixed,
            isAvailable: true,
            isEnglish: false
        )

        try snapshot.save(containerDirectory: container)

        XCTAssertEqual(FanBarWidgetSnapshot.load(containerDirectory: container), snapshot)
    }

    func testMissingSnapshotFileReturnsNil() throws {
        let container = try makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        XCTAssertNil(FanBarWidgetSnapshot.load(containerDirectory: container))
        XCTAssertEqual(FanBarWidgetSnapshot.loadResult(containerDirectory: container), .missing)
    }

    func testInvalidSnapshotDataIsIgnored() throws {
        let container = try makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let storageDirectory = container.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let storageURL = storageDirectory.appendingPathComponent("fanbar-widget-snapshot.json")
        try Data("not-json".utf8).write(to: storageURL)

        XCTAssertNil(FanBarWidgetSnapshot.load(containerDirectory: container))
        XCTAssertEqual(FanBarWidgetSnapshot.loadResult(containerDirectory: container), .failure)
    }

    func testSaveIntoUnwritableContainerSurfacesError() throws {
        // A file (not a directory) at the container path can never be
        // resolved into a writable "Library/Application Support" subdirectory,
        // so `save` must throw rather than silently succeed.
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("FanBarWidgetSnapshotTests-unwritable-\(UUID().uuidString)")
        try Data().write(to: container)
        defer { try? FileManager.default.removeItem(at: container) }

        let snapshot = FanBarWidgetSnapshot(
            fans: [],
            cpuCelsius: nil,
            mode: .automatic,
            isAvailable: true,
            isEnglish: true
        )

        XCTAssertThrowsError(try snapshot.save(containerDirectory: container)) { error in
            guard case .writeFailed(let reason)? = error as? FanBarWidgetSnapshotError else {
                return XCTFail("expected .writeFailed, got \(error)")
            }
            // The reason must name the path so a failure in a shipped build is
            // actionable from the log alone.
            XCTAssertTrue(reason.contains(container.lastPathComponent), reason)
        }
    }
}
