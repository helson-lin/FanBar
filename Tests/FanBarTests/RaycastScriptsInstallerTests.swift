import Darwin
import XCTest
@testable import FanBar

@MainActor
final class RaycastScriptsInstallerTests: XCTestCase {
    // XCTest makes a fresh instance per test, so `root` can be a constant. It
    // and the helpers below are nonisolated because the setUp/tearDown
    // overrides are; they touch no main-actor state.
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private nonisolated var source: URL { root.appendingPathComponent("Bundle/Raycast") }
    private nonisolated var destination: URL { root.appendingPathComponent("Support/Raycast") }
    private var pasted: [String] = []
    private var opened = 0

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["fanbar-auto.sh", "fanbar-preset.sh"] {
            try writeScript(name, "echo \(name)")
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private nonisolated func writeScript(_ name: String, _ body: String) throws {
        let url = source.appendingPathComponent(name)
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    private func makeInstaller(sourceURL: URL? = nil, raycast: Bool = true) -> RaycastScriptsInstaller {
        RaycastScriptsInstaller(
            sourceURL: sourceURL ?? source,
            destinationURL: destination,
            isRaycastInstalled: { raycast },
            copyToPasteboard: { [weak self] in self?.pasted.append($0) },
            openRaycast: { [weak self] in self?.opened += 1 }
        )
    }

    func testStatesBeforeSetUp() {
        XCTAssertEqual(makeInstaller(sourceURL: root.appendingPathComponent("missing")).state, .unavailable)
        XCTAssertEqual(makeInstaller(raycast: false).state, .raycastMissing)
        XCTAssertEqual(makeInstaller().state, .ready)
    }

    func testSetUpCopiesExecutableScriptsCopiesThePathAndOpensRaycast() {
        let original = source.appendingPathComponent("fanbar-auto.sh")
        XCTAssertEqual(setxattr(original.path, "com.apple.quarantine", "0081;0;FanBar;", 15, 0, 0), 0)
        let installer = makeInstaller()

        installer.setUp()

        XCTAssertEqual(installer.state, .copied)
        XCTAssertNil(installer.failure)
        XCTAssertEqual(pasted, [destination.path])
        XCTAssertEqual(opened, 1)
        for name in ["fanbar-auto.sh", "fanbar-preset.sh"] {
            let copy = destination.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: copy.path), name)
        }
        let copy = destination.appendingPathComponent("fanbar-auto.sh")
        XCTAssertEqual(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0), -1, "quarantine must not travel")
    }

    func testLaunchSyncWaitsForTheFirstSetUp() {
        makeInstaller().syncIfSetUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testLaunchSyncUpdatesScriptsAndDropsRetiredOnesOnly() throws {
        makeInstaller().setUp()
        let mine = destination.appendingPathComponent("my-own-script.sh")
        try "#!/bin/bash\n".write(to: mine, atomically: true, encoding: .utf8)
        // A newer app: one script changed, one retired.
        try writeScript("fanbar-auto.sh", "echo updated")
        try FileManager.default.removeItem(at: source.appendingPathComponent("fanbar-preset.sh"))

        makeInstaller().syncIfSetUp()

        let auto = try String(contentsOf: destination.appendingPathComponent("fanbar-auto.sh"), encoding: .utf8)
        XCTAssertTrue(auto.contains("echo updated"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("fanbar-preset.sh").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "files FanBar did not ship stay")
    }

    private func destinationText(_ name: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(name), encoding: .utf8)
    }

    func testLaunchSyncKeepsAScriptTheUserEdited() throws {
        makeInstaller().setUp()
        let edited = destination.appendingPathComponent("fanbar-preset.sh")
        try "#!/bin/bash\necho my presets\n".write(to: edited, atomically: true, encoding: .utf8)
        // A newer app changes both scripts.
        try writeScript("fanbar-preset.sh", "echo new preset")
        try writeScript("fanbar-auto.sh", "echo new auto")

        makeInstaller().syncIfSetUp()

        XCTAssertTrue(try destinationText("fanbar-preset.sh").contains("echo my presets"), "the user's edit survives")
        XCTAssertTrue(try destinationText("fanbar-auto.sh").contains("echo new auto"), "untouched scripts still update")

        // And once the user's edit is unchanged, later syncs still leave it alone.
        try writeScript("fanbar-preset.sh", "echo newer preset")
        makeInstaller().syncIfSetUp()
        XCTAssertTrue(try destinationText("fanbar-preset.sh").contains("echo my presets"))
    }

    func testRetiringAScriptKeepsTheUsersEditedCopy() throws {
        makeInstaller().setUp()
        let edited = destination.appendingPathComponent("fanbar-preset.sh")
        try "#!/bin/bash\necho mine\n".write(to: edited, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: source.appendingPathComponent("fanbar-preset.sh"))

        makeInstaller().syncIfSetUp()

        XCTAssertTrue(FileManager.default.fileExists(atPath: edited.path))
    }

    func testDeletingAnEditedCopyBringsBackTheStockScript() throws {
        makeInstaller().setUp()
        let edited = destination.appendingPathComponent("fanbar-preset.sh")
        try "#!/bin/bash\necho mine\n".write(to: edited, atomically: true, encoding: .utf8)
        makeInstaller().syncIfSetUp()
        try FileManager.default.removeItem(at: edited)

        makeInstaller().syncIfSetUp()

        XCTAssertTrue(try destinationText("fanbar-preset.sh").contains("echo fanbar-preset.sh"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: edited.path))
    }

    func testFilesWrittenBeforeTheManifestAreJudgedByContent() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Identical to the bundle: adopted. Different: treated as the user's.
        try FileManager.default.copyItem(
            at: source.appendingPathComponent("fanbar-auto.sh"),
            to: destination.appendingPathComponent("fanbar-auto.sh")
        )
        try "#!/bin/bash\necho someone else\n".write(
            to: destination.appendingPathComponent("fanbar-preset.sh"), atomically: true, encoding: .utf8
        )

        makeInstaller().setUp()
        try writeScript("fanbar-auto.sh", "echo updated auto")
        makeInstaller().syncIfSetUp()

        XCTAssertTrue(try destinationText("fanbar-auto.sh").contains("echo updated auto"))
        XCTAssertTrue(try destinationText("fanbar-preset.sh").contains("echo someone else"))
    }

    func testBundledScriptsMatchTheRepository() throws {
        // package-app.sh copies integrations/raycast as-is; keep the two lists in step.
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scripts = try FileManager.default.contentsOfDirectory(
            atPath: repository.appendingPathComponent("integrations/raycast").path
        ).filter { $0.hasSuffix(".sh") }
        XCTAssertEqual(scripts.count, 4)
        XCTAssertTrue(scripts.allSatisfy { $0.hasPrefix("fanbar-") }, "launch sync only manages fanbar-*.sh")
    }
}
