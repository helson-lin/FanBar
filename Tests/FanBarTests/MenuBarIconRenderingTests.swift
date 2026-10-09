import AppKit
import XCTest
@testable import FanBar

final class MenuBarIconRenderingTests: XCTestCase {
    /// Animated frames must keep one size and leave transparent pixels around
    /// the glyph at every angle, on ordinary and Retina displays (issue #51).
    @MainActor
    func testFullRotationHasStableSizeAndNoClippedEdges() throws {
        for style in MenuBarIconStyle.allCases {
            for isManual in [false, true] {
                for angle in stride(from: 0.0, to: 360.0, by: 15.0) {
                    let image = style.image(isManual: isManual, degrees: angle)
                    let side = MenuBarIconStyle.canvasSide
                    XCTAssertEqual(image.size, NSSize(width: side, height: side))
                    XCTAssertTrue(image.isTemplate)
                    for scale in [1, 2] {
                        let pixels = try bitmap(of: image, scale: scale)
                        let bounds = try inkBounds(of: image, scale: scale)
                        XCTAssertGreaterThan(bounds.width, 0)
                        for y in 0..<pixels.pixelsHigh {
                            for x in 0..<pixels.pixelsWide {
                                guard x == 0 || y == 0 || x == pixels.pixelsWide - 1 || y == pixels.pixelsHigh - 1 else { continue }
                                let alpha = try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent
                                XCTAssertLessThan(alpha, 0.05, "\(style) clipped at \(angle)°, \(scale)×")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The failure blink dims the whole glyph uniformly; overlapping blade
    /// and hub fills must not darken where they meet.
    @MainActor
    func testFailureFlashDimmingPreservesShape() throws {
        for style in MenuBarIconStyle.allCases {
            let fullPixels = try bitmap(of: style.image(isManual: true, alpha: 1), scale: 2)
            let dimmedPixels = try bitmap(of: style.image(isManual: true, alpha: 0.3), scale: 2)
            var fullAlpha = 0.0, dimmedAlpha = 0.0
            for y in 0..<fullPixels.pixelsHigh {
                for x in 0..<fullPixels.pixelsWide {
                    fullAlpha += try XCTUnwrap(fullPixels.colorAt(x: x, y: y)).alphaComponent
                    dimmedAlpha += try XCTUnwrap(dimmedPixels.colorAt(x: x, y: y)).alphaComponent
                }
            }
            XCTAssertGreaterThan(fullAlpha, 0, "\(style)")
            XCTAssertEqual(dimmedAlpha / fullAlpha, 0.3, accuracy: 0.02, "\(style)")
        }
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
