import AppKit
import XCTest
@testable import FanBar

/// Counts writes to the properties a status button re-snapshots on (issue #162).
private final class CountingButton: NSButton {
    var titleWrites = 0
    var fontWrites = 0
    var toolTipWrites = 0
    var imagePositionWrites = 0

    override var title: String {
        get { super.title }
        set { titleWrites += 1; super.title = newValue }
    }

    override var attributedTitle: NSAttributedString {
        get { super.attributedTitle }
        set { titleWrites += 1; super.attributedTitle = newValue }
    }

    override var font: NSFont? {
        get { super.font }
        set { fontWrites += 1; super.font = newValue }
    }

    override var toolTip: String? {
        get { super.toolTip }
        set { toolTipWrites += 1; super.toolTip = newValue }
    }

    override var imagePosition: NSControl.ImagePosition {
        get { super.imagePosition }
        set { imagePositionWrites += 1; super.imagePosition = newValue }
    }

    var totalWrites: Int {
        titleWrites + fontWrites + toolTipWrites + imagePositionWrites
    }
}

@MainActor
final class MenuBarButtonContentTests: XCTestCase {
    private func content(
        _ mode: MenuBarDisplayMode = .temperatureAndFanSpeed,
        text: String? = "54° · 1,800",
        toolTip: String = "CPU 54°"
    ) -> MenuBarButtonContent {
        .make(displayMode: mode, text: text, toolTip: toolTip, iconWidth: 16)
    }

    func testUnchangedReadingDoesNotTouchTheStatusButton() {
        let button = CountingButton()
        let writer = MenuBarButtonWriter()
        writer.apply(content(), to: button)
        let writesAfterFirstApply = button.totalWrites

        for _ in 0..<5 {
            XCTAssertFalse(writer.apply(content(), to: button))
        }

        XCTAssertEqual(button.totalWrites, writesAfterFirstApply)
    }

    func testNewReadingRewritesOnlyTheTitle() {
        let button = CountingButton()
        let writer = MenuBarButtonWriter()
        writer.apply(content(text: "54° · 1,800"), to: button)
        let before = (button.titleWrites, button.fontWrites, button.toolTipWrites, button.imagePositionWrites)

        writer.apply(content(text: "55° · 1,800"), to: button)

        XCTAssertEqual(button.title, "55° · 1,800")
        XCTAssertEqual(button.titleWrites, before.0 + 1)
        XCTAssertEqual(button.fontWrites, before.1)
        XCTAssertEqual(button.toolTipWrites, before.2)
        XCTAssertEqual(button.imagePositionWrites, before.3)
    }

    func testStackedReadoutKeepsPlaceholderTitleWhileValuesChange() {
        let button = CountingButton()
        let writer = MenuBarButtonWriter()
        writer.apply(content(.temperatureOverFanSpeed, text: "54°\n1,800"), to: button)
        let titleWrites = button.titleWrites

        let layoutChanged = writer.apply(content(.temperatureOverFanSpeed, text: "55°\n1,820"), to: button)

        XCTAssertFalse(layoutChanged)
        XCTAssertEqual(button.titleWrites, titleWrites)
        XCTAssertEqual(button.attributedTitle.string, "8,888")
        XCTAssertEqual(writer.shown?.accessibilityTitle, "55°, 1,820")
    }

    func testSwitchingModesRewritesTitleAndPosition() {
        let button = CountingButton()
        let writer = MenuBarButtonWriter()
        writer.apply(content(.iconOnly, text: nil), to: button)
        XCTAssertEqual(button.imagePosition, .imageOnly)

        XCTAssertTrue(writer.apply(content(.cpuTemperature, text: "54°"), to: button))

        XCTAssertEqual(button.title, "54°")
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertEqual(button.font, MenuBarButtonContent.digitFont)
    }

    func testWidthDependsOnTheModeNotTheCurrentReading() {
        XCTAssertEqual(
            content(text: "4° · 900").length,
            content(text: "100° · 8,888").length
        )
        XCTAssertEqual(content(.iconOnly, text: nil).length, NSStatusItem.squareLength)
        XCTAssertLessThan(
            content(.temperatureOverFanSpeed, text: "54°\n1,800").length,
            content(.temperatureAndFanSpeed).length
        )
    }

    func testOnlyTheStackedModeHasAnAccessibilityTitle() {
        XCTAssertNil(content(.cpuTemperature, text: "54°").accessibilityTitle)
        XCTAssertNil(content(.iconOnly, text: nil).accessibilityTitle)
        XCTAssertFalse(content(.iconOnly, text: nil).usesDigitFont)
    }
}
