import AppKit
import XCTest
@testable import FanBar

@MainActor
final class MenuBarIconRotorTests: XCTestCase {
    /// Regression (issue #162): a backdrop filter in the status item made
    /// WindowServer redraw the menu bar behind it on every frame and, on some
    /// Macs, paint magenta blocks over FanBar's and other apps' items.
    func testSpinningIconUsesNoBackdropOrCoreImageFilters() {
        let rotor = MenuBarIconRotor()
        let button = NSButton(title: "", target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 22)
        let image = MenuBarIconAnimator.staticIcon(style: .defaultStyle, isManual: false)

        rotor.show(image, in: CGRect(x: 4, y: 3, width: 16, height: 16), on: button)
        rotor.setTurnsPerSecond(0.5)

        XCTAssertTrue(rotor.isAttached)
        XCTAssertFalse(button.layerUsesCoreImageFilters)
        let layers = allLayers(under: button.layer)
        XCTAssertFalse(layers.isEmpty)
        for layer in layers {
            XCTAssertNil(layer.backgroundFilters, "\(layer) has a backdrop filter")
            XCTAssertNil(layer.filters, "\(layer) has a filter")
        }

        rotor.detach()
        XCTAssertFalse(rotor.isAttached)
    }

    private func allLayers(under root: CALayer?) -> [CALayer] {
        guard let root else { return [] }
        let children = (root.sublayers ?? []) + [root.mask].compactMap { $0 }
        return [root] + children.flatMap { allLayers(under: $0) }
    }
}
