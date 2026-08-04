import SwiftUI

/// A lightweight cold-air field whose motion and visibility follow live fan RPM.
/// It uses Shape paths instead of Canvas so the animation also works on macOS 11.
struct FanAirflowView: View {
    let phase: Double
    let intensity: Double

    private let icyBlue = Color(red: 0.25, green: 0.68, blue: 0.98)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                ForEach(0..<4, id: \.self) { lane in
                    airflowArc(
                        lane: lane,
                        side: side,
                        center: center,
                        trailing: false
                    )
                    airflowArc(
                        lane: lane,
                        side: side,
                        center: center,
                        trailing: true
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func airflowArc(
        lane: Int,
        side: CGFloat,
        center: CGPoint,
        trailing: Bool
    ) -> some View {
        let laneOffset = Double(lane) * 0.23
        let progress = (phase + laneOffset).truncatingRemainder(dividingBy: 1)
        let direction = lane.isMultiple(of: 2) ? 1.0 : -1.0
        let sweep = 0.42 + intensity * 0.46 + Double(lane % 2) * 0.1
        let radius = side * (0.405 + CGFloat(lane) * 0.025)
            + CGFloat(progress) * 2.5
        let start = phase * direction * .pi * 2 + laneOffset * .pi * 2
        let trailGap = 0.18 * direction
        let arcStart = trailing
            ? start - trailGap - 0.24 * direction
            : start
        let arcSweep = trailing ? 0.18 * direction : sweep * direction
        let fade = 1 - progress * 0.45
        let opacity = (trailing ? 0.42 : 1) * (0.08 + intensity * 0.24) * fade

        return AirflowArcShape(
            center: center,
            radius: radius,
            startAngle: arcStart,
            sweep: arcSweep
        )
        .stroke(
            icyBlue.opacity(opacity),
            style: StrokeStyle(
                lineWidth: (trailing ? 0.8 : 1.0) + intensity * (trailing ? 0.55 : 1.1),
                lineCap: .round
            )
        )
    }
}

private struct AirflowArcShape: Shape {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: Double
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(startAngle),
            endAngle: .radians(startAngle + sweep),
            clockwise: sweep < 0
        )
        return path
    }
}
