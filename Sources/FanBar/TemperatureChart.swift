import Charts
import SwiftUI

/// A three-minute rolling trace built from the CPU and GPU sensors available on this Mac.
struct TemperatureChart: View {
    let samples: [ThermalReading]

    private var latest: ThermalReading? { samples.last }

    private var plottedValues: [Double] {
        samples.flatMap { [$0.cpuCelsius, $0.gpuCelsius].compactMap { $0 } }
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = plottedValues.min(),
              let maximum = plottedValues.max() else {
            return 40...60
        }

        // Follow the visible samples closely while retaining enough span to avoid
        // visually exaggerating tiny sensor noise.
        let observedSpan = maximum - minimum
        let displaySpan = max(observedSpan * 1.3, 8)
        let midpoint = (minimum + maximum) / 2
        let rawLower = midpoint - displaySpan / 2
        let rawUpper = midpoint + displaySpan / 2
        let lower = max(0, floor(rawLower))
        let upper = min(120, ceil(rawUpper))
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("芯片温度")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                temperatureLegend(
                    title: "CPU",
                    value: latest?.cpuCelsius,
                    color: .orange
                )
                temperatureLegend(
                    title: "GPU",
                    value: latest?.gpuCelsius,
                    color: .accentColor
                )
            }

            if samples.isEmpty {
                ContentUnavailableView {
                    Label("正在读取温度", systemImage: "thermometer.medium")
                }
                .frame(height: 112)
            } else {
                Chart {
                    ForEach(samples, id: \.sampledAt) { sample in
                        if let cpu = sample.cpuCelsius {
                            LineMark(
                                x: .value("时间", sample.sampledAt),
                                y: .value("CPU", cpu)
                            )
                            .foregroundStyle(Color.orange)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        }

                        if let gpu = sample.gpuCelsius {
                            LineMark(
                                x: .value("时间", sample.sampledAt),
                                y: .value("GPU", gpu)
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 2,
                                    lineCap: .round,
                                    dash: [4, 3]
                                )
                            )
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisValueLabel(format: .dateTime.minute().second())
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.07))
                        AxisValueLabel()
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartPlotStyle { plot in
                    plot
                        .background(Color.primary.opacity(0.025))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 116)
                .accessibilityLabel("最近三分钟芯片温度曲线")
            }
        }
    }

    private func temperatureLegend(
        title: String,
        value: Double?,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.map { "\($0, specifier: "%.0f")°" } ?? "—")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption2)
    }
}
