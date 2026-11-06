import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

final class CustomCoolingPresetTests: XCTestCase {
    /// Controller tests use the process's standard defaults; these keys are
    /// restored afterwards so the test domain stays as it was.
    private static let touchedKeys = [
        CustomCoolingPresetStore.preferenceKey,
        CoolingPresetPreferences.preferenceKey,
        CoolingPresetPreferences.legacyPreferenceKey,
        FanCurvePreferences.selectionKey,
        FanCurvePreferences.selectionTokenKey,
        FanCurvePreferences.slotsKey,
        FanCurvePreferences.legacyProfileKey
    ]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedDefaults = [:]
        for key in Self.touchedKeys {
            if let value = defaults.object(forKey: key) { savedDefaults[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in Self.touchedKeys {
            if let value = savedDefaults[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private func makeSuite() throws -> (UserDefaults, String) {
        let suite = "CustomCoolingPresetTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: - Identity

    func testPresetIDTokenRoundTrips() {
        let ids: [CoolingPresetID] = [.builtIn(.silent), .builtIn(.extreme), .custom(UUID())]
        for id in ids {
            XCTAssertEqual(CoolingPresetID(token: id.token), id)
        }
        XCTAssertNil(CoolingPresetID(token: "builtin:9"))
        XCTAssertNil(CoolingPresetID(token: "custom:not-a-uuid"))
        XCTAssertNil(CoolingPresetID(token: "2"))
    }

    // MARK: - Naming rules

    func testNameValidation() {
        let taken = [FanCoolingPreset.balanced.title, "Gaming"]
        XCTAssertEqual(CustomPresetRules.problem(with: "   ", takenNames: taken), .empty)
        XCTAssertEqual(
            CustomPresetRules.problem(with: String(repeating: "a", count: 17), takenNames: taken),
            .tooLong
        )
        XCTAssertNil(CustomPresetRules.problem(with: String(repeating: "a", count: 16), takenNames: taken))
        XCTAssertEqual(CustomPresetRules.problem(with: " gaming ", takenNames: taken), .duplicate("gaming"))
        XCTAssertEqual(
            CustomPresetRules.problem(with: FanCoolingPreset.balanced.title, takenNames: taken),
            .duplicate(FanCoolingPreset.balanced.title)
        )
        XCTAssertNil(CustomPresetRules.problem(with: "  Night edit ", takenNames: taken))
    }

    func testDefaultNameUsesFirstFreeNumber() {
        let first = fanBarFormat("自定义 %d", "Custom %d", 1)
        let second = fanBarFormat("自定义 %d", "Custom %d", 2)
        let third = fanBarFormat("自定义 %d", "Custom %d", 3)
        XCTAssertEqual(CustomPresetRules.defaultName(takenNames: []), first)
        XCTAssertEqual(CustomPresetRules.defaultName(takenNames: [first, third]), second)
    }

    func testCopyNameAddsSuffixNumberAndFitsLimit() {
        let suffix = fanBarText(" 副本", " Copy")
        let copy = CustomPresetRules.copyName(of: "Gaming", takenNames: ["Gaming"])
        XCTAssertEqual(copy, "Gaming" + suffix)
        XCTAssertEqual(
            CustomPresetRules.copyName(of: "Gaming", takenNames: ["Gaming", copy]),
            "Gaming" + suffix + " 2"
        )
        let long = CustomPresetRules.copyName(of: String(repeating: "x", count: 16), takenNames: [])
        XCTAssertLessThanOrEqual(long.count, CustomPresetRules.maximumNameLength)
        XCTAssertNil(CustomPresetRules.problem(with: long, takenNames: []))
    }

    // MARK: - Store

    func testStoreRoundTripsPresets() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preset = CustomCoolingPreset(
            name: "Night",
            symbol: .moon,
            curve: FanCoolingPreset.silent.factoryCurve
        )

        CustomCoolingPresetStore.save([preset], defaults: defaults)

        XCTAssertEqual(CustomCoolingPresetStore.load(defaults: defaults), [preset])
    }

    func testStoreDropsDamagedEntriesButKeepsOthers() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = CustomCoolingPreset(name: "Good", symbol: .leaf, curve: FanCoolingPreset.balanced.factoryCurve)
        let goodJSON = try XCTUnwrap(String(bytes: try JSONEncoder().encode(good), encoding: .utf8))
        let blank = goodJSON
            .replacingOccurrences(of: "\"Good\"", with: "\"   \"")
            .replacingOccurrences(of: good.id.uuidString, with: UUID().uuidString)
        let payload = """
        {"version":1,"presets":[{"id":"broken"},\(goodJSON),{"name":"no symbol"},\(blank),\(goodJSON)]}
        """
        defaults.set(Data(payload.utf8), forKey: CustomCoolingPresetStore.preferenceKey)

        // The broken records, the blank name and the repeated id are dropped.
        XCTAssertEqual(CustomCoolingPresetStore.load(defaults: defaults).map(\.name), ["Good"])
    }

    func testStoreCapsLoadedPresetsAtLimit() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let presets = (0..<9).map {
            CustomCoolingPreset(name: "P\($0)", symbol: .star, curve: FanCoolingPreset.balanced.factoryCurve)
        }
        CustomCoolingPresetStore.save(presets, defaults: defaults)

        XCTAssertEqual(CustomCoolingPresetStore.load(defaults: defaults).count, CustomPresetRules.maximumCount)
    }

    // MARK: - Menu shortcuts

    func testShortcutsSkipMissingPresetsAndFollowDisplayOrder() {
        let custom = CoolingPresetID.custom(UUID())
        let missing = CoolingPresetID.custom(UUID())
        let available: [CoolingPresetID] = FanCoolingPreset.allCases.map { .builtIn($0) } + [custom]
        let raw = CoolingPresetPreferences.rawValue(for: [custom, missing])

        XCTAssertEqual(CoolingPresetPreferences.presets(from: raw, available: available), [custom])
        XCTAssertEqual(
            CoolingPresetPreferences.presets(from: "\(custom.token),builtin:0", available: available),
            [.builtIn(.silent), custom]
        )
    }

    func testShortcutsMigrateFromLegacyListOnce() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("3,0", forKey: CoolingPresetPreferences.legacyPreferenceKey)

        CoolingPresetPreferences.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: CoolingPresetPreferences.preferenceKey), "builtin:0,builtin:3")

        defaults.set("1", forKey: CoolingPresetPreferences.legacyPreferenceKey)
        CoolingPresetPreferences.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: CoolingPresetPreferences.preferenceKey), "builtin:0,builtin:3")
    }

    func testRemovingShortcutKeepsLegacyKeyToBuiltIns() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = CoolingPresetID.custom(UUID())
        CoolingPresetPreferences.save([.builtIn(.performance), custom], defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: CoolingPresetPreferences.legacyPreferenceKey), "2")

        CoolingPresetPreferences.removing(custom, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: CoolingPresetPreferences.preferenceKey), "builtin:2")
    }

    // MARK: - Selection persistence

    func testMissingCustomSelectionFallsBackToBalanced() {
        UserDefaults.standard.set(CoolingPresetID.custom(UUID()).token, forKey: FanCurvePreferences.selectionTokenKey)
        UserDefaults.standard.set(FanCoolingPreset.balanced.rawValue, forKey: FanCurvePreferences.selectionKey)

        XCTAssertEqual(FanCurvePreferences.load().selection, .fallback)
    }

    func testOlderBuildSelectionChangeWins() {
        let custom = CustomCoolingPreset(name: "Night", symbol: .moon, curve: FanCoolingPreset.silent.factoryCurve)
        CustomCoolingPresetStore.save([custom])
        UserDefaults.standard.set(CoolingPresetID.custom(custom.id).token, forKey: FanCurvePreferences.selectionTokenKey)
        UserDefaults.standard.set(FanCoolingPreset.balanced.rawValue, forKey: FanCurvePreferences.selectionKey)
        XCTAssertEqual(FanCurvePreferences.load().selection, .custom(custom.id))

        // An older build only rewrote the Int key.
        UserDefaults.standard.set(FanCoolingPreset.extreme.rawValue, forKey: FanCurvePreferences.selectionKey)
        XCTAssertEqual(FanCurvePreferences.load().selection, .builtIn(.extreme))
    }

    // MARK: - Controller

    @MainActor
    private func makeController() -> FanController {
        FanController(notificationCenter: nil, widgetSnapshotDestination: .disabled)
    }

    @MainActor
    func testCreateSelectsNewPresetWithCopiedCurve() throws {
        let controller = makeController()
        let id = try XCTUnwrap(controller.createCustomPreset(name: " Night ", symbol: .moon, copying: .builtIn(.silent)))

        XCTAssertEqual(controller.curveCoolingPreset, id)
        XCTAssertEqual(controller.presetTitle(for: id), "Night")
        XCTAssertEqual(controller.curveProfile.points.map(\.celsius),
                       FanCoolingPreset.silent.factoryCurve.sanitized().points.map(\.celsius))
        XCTAssertEqual(CustomCoolingPresetStore.load().map(\.name), ["Night"])
        XCTAssertEqual(FanCurvePreferences.load().selection, id)
    }

    @MainActor
    func testCreateRejectsDuplicateNamesAndSeventhPreset() {
        let controller = makeController()
        XCTAssertNil(controller.createCustomPreset(
            name: FanCoolingPreset.silent.title,
            symbol: .star,
            copying: .fallback
        ))
        for index in 0..<CustomPresetRules.maximumCount {
            XCTAssertNotNil(controller.createCustomPreset(name: "P\(index)", symbol: .star, copying: .fallback))
        }
        XCTAssertFalse(controller.canAddCustomPreset)
        XCTAssertNil(controller.createCustomPreset(name: "Extra", symbol: .star, copying: .fallback))
        XCTAssertNil(controller.duplicatePreset(.builtIn(.silent)))
    }

    @MainActor
    func testCurveEditsPersistOnTheCustomPreset() throws {
        let controller = makeController()
        let id = try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .fallback))
        var edited = controller.curveProfile
        edited.points[1].fraction = 0.12
        controller.setCurveProfile(edited)

        let stored = try XCTUnwrap(CustomCoolingPresetStore.load().first)
        XCTAssertEqual(stored.curve.points[1].fraction, 0.12, accuracy: 0.0001)

        // Switching away keeps the edit; the built-in slot is untouched.
        controller.selectCoolingCurvePreset(.builtIn(.balanced))
        XCTAssertEqual(controller.curveProfile(for: id).points[1].fraction, 0.12, accuracy: 0.0001)
        XCTAssertTrue(controller.curveProfile.hasFactoryCurve(for: .balanced))
    }

    @MainActor
    func testRenameKeepsOldNameOnProblem() throws {
        let controller = makeController()
        let night = try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .fallback))
        controller.createCustomPreset(name: "Gaming", symbol: .gamecontroller, copying: .fallback)

        XCTAssertEqual(controller.renameCustomPreset(night, to: "gaming"), .duplicate("gaming"))
        XCTAssertEqual(controller.presetTitle(for: night), "Night")
        XCTAssertNil(controller.renameCustomPreset(night, to: "Night"))
        XCTAssertNil(controller.renameCustomPreset(night, to: "Late night"))
        XCTAssertEqual(controller.presetTitle(for: night), "Late night")
        XCTAssertNil(controller.renameCustomPreset(.builtIn(.silent), to: "Quiet"))
        XCTAssertEqual(controller.presetTitle(for: .builtIn(.silent)), FanCoolingPreset.silent.title)
    }

    @MainActor
    func testDuplicateUsesCopyNameAndSourceCurve() throws {
        let controller = makeController()
        let night = try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .builtIn(.silent)))
        let copy = try XCTUnwrap(controller.duplicatePreset(night))

        XCTAssertEqual(controller.presetTitle(for: copy), "Night" + fanBarText(" 副本", " Copy"))
        XCTAssertEqual(controller.presetSummary(for: copy).systemImage, CustomPresetSymbol.moon.systemImage)
        XCTAssertEqual(controller.curveProfile(for: copy).points.map(\.celsius),
                       controller.curveProfile(for: night).points.map(\.celsius))
    }

    @MainActor
    func testDeletingSelectedPresetSelectsPreviousAndClearsShortcut() throws {
        let controller = makeController()
        let first = try XCTUnwrap(controller.createCustomPreset(name: "One", symbol: .star, copying: .fallback))
        let second = try XCTUnwrap(controller.createCustomPreset(name: "Two", symbol: .star, copying: .fallback))
        CoolingPresetPreferences.save([.builtIn(.balanced), second])

        controller.deleteCustomPreset(second)

        XCTAssertEqual(controller.curveCoolingPreset, first)
        XCTAssertEqual(controller.customPresets.map(\.name), ["One"])
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: CoolingPresetPreferences.preferenceKey),
            "builtin:1"
        )

        controller.deleteCustomPreset(first)
        XCTAssertEqual(controller.curveCoolingPreset, .builtIn(.extreme))
        XCTAssertTrue(controller.customPresets.isEmpty)
        XCTAssertTrue(CustomCoolingPresetStore.load().isEmpty)
    }

    // MARK: - Rendering

    /// Renders a view offscreen so its body runs; returns the bitmap.
    @MainActor
    @discardableResult
    private func render(_ view: some View, width: CGFloat = SettingsChrome.contentWidth) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: width).background(Color(NSColor.windowBackgroundColor)))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(host.bounds.height, 0)
        return bitmap
    }

    /// Renders the preset section for 0–6 custom presets, including the
    /// rename field and the curve editor's custom-preset header. Set
    /// FANBAR_DESIGN_CAPTURE_PATH to also write the renders as PNGs.
    @MainActor
    func testPresetGridRendersForEveryCustomCount() throws {
        let capturePath = ProcessInfo.processInfo.environment["FANBAR_DESIGN_CAPTURE_PATH"]
        let controller = makeController()
        let names = ["Night edit", "Gaming", "Meetings", "Builds", "External display", "Summer"]
        let symbols: [CustomPresetSymbol] = [.moon, .gamecontroller, .headphones, .hammer, .desktopcomputer, .snow]
        CoolingPresetPreferences.save([.builtIn(.balanced)])
        for count in [0, 1, 2, 3, 4, 6] {
            while controller.customPresets.count < count {
                let index = controller.customPresets.count
                controller.createCustomPreset(name: names[index], symbol: symbols[index], copying: .builtIn(.silent))
            }
            if let first = controller.customPresets.first {
                controller.selectCoolingCurvePreset(.custom(first.id))
                CoolingPresetPreferences.save([.builtIn(.balanced), .custom(first.id)])
            }
            let content = VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
                CoolingPresetTiles(controller: controller)
                FanCurveEditorView(controller: controller)
            }
            .padding(SettingsChrome.horizontalPadding)
            let bitmap = try render(content)
            if let capturePath {
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: capturePath).appendingPathComponent("presets-\(count).png"))
            }
        }

        let renaming = try XCTUnwrap(controller.customPresets.first.map { CoolingPresetID.custom($0.id) })
        PresetRenameCoordinator.shared.renaming = renaming
        defer { PresetRenameCoordinator.shared.renaming = nil }
        try render(CoolingPresetTiles(controller: controller).padding(SettingsChrome.horizontalPadding))
    }

    @MainActor
    func testPresetFormAndActionMenusRender() throws {
        let controller = makeController()
        let custom = try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .fallback))
        try render(NewCustomPresetForm(controller: controller, isPresented: .constant(true)), width: 300)
        try render(VStack { PresetActionsMenu(controller: controller, preset: custom) })
        try render(VStack { PresetActionsMenu(controller: controller, preset: .builtIn(.silent)) })
        controller.selectCoolingCurvePreset(.builtIn(.silent))
        try render(FanCurveEditorView(controller: controller).padding(SettingsChrome.horizontalPadding))
    }

    @MainActor
    func testPresetActionsDuplicateAndStartRename() throws {
        let controller = makeController()
        defer { PresetRenameCoordinator.shared.renaming = nil }

        PresetActionsMenu(controller: controller, preset: .builtIn(.silent)).duplicate()
        let first = try XCTUnwrap(controller.customPresets.first.map { CoolingPresetID.custom($0.id) })
        PresetActionsMenu(controller: controller, preset: first).duplicate()
        XCTAssertEqual(controller.customPresets.count, 2)

        controller.selectCoolingCurvePreset(.builtIn(.silent))
        PresetActionsMenu(controller: controller, preset: first).startRename()
        XCTAssertEqual(PresetRenameCoordinator.shared.renaming, first)
        XCTAssertEqual(controller.curveCoolingPreset, first)
    }

    func testShortcutTogglingKeepsDisplayOrderAndLimit() {
        let custom = CoolingPresetID.custom(UUID())
        let order: [CoolingPresetID] = FanCoolingPreset.allCases.map { .builtIn($0) } + [custom]

        XCTAssertEqual(
            CoolingPresetPreferences.toggling(.builtIn(.silent), in: [custom], order: order),
            [.builtIn(.silent), custom]
        )
        XCTAssertNil(CoolingPresetPreferences.toggling(.builtIn(.extreme), in: [.builtIn(.silent), custom], order: order))
        XCTAssertEqual(
            CoolingPresetPreferences.toggling(custom, in: [.builtIn(.silent), custom], order: order),
            [.builtIn(.silent)]
        )
    }

    @MainActor
    func testIconChangeAndMissingPresetsAreIgnoredSafely() throws {
        let controller = makeController()
        let custom = try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .fallback))
        controller.setCustomPresetSymbol(custom, symbol: .flame)
        XCTAssertEqual(CustomCoolingPresetStore.load().first?.symbol, .flame)
        XCTAssertEqual(controller.presetSummary(for: custom).systemImage, CustomPresetSymbol.flame.systemImage)

        let missing = CoolingPresetID.custom(UUID())
        controller.setCustomPresetSymbol(missing, symbol: .star)
        controller.deleteCustomPreset(missing)
        controller.setCurveProfile(FanCoolingPreset.extreme.factoryCurve, for: missing)
        XCTAssertNil(controller.duplicatePreset(missing))
        XCTAssertEqual(controller.presetTitle(for: missing), FanCoolingPreset.balanced.title)
        XCTAssertEqual(controller.customPresets.count, 1)
        for symbol in CustomPresetSymbol.allCases {
            XCTAssertFalse(symbol.title.isEmpty)
            XCTAssertFalse(symbol.systemImage.isEmpty)
        }
        XCTAssertFalse(CustomPresetRules.NameProblem.empty.message.isEmpty)
        XCTAssertFalse(CustomPresetRules.NameProblem.tooLong.message.isEmpty)
        XCTAssertTrue(CustomPresetRules.NameProblem.duplicate("Night").message.contains("Night"))
    }

    @MainActor
    func testFactoryResetIgnoresCustomPresets() throws {
        let controller = makeController()
        try XCTUnwrap(controller.createCustomPreset(name: "Night", symbol: .moon, copying: .fallback))
        var edited = controller.curveProfile
        edited.points[0].fraction = 0.3
        controller.setCurveProfile(edited)

        controller.resetActiveCurvePresetToFactory()

        XCTAssertEqual(controller.curveProfile.points[0].fraction, 0.3, accuracy: 0.0001)
    }
}
