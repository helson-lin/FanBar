import SwiftUI

/// A lightweight cold-air field whose motion and visibility follow live fan RPM.
struct FanAirflowView: View {
    let phase: Double
    let intensity: Double

    private let icyBlue = Color(red: 0.25, green: 0.68, blue: 0.98)

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shortestSide = min(size.width, size.height)

            for lane in 0..<4 {
                drawAirflowLane(
                    lane,
                    center: center,
                    shortestSide: shortestSide,
                    context: &context
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawAirflowLane(
        _ lane: Int,
        center: CGPoint,
        shortestSide: CGFloat,
        context: inout GraphicsContext
    ) {
        let laneOffset = Double(lane) * 0.23
        let progress = (phase + laneOffset).truncatingRemainder(dividingBy: 1)
        let direction = lane.isMultiple(of: 2) ? 1.0 : -1.0
        let start = (phase * direction + laneOffset) * .pi * 2
        let sweep = 0.42 + intensity * 0.46 + Double(lane % 2) * 0.1
        let radius = shortestSide * (0.405 + CGFloat(lane) * 0.025)
            + CGFloat(progress) * 2.5

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(start),
            endAngle: .radians(start + sweep * direction),
            clockwise: direction < 0
        )

        // Fade each wisp as it expands, retaining a readable static halo at low RPM.
        let fade = 1 - progress * 0.45
        let opacity = (0.08 + intensity * 0.24) * fade
        context.stroke(
            path,
            with: .color(icyBlue.opacity(opacity)),
            style: StrokeStyle(
                lineWidth: 1.0 + intensity * 1.1,
                lineCap: .round
            )
        )

        // A shorter trailing filament gives the airflow direction without particles.
        var trail = Path()
        let trailGap = 0.18 * direction
        trail.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(start - trailGap - 0.24 * direction),
            endAngle: .radians(start - trailGap),
            clockwise: direction < 0
        )
        context.stroke(
            trail,
            with: .color(icyBlue.opacity(opacity * 0.42)),
            style: StrokeStyle(
                lineWidth: 0.8 + intensity * 0.55,
                lineCap: .round
            )
        )
    }
}
