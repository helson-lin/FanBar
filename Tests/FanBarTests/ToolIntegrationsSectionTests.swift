import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

/// The General tab's Command Line & Automation section: present with either
/// tool, sized for what it holds, and absent from builds that ship neither.
@MainActor
final class ToolIntegrationsSectionTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A CLI installer whose app ships the tool, or one without it.
    private func makeTool(available: Bool) throws -> CommandLineToolInstaller {
        let app = root.appendingPathComponent("\(UUID().uuidString)/FanBar.app")
        if available {
            let tool = app.appendingPathComponent(CommandLineToolInstaller.toolRelativePath)
            try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        return CommandLineToolInstaller(
            appURL: app,
            linkURL: root.appendingPathComponent("bin/fanbar"),
            readSearchPath: { nil }
        )
    }

    /// A Raycast installer with bundled scripts and Raycast present, or one without scripts.
    private func makeRaycast(available: Bool) throws -> RaycastScriptsInstaller {
        let source = root.appendingPathComponent("\(UUID().uuidString)/Raycast")
        if available {
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("#!/bin/bash\n".utf8).write(to: source.appendingPathComponent("fanbar-auto.sh"))
        }
        return RaycastScriptsInstaller(
            sourceURL: source,
            destinationURL: root.appendingPathComponent("Support/Raycast"),
            isRaycastInstalled: { true },
            copyToPasteboard: { _ in },
            openRaycast: {}
        )
    }

    private func height(tool: Bool, raycast: Bool) throws -> CGFloat {
        let section = ToolIntegrationsSection(
            tool: try makeTool(available: tool),
            raycast: try makeRaycast(available: raycast)
        )
        let host = NSHostingView(rootView: VStack(spacing: 0) { section }.frame(width: 520))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testInstallerFixturesHaveTheIntendedStates() throws {
        XCTAssertEqual(try makeTool(available: true).state, .notInstalled)
        XCTAssertEqual(try makeTool(available: false).state, .unavailable)
        XCTAssertEqual(try makeRaycast(available: true).state, .ready)
        XCTAssertEqual(try makeRaycast(available: false).state, .unavailable)
    }

    func testSectionIsAbsentWhenTheBuildShipsNeitherTool() throws {
        XCTAssertEqual(try height(tool: false, raycast: false), 0, accuracy: 0.5)
    }

    func testSectionShowsWhicheverToolIsShipped() throws {
        let toolOnly = try height(tool: true, raycast: false)
        let raycastOnly = try height(tool: false, raycast: true)
        let both = try height(tool: true, raycast: true)
        // Header, card and footer come with even a single row.
        XCTAssertGreaterThan(toolOnly, 80)
        XCTAssertGreaterThan(raycastOnly, 80)
        // Both rows share one card: taller than either alone, but by one row,
        // not by a second header and footer.
        XCTAssertGreaterThan(both, max(toolOnly, raycastOnly))
        XCTAssertLessThan(both, toolOnly + raycastOnly)
    }

    func testLanguageChangesRefreshTheExistingSectionAndBothRows() throws {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer { UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey) }
        UserDefaults.standard.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
        let raycast = try makeRaycast(available: true)
        raycast.setUp()
        let host = NSHostingView(rootView: ToolIntegrationsSection(
            tool: try makeTool(available: true),
            raycast: raycast
        ).frame(width: 520))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // Keep the same hosting view and installers: recreating the root would
        // hide the stale-child bug seen when switching French to Japanese.
        var frenchImage: Data?
        for language in [FanBarLanguage.french, .japanese, .english, .chinese, .traditionalChinese, .russian] {
            UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            let actual = try snapshot(host)
            let reference = NSHostingView(rootView: ToolIntegrationsSection(
                tool: try makeTool(available: true), raycast: raycast
            ).frame(width: 520))
            reference.frame = host.frame
            window.contentView = reference
            reference.layoutSubtreeIfNeeded()
            XCTAssertEqual(actual, try snapshot(reference), "\(language): existing section differs from fresh translations")
            window.contentView = host
            if language == .french { frenchImage = actual }
            if language == .japanese {
                XCTAssertNotEqual(actual, frenchImage, "Fixture must distinguish stale French from Japanese")
            }
        }
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
