import AppKit
import XCTest
@testable import FanBar

final class MenuBarIconRenderingTests: XCTestCase {
    /// Issue #51: a circular SF Symbol must remain circular after rendering
    /// into the square menu-bar canvas, despite its typographic side bearings.
    @MainActor
    func testStaticIconPreservesNativeSymbolProportions() throws {
        for symbol in ["fan", "fan.fill"] {
            let native = try XCTUnwrap(NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)))
            let expected = try inkBounds(of: native, scale: 8)
            let actual = try inkBounds(of: MenuBarIconAnimator.staticIcon(symbol: symbol), scale: 8)
            XCTAssertEqual(actual.width / actual.height, expected.width / expected.height,
                           accuracy: 0.03, "\(symbol) was stretched")
        }
    }

    /// Animated frames must retain one size and leave transparent pixels
    /// around the rotor at every angle, on ordinary and Retina displays.
    @MainActor
    func testFullRotationHasStableSizeAndNoClippedEdges() throws {
        for symbol in ["fan", "fan.fill"] {
            for angle in stride(from: 0.0, to: 360.0, by: 15.0) {
                let image = MenuBarIconAnimator.render(symbol: symbol, degrees: angle, alpha: 1)
                XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
                XCTAssertTrue(image.isTemplate)
                for scale in [1, 2] {
                    let pixels = try bitmap(of: image, scale: scale)
                    let bounds = try inkBounds(of: image, scale: scale)
                    XCTAssertGreaterThan(bounds.width, 0)
                    for y in 0..<pixels.pixelsHigh {
                        for x in 0..<pixels.pixelsWide {
                            guard x == 0 || y == 0 || x == pixels.pixelsWide - 1 || y == pixels.pixelsHigh - 1 else { continue }
                            let alpha = try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent
                            XCTAssertLessThan(alpha, 0.05, "\(symbol) clipped at \(angle)°, \(scale)×")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testFailureFlashDimmingPreservesShape() throws {
        let full = MenuBarIconAnimator.render(symbol: "fan.fill", degrees: 0, alpha: 1)
        let dimmed = MenuBarIconAnimator.render(symbol: "fan.fill", degrees: 0, alpha: 0.3)
        let fullPixels = try bitmap(of: full, scale: 2)
        let dimmedPixels = try bitmap(of: dimmed, scale: 2)
        var fullAlpha = 0.0, dimmedAlpha = 0.0
        for y in 0..<fullPixels.pixelsHigh {
            for x in 0..<fullPixels.pixelsWide {
                fullAlpha += try XCTUnwrap(fullPixels.colorAt(x: x, y: y)).alphaComponent
                dimmedAlpha += try XCTUnwrap(dimmedPixels.colorAt(x: x, y: y)).alphaComponent
            }
        }
        XCTAssertGreaterThan(fullAlpha, 0)
        XCTAssertEqual(dimmedAlpha / fullAlpha, 0.3, accuracy: 0.02)
    }

    @MainActor
    private func bitmap(of image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width) * scale,
            pixelsHigh: Int(image.size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        return bitmap
    }

    @MainActor
    private func inkBounds(of image: NSImage, scale: Int) throws -> NSRect {
        let bitmap = try bitmap(of: image, scale: scale)
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh
        var maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX, "Icon must contain visible pixels")
        XCTAssertGreaterThanOrEqual(maxY, minY, "Icon must contain visible pixels")
        return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
