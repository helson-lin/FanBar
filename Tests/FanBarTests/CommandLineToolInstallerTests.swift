import XCTest
@testable import FanBar

@MainActor
final class CommandLineToolInstallerTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/tmp")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Builds `<parent>/FanBar.app` with an executable `Contents/Helpers/fanbar`.
    private func makeApp(in parent: URL) throws -> URL {
        let app = parent.appendingPathComponent("FanBar.app")
        let tool = app.appendingPathComponent(CommandLineToolInstaller.toolRelativePath)
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return app
    }

    private func state(app: URL, link: URL) -> CommandLineToolInstaller.State {
        CommandLineToolInstaller.state(
            toolURL: app.appendingPathComponent(CommandLineToolInstaller.toolRelativePath),
            linkURL: link
        )
    }

    func testBuildWithoutTheToolIsUnavailable() {
        XCTAssertEqual(state(app: root.appendingPathComponent("FanBar.app"), link: root.appendingPathComponent("fanbar")), .unavailable)
    }

    func testDetectsEveryLinkState() throws {
        let app = try makeApp(in: root)
        let link = root.appendingPathComponent("bin/fanbar")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertEqual(state(app: app, link: link), .notInstalled)

        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: app.appendingPathComponent(CommandLineToolInstaller.toolRelativePath)
        )
        XCTAssertEqual(state(app: app, link: link), .installed)

        try FileManager.default.removeItem(at: link)
        let other = try makeApp(in: root.appendingPathComponent("Old"))
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: other.appendingPathComponent(CommandLineToolInstaller.toolRelativePath)
        )
        XCTAssertEqual(state(app: app, link: link), .linkedElsewhere)

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertEqual(state(app: app, link: link), .blocked)

        try FileManager.default.removeItem(at: link)
        try Data().write(to: link)
        XCTAssertEqual(state(app: app, link: link), .blocked)
    }

    func testOnlyReadOnlyVolumesNeedAMove() throws {
        let app = try makeApp(in: root)
        let tool = app.appendingPathComponent(CommandLineToolInstaller.toolRelativePath)
        let link = root.appendingPathComponent("fanbar")
        // An Applications folder on a writable external disk is fine.
        XCTAssertEqual(CommandLineToolInstaller.state(toolURL: tool, linkURL: link, isOnReadOnlyVolume: false), .notInstalled)
        XCTAssertEqual(CommandLineToolInstaller.state(toolURL: tool, linkURL: link, isOnReadOnlyVolume: true), .needsMove)
    }

    func testTranslocatedCopyMustMoveFirst() throws {
        let app = try makeApp(in: root.appendingPathComponent("AppTranslocation/ABC/d"))
        XCTAssertEqual(state(app: app, link: root.appendingPathComponent("fanbar")), .needsMove)
    }

    func testInstallAndUninstallInAWritableDirectory() async throws {
        let app = try makeApp(in: root)
        let link = root.appendingPathComponent("bin/fanbar")
        let installer = CommandLineToolInstaller(appURL: app, linkURL: link, readSearchPath: { nil })
        XCTAssertEqual(installer.state, .notInstalled)

        installer.install()
        while installer.isWorking {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(installer.state, .installed)
        XCTAssertNil(installer.failure)

        installer.uninstall()
        while installer.isWorking {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(installer.state, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
    }

    func testUninstallLeavesForeignFilesAlone() throws {
        let app = try makeApp(in: root)
        let link = root.appendingPathComponent("fanbar")
        try Data("mine".utf8).write(to: link)
        let installer = CommandLineToolInstaller(appURL: app, linkURL: link, readSearchPath: { nil })
        installer.uninstall()
        XCTAssertFalse(installer.isWorking)
        XCTAssertEqual(try Data(contentsOf: link), Data("mine".utf8))
    }

    func testInstalledLinkShadowedByAnEarlierFanbarIsReported() async throws {
        let app = try makeApp(in: root)
        let bin = root.appendingPathComponent("bin")
        let link = bin.appendingPathComponent("fanbar")
        let earlier = root.appendingPathComponent("local-bin")
        try FileManager.default.createDirectory(at: earlier, withIntermediateDirectories: true)
        let other = earlier.appendingPathComponent("fanbar")
        try FileManager.default.createSymbolicLink(at: other, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        let searchPath = "\(earlier.path):\(bin.path):/usr/bin"
        let installer = CommandLineToolInstaller(appURL: app, linkURL: link, readSearchPath: { searchPath })

        installer.install()
        while installer.isWorking {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await installer.settlePathResolution()
        XCTAssertEqual(installer.state, .installed)
        XCTAssertEqual(installer.pathResolution, .shadowed(by: other.path))

        try FileManager.default.removeItem(at: other)
        installer.refresh()
        await installer.settlePathResolution()
        XCTAssertEqual(installer.pathResolution, .resolvesToTool)
    }

    func testNoResolutionUntilInstalled() async throws {
        let app = try makeApp(in: root)
        let installer = CommandLineToolInstaller(
            appURL: app,
            linkURL: root.appendingPathComponent("bin/fanbar"),
            readSearchPath: { "/usr/bin" }
        )
        await installer.settlePathResolution()
        XCTAssertEqual(installer.state, .notInstalled)
        XCTAssertNil(installer.pathResolution)
    }

    func testShellAndAppleScriptQuoting() {
        XCTAssertEqual(CommandLineToolInstaller.quoted("/A b/it's"), "'/A b/it'\\''s'")
        XCTAssertEqual(CommandLineToolInstaller.appleScriptString(#"say "hi" \ ok"#), #""say \"hi\" \\ ok""#)
    }
}
