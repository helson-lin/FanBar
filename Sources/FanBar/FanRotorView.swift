import FanBarShared
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

    private var normalizedSpeed: Double {
        let span = max(fan.maximumRPM - fan.minimumRPM, 1)
        return min(max(Double(fan.currentRPM - fan.minimumRPM) / Double(span), 0), 1)
    }

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
        ZStack {
            FanAirflowView(
                phase: airflowPhase,
                intensity: airflowIntensity
            )
            .frame(width: 104, height: 104)

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: normalizedSpeed)
                    .stroke(
                        tint,
                        style: StrokeStyle(
                            lineWidth: 3.5 + airflowIntensity * 1.5,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(tint.opacity(0.08 + airflowIntensity * 0.08))
                    .padding(9)

                Image(systemName: "fanblades.fill")
                    .font(.system(size: 37, weight: .medium))
                    .foregroundColor(tint)
                    .rotationEffect(.degrees(angle))
                    .shadow(
                        color: tint.opacity(0.08 + airflowIntensity * 0.18),
                        radius: 2 + airflowIntensity * 3
                    )
            }
            .frame(width: 78, height: 78)
        }
        .frame(width: 104, height: 96)
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
