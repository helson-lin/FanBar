import AppKit

/// Keeps the status-item icon rotating while the physical fans are running.
///
/// The controller calls `update(rpm:on:style:isManual:)` with the average RPM on
/// every change; the icon spins at a perceptual speed mapped from that reading
/// and coasts to a stop once the fans halt. A mode switch spins it briefly
/// even when the fans are stopped, and a failed switch flashes it via
/// `flashFailure()`.
///
/// On Apple silicon the spin is a Core Animation rotation (`MenuBarIconRotor`):
/// nearly free, but only the menu bar hosting the live item turns. Elsewhere,
/// and for the failure blink, frames are swapped on the button instead. Every
/// swap makes AppKit re-snapshot the status item for each display's menu bar,
/// roughly 0.85% of a core per frame per second on a Mac mini M4 with two
/// displays, so frames are quantized, only swapped on change, and capped at
/// `maximumFramesPerSecond`. Uncapped, a 3,000 RPM fan swapped about 7 frames
/// a second and cost 10% CPU.
///
/// The status item is pure AppKit (macOS 11 target), so SF Symbol effects are
/// unavailable; rotation is produced by pre-rendering quantized frames of the
/// template glyph. The timer only runs while an animation is active.
@MainActor
final class MenuBarIconAnimator {
    private enum Phase {
        case idle
        case spinning
        case coasting
        case blinking
    }

    /// Called whenever the animation fully stops so the owner can restore the
    /// authoritative icon for the current mode.
    var onFinish: (() -> Void)?

    private weak var button: NSButton?
    private var timer: Timer?
    private var phase: Phase = .idle
    private var style = MenuBarIconStyle.defaultStyle
    private var isManual = false
    private var angle = 0.0
    private var angularVelocity = 0.0
    private var targetVelocity = 0.0
    private var lastTick = Date()
    private var blinkAccumulator = 0.0
    private var blinkRemaining = 0
    private var frameCache: [String: NSImage] = [:]
    private var lastRPM = 0.0
    private var lastDelta = 0.0
    private var burstEndsAt = Date.distantPast

    /// How long a switch burst spins before coasting to rest when the fans
    /// themselves are stopped.
    static let burstDuration: TimeInterval = 3
    /// Lowest speed for a switch acknowledgement, so it reads as motion even
    /// when the fans are slow or stopped.
    private static let minimumBurstVelocity = 0.18 * 360

    /// 12 cached frames per full turn. Keep it under half the smallest blade
    /// spacing (60° for six blades), or a turn can read as running backwards.
    static let frameQuantum = 30.0
    /// The icon turns at most this many frames a second, 120° a second at 30°
    /// frames, reached near 1,670 RPM; faster fans look no faster and cost no more.
    static let maximumFramesPerSecond = 4.0
    private let blinkInterval = 0.12
    /// Degrees per second squared used when the fans stop, so the icon slows
    /// down like a rotor spinning down instead of freezing in place.
    private let spinDownDeceleration = 260.0
    /// Readings arrive every two seconds; smoothing avoids velocity jumps.
    private let velocitySmoothing = 4.0

    var isAnimating: Bool {
        phase != .idle
    }

    private let reduceMotionSetting: () -> Bool
    /// Nil where the rotor cannot hide the still icon (Intel) and in tests
    /// that count frame swaps.
    private let rotor: MenuBarIconRotor?

    private var reduceMotion: Bool {
        reduceMotionSetting()
    }

    /// `reduceMotion` reads the system setting; tests pass a fixed value so
    /// the host's accessibility settings cannot skip them.
    init(
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        rotor: MenuBarIconRotor? = MenuBarIconRotor.isSupported ? MenuBarIconRotor() : nil
    ) {
        reduceMotionSetting = reduceMotion
        self.rotor = rotor
    }

    /// Follows the live fan reading: spins while the fans run, coasts to a
    /// stop when they halt. Called on every controller change, usually with an
    /// unchanged reading.
    func update(rpm: Double, on button: NSButton, style: MenuBarIconStyle, isManual: Bool) {
        self.button = button
        if self.style != style || self.isManual != isManual {
            self.style = style
            self.isManual = isManual
            frameCache.removeAll()
        }
        lastRPM = rpm

        guard !reduceMotion else {
            if phase != .idle { stop() }
            return
        }

        // Running fans keep the icon spinning (and revive a coast) for as long
        // as they run. Stopped fans let `tick` coast once any burst has ended.
        let target = Self.perceptualVelocity(forRPM: rpm, capped: rotor == nil)
        guard target > 0, phase != .blinking else { return }
        targetVelocity = target
        if phase == .idle {
            angularVelocity = target * 0.35 // gentle spin-up from rest
            lastTick = Date()
        }
        phase = .spinning
        startTimerIfNeeded()
    }

    /// Spins briefly to acknowledge a mode switch, then coasts to rest.
    func playSwitchBurst() {
        guard !reduceMotion, button != nil else { return }
        startBurst(velocity: max(Self.perceptualVelocity(forRPM: lastRPM, capped: rotor == nil), Self.minimumBurstVelocity))
    }

    /// Starts or extends a burst. A running blink keeps the icon until it ends.
    private func startBurst(velocity: Double) {
        guard velocity > 0, phase != .blinking else { return }
        burstEndsAt = Date().addingTimeInterval(Self.burstDuration)
        targetVelocity = velocity
        if phase == .idle {
            angularVelocity = velocity * 0.35 // gentle spin-up from rest
            lastTick = Date()
        }
        phase = .spinning
        startTimerIfNeeded()
    }

    /// Flashes the icon to signal a failed switch, then restores the state
    /// that matches the live fan readings.
    func flashFailure() {
        guard !reduceMotion else { return }
        // The blink dims the icon on every menu bar, so it swaps frames.
        rotor?.detach()
        phase = .blinking
        blinkAccumulator = 0
        blinkRemaining = 4 // two dim/bright cycles
        lastTick = Date()
        startTimerIfNeeded()
    }

    /// Stops immediately and asks the owner to restore the authoritative icon.
    func stop() {
        guard phase != .idle else { return }
        phase = .idle
        timer?.invalidate()
        timer = nil
        rotor?.detach()
        onFinish?()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let button else {
            stop()
            return
        }
        let now = Date()
        // Clamp delayed frames so a busy run loop cannot cause a visible jump;
        // the bound sits above the 10 Hz tick so on-time frames are not slowed.
        let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.25)
        lastTick = now
        lastDelta = delta

        switch phase {
        case .idle:
            break
        case .spinning:
            if reduceMotion {
                stop()
                return
            }
            if now >= burstEndsAt, Self.perceptualVelocity(forRPM: lastRPM, capped: false) <= 0 {
                phase = .coasting
            }
            let smoothing = min(delta * velocitySmoothing, 1)
            angularVelocity += (targetVelocity - angularVelocity) * smoothing
            spin(on: button)
        case .coasting:
            angularVelocity = max(angularVelocity - spinDownDeceleration * delta, 0)
            guard angularVelocity > 0 else {
                stop()
                return
            }
            spin(on: button)
        case .blinking:
            blinkAccumulator += delta
            guard blinkAccumulator >= blinkInterval else { return }
            blinkAccumulator = 0
            blinkRemaining -= 1
            guard blinkRemaining > 0 else {
                stop()
                return
            }
            let dimmed = blinkRemaining % 2 == 1
            show(frame(at: 0, alpha: dimmed ? 0.3 : 1), on: button)
        }
    }

    /// Turns the icon at `angularVelocity`: the rotor when there is one, else
    /// the next quantized frame. The rotor keeps the button's still icon, which
    /// is what the other displays' menu bars show.
    private func spin(on button: NSButton) {
        if let rotor, let cell = button.cell as? NSButtonCell {
            let still = frame(at: 0, alpha: 1)
            show(still, on: button)
            rotor.show(still, in: cell.imageRect(forBounds: button.bounds), on: button)
            rotor.setTurnsPerSecond(angularVelocity / 360)
            return
        }
        angle = (angle + angularVelocity * lastDelta).truncatingRemainder(dividingBy: 360)
        show(frame(at: angle, alpha: 1), on: button)
    }

    /// Frames are quantized, so most ticks resolve to the image already shown.
    /// Every assignment makes AppKit re-snapshot the status item for each
    /// menu bar replicant, so only swap when the frame actually changes.
    private func show(_ image: NSImage, on button: NSButton) {
        guard button.image !== image else { return }
        button.image = image
    }

    /// Real fan RPM is too fast to render directly without aliasing, so the
    /// icon turns on a perceptual scale: degrees per second, clamped so idle
    /// fans still visibly turn and fast ones never strobe. Swapped frames are
    /// also `capped` at their frame rate; the rotor is not.
    static func perceptualVelocity(forRPM rpm: Double, capped: Bool) -> Double {
        guard rpm > 1 else { return 0 }
        let velocity = min(max(rpm / 5_000, 0.18), 1.15) * 360
        return capped ? min(velocity, frameQuantum * maximumFramesPerSecond) : velocity
    }

    /// Returns the un-rotated, full-opacity icon image — intended for the
    /// static status bar item when the animator is idle. Shares the same
    /// rendering path as the animated frames so the sizes are pixel-identical.
    static func staticIcon(style: MenuBarIconStyle, isManual: Bool) -> NSImage {
        style.image(isManual: isManual)
    }

    // MARK: - Render

    /// Returns a cached template frame for the quantized angle and alpha.
    private func frame(at angle: Double, alpha: CGFloat) -> NSImage {
        // 360° and 0° are the same picture; wrapping the index keeps a full
        // turn from costing one extra, invisible frame swap.
        let framesPerTurn = Int(360 / Self.frameQuantum)
        let index = Int((angle / Self.frameQuantum).rounded()) % framesPerTurn
        let quantized = Double(index) * Self.frameQuantum
        let key = "\(index)-\(Int(alpha * 100))"
        if let cached = frameCache[key] { return cached }
        let rendered = style.image(isManual: isManual, degrees: quantized, alpha: alpha)
        frameCache[key] = rendered
        return rendered
    }
}
