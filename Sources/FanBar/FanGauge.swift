import SwiftUI

/// One half of the shared dual-fan instrument panel.
struct FanGauge: View {
    let fan: FanReading
    let isManual: Bool

    private var tint: Color {
        isManual ? .orange : .accentColor
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text("风扇 \(fan.index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            FanRotorView(fan: fan, tint: tint)

            VStack(spacing: 2) {
                Text(fan.currentRPM.formatted())
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("RPM")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
            }

            Text("\(fan.minimumRPM.formatted())–\(fan.maximumRPM.formatted())")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityLabel("安全范围 \(fan.minimumRPM) 到 \(fan.maximumRPM) RPM")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
