import AppKit

/// Spins the status-item icon with Core Animation instead of swapping images.
///
/// Every image swap makes AppKit re-snapshot the status item for each other
/// display's menu bar, about 0.85% of a core per frame per second on a Mac mini
/// M4 with two displays. A layer animation runs in the render server and costs
/// next to nothing, but sublayers are not part of those snapshots: only the
/// menu bar that hosts the live item turns.
///
/// While the rotor spins, the button holds a transparent placeholder the size
/// of the icon (see `MenuBarIconAnimator`), so the live menu bar shows only the
/// rotor and the other menu bars show an empty slot until the spin stops.
///
/// An earlier version kept the still icon and cut it out of the live menu bar
/// with a Core Image backdrop filter. WindowServer re-rendered that backdrop
/// on every frame, and on some Macs drew magenta blocks across FanBar's and
/// neighboring apps' status items (issue #162), so the rotor uses no filters.
@MainActor
final class MenuBarIconRotor {
    /// Intel Macs keep swapping capped frames, as they did before the rotor
    /// stopped using a backdrop filter.
    static var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private weak var button: NSButton?
    /// Painted in the menu bar's text color and cut to the icon by `glyph`.
    private let tint = CALayer()
    /// Carries the template icon as a mask and holds the rotation.
    private let glyph = CALayer()
    private var appearanceObservation: NSKeyValueObservation?
    private var image: NSImage?
    private(set) var turnsPerSecond = 0.0

    private static let spinKey = "spin"

    init() {
        tint.mask = glyph
        for layer in [tint, glyph] {
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "backgroundColor": NSNull()]
        }
    }

    var isAttached: Bool {
        tint.superlayer != nil
    }

    /// Places the rotor over `iconRect` (in the button's coordinates) and starts
    /// or keeps spinning at `turnsPerSecond`.
    func show(_ image: NSImage, in iconRect: CGRect, on button: NSButton) {
        attachIfNeeded(to: button)
        withoutAnimation {
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

    /// Removes the layers; the owner puts the still icon back on the button.
    func detach() {
        guard isAttached else { return }
        withoutAnimation {
            glyph.removeAnimation(forKey: Self.spinKey)
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
        guard let host = button.layer else { return }
        withoutAnimation { host.addSublayer(tint) }
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
