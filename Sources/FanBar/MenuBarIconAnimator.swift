import AppKit

/// Keeps the status-item icon rotating while the physical fans are running.
///
/// The controller refreshes fan readings every two seconds and calls
/// `update(rpm:on:symbolName:)` with the average RPM; the animator spins at a
/// perceptual speed mapped from that reading and coasts to a stop once the
/// fans halt. A failed mode switch can still flash the icon via
/// `flashFailure()`.
///
/// The status item is pure AppKit (macOS 11 target), so SF Symbol effects are
/// unavailable; rotation is produced by pre-rendering quantized frames of the
/// template symbol. The timer only runs while an animation is active.
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
    private var symbolName = "fan"
    private var angle = 0.0
    private var angularVelocity = 0.0
    private var targetVelocity = 0.0
    private var lastTick = Date()
    private var blinkAccumulator = 0.0
    private var blinkRemaining = 0
    private var frameCache: [String: NSImage] = [:]

    private let frameQuantum = 15.0           // 24 cached frames per full turn
    private let blinkInterval = 0.12
    /// Degrees per second squared used when the fans stop, so the icon slows
    /// down like a rotor spinning down instead of freezing in place.
    private let spinDownDeceleration = 260.0
    /// Readings arrive every two seconds; smoothing avoids velocity jumps.
    private let velocitySmoothing = 4.0

    var isAnimating: Bool {
        phase != .idle
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Follows the live fan reading: spins while fans run, coasts to a stop
    /// when they halt. Called on every controller refresh.
    func update(rpm: Double, on button: NSButton, symbolName: String) {
        self.button = button
        if self.symbolName != symbolName {
            self.symbolName = symbolName
            frameCache.removeAll()
        }

        guard !reduceMotion else {
            if phase != .idle { stop() }
            return
        }

        let target = Self.perceptualVelocity(forRPM: rpm)
        switch phase {
        case .idle:
            guard target > 0 else { return }
            targetVelocity = target
            angularVelocity = target * 0.35 // gentle spin-up from rest
            phase = .spinning
            lastTick = Date()
            startTimerIfNeeded()
        case .spinning:
            targetVelocity = target
            if target <= 0 {
                phase = .coasting
            }
        case .coasting:
            if target > 0 {
                targetVelocity = target
                phase = .spinning
            }
        case .blinking:
            // The blink owns the image; the refresh after it (via onFinish)
            // resumes spinning if the fans are still running.
            break
        }
    }

    /// Flashes the icon to signal a failed switch, then restores the state
    /// that matches the live fan readings.
    func flashFailure() {
        guard !reduceMotion else { return }
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
        onFinish?()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
        // Clamp delayed frames so a busy run loop cannot cause a visible jump.
        let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.1)
        lastTick = now

        switch phase {
        case .idle:
            break
        case .spinning:
            if reduceMotion {
                stop()
                return
            }
            let smoothing = min(delta * velocitySmoothing, 1)
            angularVelocity += (targetVelocity - angularVelocity) * smoothing
            angle = (angle + angularVelocity * delta).truncatingRemainder(dividingBy: 360)
            button.image = frame(at: angle, alpha: 1)
        case .coasting:
            angularVelocity = max(angularVelocity - spinDownDeceleration * delta, 0)
            guard angularVelocity > 0 else {
                stop()
                return
            }
            angle = (angle + angularVelocity * delta).truncatingRemainder(dividingBy: 360)
            button.image = frame(at: angle, alpha: 1)
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
            button.image = frame(at: 0, alpha: dimmed ? 0.3 : 1)
        }
    }

    /// Real fan RPM is too fast to render directly without aliasing. Reuses
    /// the perceptual scale from FanRotorView so the menu bar and the panel
    /// rotor feel like the same machine.
    private static func perceptualVelocity(forRPM rpm: Double) -> Double {
        guard rpm > 1 else { return 0 }
        return min(max(rpm / 5_000, 0.18), 1.15) * 360
    }

    /// Returns the un-rotated, full-opacity icon image — intended for the
    /// static status bar item when the animator is idle. Shares the same
    /// rendering path as the animated frames so the sizes are pixel-identical.
    static func staticIcon(symbol: String) -> NSImage {
        render(symbol: symbol, degrees: 0, alpha: 1)
    }

    // MARK: - Render

    /// Returns a cached template frame for the quantized angle and alpha.
    private func frame(at angle: Double, alpha: CGFloat) -> NSImage {
        let quantized = (angle / frameQuantum).rounded() * frameQuantum
        let key = "\(symbolName)-\(Int(quantized))-\(Int(alpha * 100))"
        if let cached = frameCache[key] { return cached }
        let rendered = Self.render(symbol: symbolName, degrees: quantized, alpha: alpha)
        frameCache[key] = rendered
        return rendered
    }

    private static func render(symbol: String, degrees: Double, alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "FanBar")?
                .withSymbolConfiguration(config)
            else { return false }
            NSGraphicsContext.current?.imageInterpolation = .high
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: degrees)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        image.isTemplate = true
        return image
    }
}
