import FanBarShared
import SwiftUI

/// One half of the shared dual-fan instrument panel.
struct FanGauge: View {
    let fan: FanReading

    private var tint: Color {
        FanCoolingPalette.tint(for: fan)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(fanBarFormat("风扇 %d", "Fan %d", fan.index + 1))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            FanRotorView(fan: fan, tint: tint)

            VStack(spacing: 2) {
                Text("\(fan.currentRPM)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                Text("RPM")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(.secondary)
            }

            Text("\(fan.minimumRPM)–\(fan.maximumRPM)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .accessibilityLabel(fanBarFormat(
                    "安全范围 %d 到 %d RPM",
                    "Safe range %d–%d RPM",
                    fan.minimumRPM,
                    fan.maximumRPM
                ))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
