import FanBarShared
import SwiftUI

/// The fan instrument shared by the app and WidgetKit.
public struct FanRotorGraphic: View {
    public let currentRPM: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let tint: Color
    public let angle: Double
    public let airflowPhase: Double

    public init(
        currentRPM: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        tint: Color,
        angle: Double = 0,
        airflowPhase: Double = 0
    ) {
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.tint = tint
        self.angle = angle
        self.airflowPhase = airflowPhase
    }

    private var normalizedSpeed: Double {
        let span = max(maximumRPM - minimumRPM, 1)
        return min(max(Double(currentRPM - minimumRPM) / Double(span), 0), 1)
    }

    private var airflowIntensity: Double {
        guard maximumRPM > 0 else { return 0 }
        return min(max(Double(currentRPM) / Double(maximumRPM), 0), 1)
    }

    public var body: some View {
        ZStack {
            FanRotorAirflowGraphic(
                intensity: airflowIntensity,
                phase: airflowPhase
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan")
        .accessibilityValue("\(currentRPM) RPM")
    }
}

private struct FanRotorAirflowGraphic: View {
    let intensity: Double
    let phase: Double

    private let icyBlue = Color(red: 0.25, green: 0.68, blue: 0.98)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(0..<4, id: \.self) { lane in
                    arc(lane: lane, side: side, center: center, trailing: false)
                    arc(lane: lane, side: side, center: center, trailing: true)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func arc(
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

        return FanRotorArcShape(
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

private struct FanRotorArcShape: Shape {
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
