import FanBarShared
import FanBarUI
import SwiftUI

/// A compact instrument that turns live RPM into readable motion and a precise gauge.
struct FanRotorView: View {
    let fan: FanReading
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var airflowPhase = 0.0
    @State private var lastTick = Date()

    private let animationTimer = Timer.publish(
        every: 1.0 / 30.0,
        on: .main,
        in: .common
    ).autoconnect()

    /// Real fan RPM is too fast to render directly without aliasing. A fixed
    /// perceptual scale keeps different fans proportional to their actual RPM.
    private var visualRotationsPerSecond: Double {
        min(max(Double(fan.currentRPM) / 5_000, 0.18), 1.15)
    }

    private var airflowIntensity: Double {
        guard fan.maximumRPM > 0 else { return 0 }
        return min(max(Double(fan.currentRPM) / Double(fan.maximumRPM), 0), 1)
    }

    private var airflowRotationsPerSecond: Double {
        0.12 + airflowIntensity * 0.42
    }

    var body: some View {
        FanRotorGraphic(
            currentRPM: fan.currentRPM,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM,
            tint: tint,
            angle: angle,
            airflowPhase: airflowPhase
        )
        .onAppear { lastTick = Date() }
        .onReceive(animationTimer) { now in
            defer { lastTick = now }
            guard !reduceMotion else { return }

            // Clamp delayed frames so wake-up or menu reopening cannot cause a jump.
            let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.1)
            angle = (angle + visualRotationsPerSecond * 360 * delta)
                .truncatingRemainder(dividingBy: 360)
            airflowPhase = (airflowPhase + airflowRotationsPerSecond * delta)
                .truncatingRemainder(dividingBy: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fanBarFormat("风扇 %d", "Fan %d", fan.index + 1))
        .accessibilityValue(fanBarFormat("%d RPM", "%d RPM", fan.currentRPM))
    }
}
