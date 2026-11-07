import AppKit
import FanBarShared
import XCTest
@testable import FanBar

final class MenuBarResourceTests: XCTestCase {
    private var savedLanguage: Any?
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
        defaults = try XCTUnwrap(UserDefaults(suiteName: "MenuBarResourceTests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
        }
        try super.tearDownWithError()
    }

    // MARK: Values

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

    func testMemoryLabelFollowsTheInterfaceLanguage() {
        UserDefaults.standard.set(FanBarLanguage.chinese.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(MenuBarResource.memory.label, "内存")
        UserDefaults.standard.set(FanBarLanguage.japanese.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(MenuBarResource.memory.label, "メモリ")
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(MenuBarResource.memory.label, "MEM")
    }

    // MARK: Preferences

    func testMissingSwitchIsOffAndMissingStyleIsIcon() {
        let preferences = MenuBarResourcePreferences(defaults: defaults)
        for resource in MenuBarResource.allCases {
            XCTAssertFalse(preferences.isEnabled(resource))
            XCTAssertEqual(preferences.style(resource), .icon)
        }
    }

    func testRetiredOrUnknownStyleReadsAsLabelEverywhere() {
        defaults.set("value", forKey: MenuBarResource.cpu.stylePreferenceKey)
        defaults.set("label", forKey: MenuBarResource.memory.stylePreferenceKey)
        defaults.set("icon", forKey: MenuBarResource.gpu.stylePreferenceKey)
        let preferences = MenuBarResourcePreferences(defaults: defaults)
        XCTAssertEqual(preferences.style(.cpu), .label)
        XCTAssertEqual(preferences.style(.memory), .label)
        XCTAssertEqual(preferences.style(.gpu), .icon)
        // Settings and the preview resolve the raw value the same way.
        XCTAssertEqual(MenuBarResourceStyle.resolve("value"), preferences.style(.cpu))
        XCTAssertEqual(MenuBarResourceStyle.resolve(nil), .icon)
    }

    func testSwitchesAreReadPerResource() {
        defaults.set(true, forKey: MenuBarResource.memory.preferenceKey)
        let preferences = MenuBarResourcePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnabled(.cpu))
        XCTAssertTrue(preferences.isEnabled(.memory))
        XCTAssertFalse(preferences.isEnabled(.gpu))
    }

    // MARK: Item content

    func testAccessibilityTitleNamesTheResourceOnce() {
        var usage = SystemUsage()
        usage.cpuFraction = 0.24
        let label = MenuBarResourceItemContent.make(.cpu, usage: usage, style: .label)
        let icon = MenuBarResourceItemContent.make(.cpu, usage: usage, style: .icon)
        XCTAssertEqual(label.title, "CPU 24%")
        XCTAssertEqual(label.accessibilityTitle, "CPU usage, 24%")
        XCTAssertEqual(icon.accessibilityTitle, "CPU usage, 24%")
        XCTAssertEqual(label.toolTip, "CPU usage")
    }

    func testWidthStaysFixedWhileTheValueChanges() {
        var low = SystemUsage()
        low.cpuFraction = 0.05
        var high = SystemUsage()
        high.cpuFraction = 0.99
        let first = MenuBarResourceItemContent.make(.cpu, usage: low, style: .label)
        let second = MenuBarResourceItemContent.make(.cpu, usage: high, style: .label)
        XCTAssertEqual(first.widestTitle, second.widestTitle)
        XCTAssertEqual(first.widestTitle, "CPU 100%")
        XCTAssertEqual(MenuBarResourceItemContent.make(.memory, usage: low, style: .label).widestTitle, "MEM 100%")
        XCTAssertNotEqual(first, second)
        // An unchanged reading compares equal, so nothing is written to the status button.
        XCTAssertEqual(MenuBarResourceItemContent.make(.cpu, usage: low, style: .label), first)
    }

    func testIconStyleShowsTheIconAndLabelStyleDoesNot() {
        let usage = SystemUsage()
        XCTAssertTrue(MenuBarResourceItemContent.make(.gpu, usage: usage, style: .icon).showsIcon)
        XCTAssertFalse(MenuBarResourceItemContent.make(.gpu, usage: usage, style: .label).showsIcon)
        XCTAssertEqual(MenuBarResourceItemContent.make(.gpu, usage: usage, style: .icon).widestTitle, "100%")
    }

    func testEachResourceHasItsOwnAutosaveName() {
        let names = Set(MenuBarResource.allCases.map(MenuBarResourceItems.autosaveName(for:)))
        XCTAssertEqual(names.count, MenuBarResource.allCases.count)
        XCTAssertEqual(MenuBarResourceItems.autosaveName(for: .cpu), "FanBarResource-cpu")
    }

    // MARK: Panel clicks

    func testClickOpensClosesOrMovesThePanel() {
        XCTAssertEqual(MenuBarPanelClick.action(isShown: false, fromAnchorItem: false), .open)
        XCTAssertEqual(MenuBarPanelClick.action(isShown: false, fromAnchorItem: true), .open)
        XCTAssertEqual(MenuBarPanelClick.action(isShown: true, fromAnchorItem: true), .close)
        XCTAssertEqual(MenuBarPanelClick.action(isShown: true, fromAnchorItem: false), .move)
    }

    @MainActor
    func testPopoverCanReopenUnderAnotherViewRightAfterClosing() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let first = NSView(frame: NSRect(x: 10, y: 10, width: 40, height: 20))
        let second = NSView(frame: NSRect(x: 200, y: 10, width: 40, height: 20))
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(second)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let popover = NSPopover()
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        popover.show(relativeTo: first.bounds, of: first, preferredEdge: .minY)
        XCTAssertTrue(popover.isShown)

        popover.closeImmediately()
        XCTAssertFalse(popover.isShown)
        XCTAssertTrue(popover.animates, "The popover keeps animating its ordinary opens and closes")

        popover.show(relativeTo: second.bounds, of: second, preferredEdge: .minY)
        XCTAssertTrue(popover.isShown)
        popover.closeImmediately()
    }
}
