import AppKit
import CoreImage.CIFilterBuiltins

/// Spins the status-item icon with Core Animation instead of swapping images.
///
/// Every image swap makes AppKit re-snapshot the status item for each other
/// display's menu bar, about 0.85% of a core per frame per second on a Mac mini
/// M4 with two displays. A layer animation runs in the render server and costs
/// next to nothing, but sublayers are not part of those snapshots: only the
/// menu bar that hosts the live item turns. The other menu bars keep the still
/// icon the button draws itself.
///
/// On the live menu bar the button's still icon would show under the rotor, so
/// `eraser` cuts it out with a backdrop filter. That filter has no effect on
/// Intel Macs, which therefore keep swapping capped frames instead. The same
/// approach is used by RunCat (runcat-dev/RunCatNeo).
@MainActor
final class MenuBarIconRotor {
    /// Whether this Mac can hide the still icon under the rotor.
    static var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private weak var button: NSButton?
    /// Removes the button's own still icon from the live menu bar.
    private let eraser = CALayer()
    /// Painted in the menu bar's text color and cut to the icon by `glyph`.
    private let tint = CALayer()
    /// Carries the template icon as a mask and holds the rotation.
    private let glyph = CALayer()
    private var appearanceObservation: NSKeyValueObservation?
    private var image: NSImage?
    private(set) var turnsPerSecond = 0.0

    private static let spinKey = "spin"

    init() {
        eraser.backgroundFilters = [Self.makeEraserFilter()]
        eraser.masksToBounds = true
        tint.mask = glyph
        for layer in [eraser, tint, glyph] {
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "backgroundColor": NSNull()]
        }
    }

    /// Turns whatever lies under the eraser fully transparent, leaving the
    /// menu bar. Every input is a vector: a CIImage input would make Core
    /// Animation encode it through an in-process Core Image Metal context,
    /// which loads about 180 MB of precompiled kernels into the app.
    static func makeEraserFilter() -> CIFilter {
        let filter = CIFilter.colorMatrix()
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.rVector = zero
        filter.gVector = zero
        filter.bVector = zero
        filter.aVector = zero
        filter.biasVector = zero
        return filter
    }

    var isAttached: Bool {
        tint.superlayer != nil
    }

    /// Places the rotor over `iconRect` (in the button's coordinates) and starts
    /// or keeps spinning at `turnsPerSecond`.
    func show(_ image: NSImage, in iconRect: CGRect, on button: NSButton) {
        attachIfNeeded(to: button)
        withoutAnimation {
            if eraser.frame != iconRect { eraser.frame = iconRect }
            if tint.frame != iconRect {
                tint.frame = iconRect
                glyph.frame = CGRect(origin: .zero, size: iconRect.size)
            }
            if self.image !== image {
                self.image = image
                glyph.contents = image
                let scale = button.window?.backingScaleFactor ?? 2
                glyph.contentsScale = scale
                tint.contentsScale = scale
            }
        }
    }

    /// Changes the speed without a jump: the current angle is kept and the
    /// animation continues from it. Zero holds the icon where it is.
    func setTurnsPerSecond(_ value: Double) {
        guard isAttached, abs(value - turnsPerSecond) > 0.005 else { return }
        turnsPerSecond = value
        withoutAnimation {
            if glyph.animation(forKey: Self.spinKey) == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                // The button layer is flipped, so this turns counterclockwise on
                // screen, the same way as the swapped frames.
                spin.toValue = -2 * Double.pi
                spin.duration = 1
                spin.repeatCount = .infinity
                spin.isRemovedOnCompletion = false
                glyph.speed = 0
                glyph.timeOffset = 0
                glyph.add(spin, forKey: Self.spinKey)
            }
            glyph.timeOffset = glyph.convertTime(CACurrentMediaTime(), from: nil)
            glyph.beginTime = CACurrentMediaTime()
            glyph.speed = Float(value)
        }
    }

    /// Removes the layers so the button's still icon shows again.
    func detach() {
        guard isAttached else { return }
        withoutAnimation {
            glyph.removeAnimation(forKey: Self.spinKey)
            eraser.removeFromSuperlayer()
            tint.removeFromSuperlayer()
        }
        appearanceObservation = nil
        turnsPerSecond = 0
        image = nil
    }

    private func attachIfNeeded(to button: NSButton) {
        guard !isAttached || self.button !== button else { return }
        self.button = button
        button.wantsLayer = true
        // Backdrop filters only render when the view asks for Core Image.
        button.layerUsesCoreImageFilters = true
        guard let host = button.layer else { return }
        withoutAnimation {
            host.addSublayer(eraser)
            host.addSublayer(tint)
        }
        updateTint(for: button)
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] button, _ in
            Task { @MainActor in self?.updateTint(for: button) }
        }
    }

    /// The live menu bar's text color, so the icon matches its neighbors in
    /// light and dark menu bars alike.
    private func updateTint(for button: NSButton) {
        var color = NSColor.labelColor.cgColor
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.cgColor
        }
        withoutAnimation { tint.backgroundColor = color }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
