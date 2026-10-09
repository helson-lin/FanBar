import AppKit
import FanBarShared

/// User-selectable menu bar glyphs. All are drawn as vector template images
/// at the same 18pt glyph size, so they carry the weight of neighbouring extras,
/// follow menu bar tinting, and rotate without clipping.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    /// Five crescent blades around an open hub, echoing the app icon.
    case swirl
    /// Three blades inside a fixed ring, read like a gauge.
    case ringed
    /// Four broad blades on a solid hub, the most compact silhouette.
    case bold
    /// Four rounded, crescent-cut lobes, like a desk-fan propeller.
    case propeller
    /// Six short blades inside a heavy guard ring.
    case guarded = "guard"
    /// Line art: four outlined petals inside a thin ring.
    case outline

    static let preferenceKey = "fanbar.menuBarIconStyle"
    static let defaultStyle = MenuBarIconStyle.swirl

    var id: String { rawValue }

    static var current: MenuBarIconStyle {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(MenuBarIconStyle.init) ?? defaultStyle
    }

    var title: String {
        switch self {
        case .swirl: fanBarText("漩涡", "Swirl")
        case .ringed: fanBarText("环形", "Ringed")
        case .bold: fanBarText("粗体", "Bold")
        case .propeller: fanBarText("螺旋桨", "Propeller")
        case .guarded: fanBarText("护罩", "Guard")
        case .outline: fanBarText("线条", "Outline")
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

    /// Draws around the origin; `unit` scales the 17pt design grid.
    private func draw(isManual: Bool, unit u: CGFloat) {
        switch self {
        case .swirl:
            // Wide, long blades: thin crescents left the glyph reading light
            // and small beside other extras even at full canvas size.
            for index in 0..<5 {
                Self.blade(start: 72 * CGFloat(index), innerRadius: 2.1 * u, outerRadius: 8.4 * u, sweep: 125, width: 84).fill()
            }
            if isManual {
                Self.circle(radius: 2.0 * u).fill()
            }
        case .ringed:
            // Blades reach close to the ring so the inside does not read as
            // empty space, which made this style look smaller than its size.
            let ring = Self.circle(radius: 7.3 * u)
            ring.lineWidth = 1.5 * u
            ring.stroke()
            for index in 0..<3 {
                Self.blade(start: 120 * CGFloat(index), innerRadius: 1.6 * u, outerRadius: 6.1 * u, sweep: 100, width: 85).fill()
            }
            Self.hub(radius: 2.3 * u, holeRadius: isManual ? 0 : 1.1 * u)
        case .bold:
            for index in 0..<4 {
                Self.blade(start: 90 * CGFloat(index), innerRadius: 1.8 * u, outerRadius: 8.2 * u, sweep: 90, width: 95).fill()
            }
            Self.hub(radius: 2.9 * u, holeRadius: isManual ? 0 : 1.4 * u)
        case .propeller:
            // Each lobe is a disc with a bite taken from its trailing side,
            // which turns four circles into a pinwheel. Every lobe gets its
            // own layer: the last bite overlaps the first lobe, and erasing on
            // the shared canvas left that one blade visibly cut away.
            Self.circle(radius: 2.2 * u).fill()
            for index in 0..<4 {
                let angle = 90 * CGFloat(index)
                Self.inIsolatedLayer {
                    Self.circle(radius: 3.4 * u, at: Self.polar(radius: 4.8 * u, degrees: angle)).fill()
                    Self.erase(Self.circle(radius: 3.8 * u, at: Self.polar(radius: 6.1 * u, degrees: angle + 55)))
                }
            }
            if !isManual {
                Self.erase(Self.circle(radius: 1.2 * u))
            }
        case .guarded:
            // A heavy ring reads larger than a thin one, so its outer edge
            // matches the ringed style's rather than the canvas edge.
            let guardRing = Self.circle(radius: 7.1 * u)
            guardRing.lineWidth = 1.9 * u
            guardRing.stroke()
            for index in 0..<6 {
                Self.blade(start: 60 * CGFloat(index), innerRadius: 2.0 * u, outerRadius: 5.4 * u, sweep: 55, width: 42).fill()
            }
            Self.hub(radius: 2.1 * u, holeRadius: isManual ? 0 : 1.0 * u)
        case .outline:
            // Line weights are set for 18pt, not scaled from a large drawing,
            // so the strokes stay legible beside system symbols.
            let ring = Self.circle(radius: 7.6 * u)
            ring.lineWidth = 1.2 * u
            ring.stroke()
            for index in 0..<4 {
                let petal = Self.petal(degrees: 90 * CGFloat(index) + 15, innerRadius: 1.7 * u, outerRadius: 6.3 * u, width: 1.7 * u)
                petal.lineWidth = 1.15 * u
                petal.lineJoinStyle = .round
                petal.stroke()
            }
            if isManual {
                Self.circle(radius: 1.6 * u).fill()
            }
        }
    }

    /// A kidney-shaped petal pointing along `degrees` and curling
    /// counter-clockwise, sized so four of them never touch when outlined.
    private static func petal(degrees: CGFloat, innerRadius: CGFloat, outerRadius: CGFloat, width: CGFloat) -> NSBezierPath {
        let length = outerRadius - innerRadius
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: innerRadius + x * length, y: y * width)
        }
        let path = NSBezierPath()
        path.move(to: point(0, -0.25))
        path.curve(to: point(1.0, 0.25), controlPoint1: point(0.30, -1.15), controlPoint2: point(1.02, -1.0))
        path.curve(to: point(0.62, 1.15), controlPoint1: point(0.98, 0.95), controlPoint2: point(0.85, 1.2))
        path.curve(to: point(0, 0.25), controlPoint1: point(0.38, 1.1), controlPoint2: point(0.12, 0.75))
        path.curve(to: point(0, -0.25), controlPoint1: point(-0.06, 0.08), controlPoint2: point(-0.06, -0.08))
        path.close()
        let rotation = NSAffineTransform()
        rotation.rotate(byDegrees: degrees)
        path.transform(using: rotation as AffineTransform)
        return path
    }

    private static func polar(radius: CGFloat, degrees: CGFloat) -> NSPoint {
        let radians = degrees * .pi / 180
        return NSPoint(x: radius * cos(radians), y: radius * sin(radians))
    }

    /// Composites `draw` as one unit, so an `erase` inside it cannot reach
    /// anything drawn earlier on the canvas.
    private static func inIsolatedLayer(_ draw: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return draw() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        context.endTransparencyLayer()
    }

    /// Clears a shape from what is already drawn. Safe because every frame
    /// is rendered inside its own transparency layer.
    private static func erase(_ path: NSBezierPath) {
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        path.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// A lens between two spirals that share both endpoints: the leading edge
    /// sweeps from hub to tip, the trailing edge lags by `width·sin(πt)`, so
    /// the blade is fattest mid-span and tapers cleanly at both ends.
    private static func blade(
        start: CGFloat,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        sweep: CGFloat,
        width: CGFloat
    ) -> NSBezierPath {
        let steps = 48
        let span = outerRadius - innerRadius
        func point(radius: CGFloat, degrees: CGFloat) -> NSPoint {
            let radians = degrees * .pi / 180
            return NSPoint(x: radius * cos(radians), y: radius * sin(radians))
        }

        let path = NSBezierPath()
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let leading = point(radius: innerRadius + span * t, degrees: start + sweep * t)
            step == 0 ? path.move(to: leading) : path.line(to: leading)
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(step) / CGFloat(steps)
            let bulge = sin(.pi * t)
            path.line(to: point(
                radius: innerRadius + span * t - span * 0.18 * bulge,
                degrees: start + sweep * t - width * bulge
            ))
        }
        path.close()
        return path
    }

    private static func circle(radius: CGFloat, at center: NSPoint = .zero) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// A solid hub, optionally punched through so automatic mode reads open.
    private static func hub(radius: CGFloat, holeRadius: CGFloat) {
        let path = circle(radius: radius)
        if holeRadius > 0 {
            path.append(circle(radius: holeRadius))
            path.windingRule = .evenOdd
        }
        path.fill()
    }
}
