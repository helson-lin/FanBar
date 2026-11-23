import AppKit
import FanBarShared

/// User-selectable menu bar glyphs. Each one is a system fan symbol, drawn
/// as a template so it tints with the menu bar and can spin. Hand-drawn
/// stand-ins were retired; a saved choice of one of those falls back to Fan.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    /// System `fan.fill`. On macOS 12–13 this is `fanblades.fill`; on macOS 11, `wind`.
    case fan
    /// System `fan`, the unfilled form of the same symbol.
    case outline
    /// No glyph. The status item keeps its reading, so the menu bar can show
    /// temperature or fan speed without an icon (issue #173).
    case none

    static let preferenceKey = "fanbar.menuBarIconStyle"
    static let defaultStyle = MenuBarIconStyle.fan

    var id: String { rawValue }

    /// `none` is a choice, not a drawing. Callers skip the glyph and its spin.
    var showsGlyph: Bool {
        switch self {
        case .none: false
        default: true
        }
    }

    /// A saved hand-drawn style, or the retired Blades choice, resolves to Fan.
    static func stored(_ rawValue: String?) -> MenuBarIconStyle {
        switch rawValue {
        case outline.rawValue: return .outline
        case none.rawValue: return .none
        default: return .fan
        }
    }

    static var current: MenuBarIconStyle {
        stored(UserDefaults.standard.string(forKey: preferenceKey))
    }

    var title: String {
        switch self {
        case .fan: fanBarText("风扇", "Fan")
        case .outline: fanBarText("线条", "Outline")
        case .none: fanBarText("无", "None")
        }
    }

    /// Designs are drawn on a 17pt grid scaled to an 18pt glyph, so the ink
    /// reaches ~17pt and matches the visual weight of neighbouring extras.
    static let glyphSide: CGFloat = 18
    /// The canvas adds a 1pt transparent border around the glyph: without it
    /// the outermost ink and its antialiasing clip at the image edge on
    /// non-Retina displays while the icon rotates (issue #51).
    static let canvasSide: CGFloat = 20
    private static let designGrid: CGFloat = 17

    /// Renders a template frame. Manual control is marked by shape — a solid
    /// hub — never by tint alone, since menu bar extras are monochrome.
    func image(isManual: Bool, degrees: Double = 0, alpha: CGFloat = 1) -> NSImage {
        guard showsGlyph else {
            let image = NSImage(size: .zero)
            image.isTemplate = true
            return image
        }
        let side = Self.canvasSide
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            // Draw opaque, then apply alpha once, so overlapping blade and hub
            // fills cannot darken where they meet during the failure blink.
            context.cgContext.setAlpha(alpha)
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: degrees)
            transform.concat()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            draw(isManual: isManual, unit: Self.glyphSide / Self.designGrid)
            context.cgContext.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "FanBar"
        return image
    }

    /// Draws the system symbol around the origin. `unit` only sizes the hub
    /// dot that marks manual control.
    private func draw(isManual: Bool, unit u: CGFloat) {
        guard let symbol = ink else { return }
        let side = Self.symbolSide
        symbol.draw(in: NSRect(x: -side / 2, y: -side / 2, width: side, height: side))
        if isManual {
            Self.circle(radius: 1.15 * u).fill()
        }
    }

    /// Square the cropped symbol is drawn into. Large enough to match the
    /// other menu-bar glyphs, small enough that a 45° spin stays inside the canvas.
    private static let symbolSide: CGFloat = 15.5

    private var ink: NSImage? {
        switch self {
        case .fan: Self.fanInk
        case .outline: Self.outlineInk
        case .none: nil
        }
    }

    /// The symbol with alignment padding removed, so rotation is around the
    /// blades rather than the image box.
    private static let fanInk = croppedSymbol(named: FanBarSymbols.fanFill)
    private static let outlineInk = croppedSymbol(named: FanBarSymbols.fan)

    private static func croppedSymbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else { return nil }
        let pixels = 256
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return symbol }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.set()
        let layout = symbol.size
        let origin = NSPoint(x: (CGFloat(pixels) - layout.width) / 2, y: (CGFloat(pixels) - layout.height) / 2)
        symbol.draw(in: NSRect(origin: origin, size: layout))
        NSGraphicsContext.restoreGraphicsState()
        var minX = pixels
        var minY = pixels
        var maxX = -1
        var maxY = -1
        for y in 0..<pixels {
            for x in 0..<pixels where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return symbol }
        let crop = NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cg = rep.cgImage?.cropping(to: crop) else { return symbol }
        let image = NSImage(cgImage: cg, size: NSSize(width: crop.width, height: crop.height))
        image.isTemplate = true
        return image
    }

    private static func circle(radius: CGFloat, at center: NSPoint = .zero) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
