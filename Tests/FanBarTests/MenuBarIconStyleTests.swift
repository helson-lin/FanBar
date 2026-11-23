import AppKit
import XCTest
@testable import FanBar

@MainActor
final class MenuBarIconStyleTests: XCTestCase {
    func testDefaultsToTheSystemFan() {
        XCTAssertEqual(MenuBarIconStyle.defaultStyle, .fan)
    }

    func testRetiredHandDrawnStylesResolveToTheSystemFan() {
        for raw in ["swirl", "ringed", "bold", "propeller", "guard", "blades", nil] {
            XCTAssertEqual(MenuBarIconStyle.stored(raw), .fan, raw ?? "nil")
        }
        XCTAssertEqual(MenuBarIconStyle.stored("outline"), .outline)
        XCTAssertEqual(MenuBarIconStyle.stored("none"), .none)
    }

    func testNoneHidesTheGlyph() {
        XCTAssertEqual(MenuBarIconStyle.none.rawValue, "none")
        XCTAssertFalse(MenuBarIconStyle.none.showsGlyph)
        XCTAssertTrue(MenuBarIconStyle.fan.showsGlyph)
        XCTAssertEqual(MenuBarIconStyle(rawValue: "none"), MenuBarIconStyle.none)
        for isManual in [false, true] {
            let image = MenuBarIconStyle.none.image(isManual: isManual)
            XCTAssertEqual(image.size, .zero)
            XCTAssertTrue(image.isTemplate)
        }
    }

    func testEveryStyleRendersATemplateOnTheSharedCanvas() {
        for style in MenuBarIconStyle.allCases where style.showsGlyph {
            let image = style.image(isManual: false)
            XCTAssertTrue(image.isTemplate, "\(style)")
            XCTAssertEqual(image.size, NSSize(width: MenuBarIconStyle.canvasSide, height: MenuBarIconStyle.canvasSide), "\(style)")
            XCTAssertGreaterThan(inkCoverage(of: image), 0.15, "\(style) should not be blank")
        }
    }

    /// Manual control must change the silhouette, not just a tint.
    func testManualModeAddsInkAtTheHub() {
        for style in MenuBarIconStyle.allCases where style.showsGlyph {
            let automatic = inkCoverage(of: style.image(isManual: false))
            let manual = inkCoverage(of: style.image(isManual: true))
            XCTAssertGreaterThan(manual, automatic, "\(style)")
        }
    }

    /// Optical alignment: every glyph must read as the same size and weight
    /// in the menu bar. Bounding boxes alone are not enough — a heavy closed
    /// ring reads larger than an open pinwheel of equal diameter — so styles
    /// are tuned against ink extent and ink coverage within these bands.
    func testStylesShareOpticalSizeAndWeight() {
        for style in MenuBarIconStyle.allCases where style.showsGlyph {
            let image = style.image(isManual: false)
            let diameter = inkDiameter(of: image)
            XCTAssertGreaterThanOrEqual(diameter, 15.5, "\(style) reads too small")
            XCTAssertLessThanOrEqual(diameter, 17.6, "\(style) reads too large")
        }
    }

    /// The Fan choice is the system symbol scaled into the menu-bar slot,
    /// not a hand-drawn stand-in.
    func testFanGlyphMatchesTheSystemSymbol() throws {
        let glyph = MenuBarIconStyle.fan.image(isManual: false)
        let configuration = NSImage.SymbolConfiguration(pointSize: MenuBarIconStyle.glyphSide, weight: .regular)
        let symbol = try XCTUnwrap(
            NSImage(systemSymbolName: FanBarSymbols.fanFill, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        )
        let reference = NSImage(size: glyph.size, flipped: false) { _ in
            let canvas = glyph.size.width
            let side = MenuBarIconStyle.glyphSide
            let origin = (canvas - side) / 2
            symbol.draw(in: NSRect(x: origin, y: origin, width: side, height: side))
            return true
        }
        // Cropped and scaled, so the pixels are not identical, but the glyph
        // must stay inside the system symbol's silhouette.
        XCTAssertGreaterThan(inkOverlap(glyph, inside: reference), 0.9)
    }

    /// Every glyph is a fan: rotating it by one blade pitch must reproduce
    /// it. Catches drawing-order bugs that leave a single blade damaged.
    func testEveryBladeIsDrawnIdentically() {
        let bladeCounts: [MenuBarIconStyle: Int] = [
            .fan: 4, .outline: 4
        ]
        for style in MenuBarIconStyle.allCases where style.showsGlyph {
            guard let blades = bladeCounts[style] else {
                return XCTFail("add \(style) to bladeCounts")
            }
            for isManual in [false, true] {
                let upright = style.image(isManual: isManual)
                let turned = style.image(isManual: isManual, degrees: 360 / Double(blades))
                // Resampling a system symbol by a right angle is not pixel-identical.
                let limit = 0.03
                XCTAssertLessThan(
                    pixelDifference(upright, turned), limit,
                    "\(style) manual=\(isManual) is not rotationally symmetric"
                )
            }
        }
    }

    /// Share of `glyph` ink that also lies on `container` ink.
    private func inkOverlap(_ glyph: NSImage, inside container: NSImage) -> Double {
        let pixels = 72
        guard let left = render(glyph, pixels: pixels), let right = render(container, pixels: pixels) else { return 0 }
        var ink = 0.0
        var shared = 0.0
        for y in 0..<pixels {
            for x in 0..<pixels {
                let alpha = Double(left.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                guard alpha > 0.3 else { continue }
                ink += 1
                if (right.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    shared += 1
                }
            }
        }
        return ink == 0 ? 0 : shared / ink
    }

    /// Mean absolute alpha difference across the canvas.
    private func pixelDifference(_ lhs: NSImage, _ rhs: NSImage) -> Double {
        let pixels = 72
        guard let left = render(lhs, pixels: pixels), let right = render(rhs, pixels: pixels) else { return 1 }
        var total = 0.0
        for y in 0..<pixels {
            for x in 0..<pixels {
                total += abs(Double(left.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                    - Double(right.colorAt(x: x, y: y)?.alphaComponent ?? 0))
            }
        }
        return total / Double(pixels * pixels)
    }

    /// The farthest inked pixel from the canvas centre, as a diameter in points.
    private func inkDiameter(of image: NSImage) -> Double {
        let pixels = 72
        guard let rep = render(image, pixels: pixels) else { return 0 }
        let center = Double(pixels) / 2
        var maxRadius = 0.0
        for y in 0..<pixels {
            for x in 0..<pixels where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                let dx = Double(x) + 0.5 - center
                let dy = Double(y) + 0.5 - center
                maxRadius = max(maxRadius, (dx * dx + dy * dy).squareRoot())
            }
        }
        return maxRadius * 2 * Double(image.size.width) / Double(pixels)
    }

    private func render(_ image: NSImage, pixels: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func inkCoverage(of image: NSImage) -> Double {
        let pixels = 72
        guard let rep = render(image, pixels: pixels) else { return 0 }
        var ink = 0.0
        for y in 0..<pixels {
            for x in 0..<pixels {
                ink += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        // Measured against the glyph area, not the padded canvas, so the
        // weight bands stay meaningful if the transparent border changes.
        let glyphFraction = Double(MenuBarIconStyle.glyphSide / MenuBarIconStyle.canvasSide)
        return ink / Double(pixels * pixels) / (glyphFraction * glyphFraction)
    }
}
