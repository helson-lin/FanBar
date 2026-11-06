import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
private final class EmptyLanguageTestReceipts: CompatibilityReceiptStoring {
    func save(_ receipt: CompatibilitySavedReceipt) throws {}
    func receipts() throws -> [CompatibilitySavedReceipt] {
        []
    }

    func remove(reportID: String) throws {}
}

@MainActor
private final class UnreadableLanguageTestReceipts: CompatibilityReceiptStoring {
    func save(_ receipt: CompatibilitySavedReceipt) throws {}
    func receipts() throws -> [CompatibilitySavedReceipt] {
        throw CompatibilityServiceError.credentialStorage
    }

    func remove(reportID: String) throws {}
}

/// Compare a retained view against a freshly constructed view in each language.
/// Static fixtures prevent sensor polling or animation from hiding stale text.
@MainActor
final class InterfaceLanguageRefreshTests: XCTestCase {
    private func makeController() -> FanController {
        let source = FakeFanReadingSource()
        return FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source },
                             readUsage: { SystemUsage() }, refreshInterval: nil)
    }

    func testIndependentWindowsSheetsAndSettingsChildrenRefresh() throws {
        let controller = makeController()
        let store = EmptyLanguageTestReceipts()
        // A failed attached upload shows its error and a retry button.
        let failedDiagnostic = DiagnosticUploadCoordinator(collect: { await controller.collectDiagnosticReport() },
                                                           makeService: { _ in throw CompatibilityServiceError.notConfigured },
                                                           store: store)
        failedDiagnostic.exportFailed()
        let cases: [(String, () -> AnyView)] = [
            ("compatibility", { AnyView(DeviceCompatibilityView(controller: controller)) }),
            ("report", { AnyView(CompatibilityReportPreview(data: Data("{}".utf8))) }),
            ("receipts", { AnyView(CompatibilityReceiptsView(store: store)) }),
            ("receipt-storage-error", { AnyView(CompatibilityReceiptsView(store: UnreadableLanguageTestReceipts())) }),
            ("service-banner", { AnyView(ControlServiceBanner(controller: controller)) }),
            ("preset-actions", { AnyView(VStack { PresetActionsMenu(controller: controller, preset: .fallback) }) }),
            ("custom-preset-actions", {
                AnyView(VStack { PresetActionsMenu(controller: controller, preset: .custom(UUID())) })
            }),
            ("curve-editor", { AnyView(FanCurveEditorView(controller: controller)) }),
            ("new-preset", { AnyView(NewCustomPresetForm(controller: controller, isPresented: .constant(true))) }),
            ("log", { AnyView(VStack { TemperatureLogSettingsView(controller: controller) }) }),
            ("icon-picker", { AnyView(MenuBarIconStylePicker(controller: controller)) }),
            ("app-icon", { AnyView(AppIconPickerRow()) }),
            ("fan-readout", {
                AnyView(PanelFanReadout(
                    fan: FanReading(index: 0, minimumRPM: 1200, currentRPM: 1850, maximumRPM: 6000, isManual: false)
                ))
            }),
            ("resources", {
                AnyView(PanelResourceList(
                    usage: SystemUsage(), thermal: nil, cpuHistory: [], gpuHistory: [], animates: false, expanded: .constant(nil)
                ))
            }),
            ("chart", { AnyView(TemperatureChart(samples: [], range: .constant(.tenMinutes), alertThreshold: 90)) }),
            ("attached-diagnostic", { AnyView(AttachedDiagnosticStatus(model: failedDiagnostic, retry: {})) })
        ]
        for (name, make) in cases {
            try assertRefresh(name: name, make: make)
        }
    }

    func testWelcomeRefreshesWithoutControllerChanges() throws {
        let controller = makeController()
        try assertRefresh(name: "welcome") { AnyView(OnboardingCard(controller: controller, onOpenMenu: {}, onDismiss: {})) }
    }

    func testMenuRefreshesWithoutControllerChanges() throws {
        let controller = makeController()
        try assertRefresh(name: "menu") { AnyView(FanMenu(controller: controller)) }
    }

    func testAlertSoundRowRefreshesWithoutControllerChanges() throws {
        let controller = makeController()
        try assertRefresh(name: "sound") { AnyView(ThermalAlertSoundRow(controller: controller)) }
    }

    func testInstallerFailureTranslatesWithoutRepeatingTheAction() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: FanBarLanguage.preferenceKey)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.set(saved, forKey: FanBarLanguage.preferenceKey)
            try? FileManager.default.removeItem(at: root)
        }
        let source = root.appendingPathComponent("source")
        let blocked = root.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("#!/bin/sh".utf8).write(to: source.appendingPathComponent("command.sh"))
        try Data().write(to: blocked)
        let installer = RaycastScriptsInstaller(sourceURL: source, destinationURL: blocked,
                                               isRaycastInstalled: { true }, copyToPasteboard: { _ in }, openRaycast: {})
        defaults.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
        installer.setUp()
        let french = try XCTUnwrap(installer.failure)
        defaults.set(FanBarLanguage.japanese.rawValue, forKey: FanBarLanguage.preferenceKey)
        let japanese = try XCTUnwrap(installer.failure)
        XCTAssertNotEqual(french, japanese)
        XCTAssertTrue(japanese.hasPrefix(fanBarFormat("无法准备 Raycast 脚本：%@", "Could not prepare the Raycast scripts: %@", "")))
    }

    func testDiagnosticMessagesResolveInTheCurrentLanguage() throws {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer { UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey) }
        let report = DiagnosticReport(
            diagnosticID: "language-test", capturedAt: "2026-10-21T00:00:00Z",
            device: CompatibilityDevice(modelIdentifier: "Mac16,10", processor: "Apple M4",
                                        macOSVersion: "27.0", appVersion: "0.7.0", helperVersion: "32"),
            helperState: "enabled", probes: []
        )
        let model = DiagnosticUploadCoordinator(collect: { report }, makeService: { _ in
            throw CompatibilityServiceError.notConfigured
        }, store: EmptyLanguageTestReceipts())
        UserDefaults.standard.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
        model.exportFailed()
        let french = try XCTUnwrap(model.error)
        UserDefaults.standard.set(FanBarLanguage.japanese.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(model.error, fanBarText("无法保存报告，请选择其他位置后重试。", "Unable to save. Choose another location and retry."))
        XCTAssertNotEqual(model.error, french)
        try assertRefresh(name: "diagnostics") { AnyView(DiagnosticUploadView(controller: self.makeController(), model: model)) }
    }

    func testAppKitWindowTitlesRefreshWithoutReopening() {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer { UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey) }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let title = LocalizedWindowTitle(window: window, chinese: "设备兼容性", english: "Device Compatibility")
        withExtendedLifetime(title) {
            for language in [FanBarLanguage.french, .japanese, .english, .chinese, .traditionalChinese, .russian] {
                UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
                // Match the notification delivered by the language picker.
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                XCTAssertEqual(window.title, fanBarText("设备兼容性", "Device Compatibility"))
            }
        }
    }

    private func assertRefresh(name: String, make: () -> AnyView) throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: FanBarLanguage.preferenceKey)
        defer { defaults.set(saved, forKey: FanBarLanguage.preferenceKey) }
        defaults.set(FanBarLanguage.french.rawValue, forKey: FanBarLanguage.preferenceKey)
        func content() -> some View {
            make().environment(\.colorScheme, .light).environment(\.isPanelVisible, false)
                .modifier(NoScrollIndicators())
                // The welcome card uses an appearance fade. Snapshot text
                // after a language change, independent of runner frame rate.
                .transaction {
                    $0.disablesAnimations = true
                    $0.animation = nil
                }
                .frame(width: 740, height: 850, alignment: .topLeading)
        }
        let host = NSHostingView(rootView: content())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let referenceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 850),
                                       styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        referenceWindow.orderBack(nil)
        defer {
            window.orderOut(nil)
            referenceWindow.orderOut(nil)
            window.contentView = nil
            referenceWindow.contentView = nil
        }
        var retainedDraft: String?
        for language in [FanBarLanguage.french, .japanese, .english, .chinese, .traditionalChinese, .russian] {
            defaults.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            if name == "new-preset" {
                let field = try XCTUnwrap(editableFields(in: host).first)
                if let retainedDraft {
                    XCTAssertEqual(field.stringValue, retainedDraft, "Language changes must preserve the draft name")
                } else { retainedDraft = field.stringValue }
            }
            let actual = try snapshot(host, hideEditableText: name == "new-preset")
            let fresh = NSHostingView(rootView: content())
            fresh.frame = host.frame
            referenceWindow.contentView = fresh
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            fresh.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            fresh.layoutSubtreeIfNeeded()
            let expected = try snapshot(fresh, hideEditableText: name == "new-preset")
            referenceWindow.contentView = nil
            if actual != expected {
                // Allow minor antialiasing and curve-selection differences,
                // measured against foreground pixels rather than blank space.
                let difference = try LanguageRefreshRendering.difference(actual, expected)
                let tolerance = name == "welcome" ? 0.05 : 0.03
                if difference >= tolerance {
                    try saveMismatch(name: name, language: language, actual: actual, expected: expected)
                }
                XCTAssertLessThan(difference, tolerance, "\(name) retained stale text for \(language)")
            }
        }
    }

    private func saveMismatch(name: String, language: FanBarLanguage, actual: Data, expected: Data) throws {
        try actual.write(to: URL(fileURLWithPath: "/tmp/fanbar-\(name)-\(language)-actual.png"))
        try expected.write(to: URL(fileURLWithPath: "/tmp/fanbar-\(name)-\(language)-expected.png"))
    }

    private func snapshot(_ view: NSView, hideEditableText: Bool = false) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if hideEditableText {
            // A newly opened form suggests a name in its current language;
            // the retained form must keep its original draft. Compare that
            // state above, and mask only editable values in the image check.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.white.setFill()
            for field in editableFields(in: view) {
                var rect = view.convert(field.bounds, from: field)
                if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
                NSBezierPath(rect: rect).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }.map { [$0] } ?? []
        return own + view.subviews.flatMap { editableFields(in: $0) }
    }
}

/// A scrollbar appears only when content overflows (or always, with legacy
/// scrollers) and its gutter narrows the content, so a short retained view and
/// a fresh one can wrap differently. Ask SwiftUI for no indicators in both.
private struct NoScrollIndicators: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollIndicators(.never)
        } else {
            content
        }
    }
}

@MainActor
enum LanguageRefreshRendering {
    static func difference(_ actual: Data, _ expected: Data) throws -> Double {
        let left = try XCTUnwrap(NSBitmapImageRep(data: actual))
        let right = try XCTUnwrap(NSBitmapImageRep(data: expected))
        guard left.pixelsWide == right.pixelsWide, left.pixelsHigh == right.pixelsHigh,
              left.samplesPerPixel == right.samplesPerPixel else { return 1 }
        let lhs = try XCTUnwrap(left.bitmapData)
        let rhs = try XCTUnwrap(right.bitmapData)
        let channels = left.samplesPerPixel
        let alphaFirst = left.bitmapFormat.contains(.alphaFirst)
        let colorOffset = alphaFirst ? 1 : 0
        let alphaOffset = alphaFirst ? 0 : channels - 1
        var foreground = 0
        var changed = 0
        for row in 0..<left.pixelsHigh {
            for column in 0..<left.pixelsWide {
                let leftOffset = row * left.bytesPerRow + column * channels
                let rightOffset = row * right.bytesPerRow + column * channels
                if left.hasAlpha, lhs[leftOffset + alphaOffset] < 128, rhs[rightOffset + alphaOffset] < 128 { continue }
                let ink = (0..<3).contains { lhs[leftOffset + colorOffset + $0] < 180 || rhs[rightOffset + colorOffset + $0] < 180 }
                guard ink else { continue }
                foreground += 1
                if (0..<3).contains(where: {
                    abs(Int(lhs[leftOffset + colorOffset + $0]) - Int(rhs[rightOffset + colorOffset + $0])) > 32
                }) {
                    changed += 1
                }
            }
        }
        return Double(changed) / Double(max(foreground, 1))
    }
}
