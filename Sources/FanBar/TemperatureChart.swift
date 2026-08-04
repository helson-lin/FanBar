import FanBarShared
import SwiftUI

/// A ten-minute rolling trace built from the CPU and GPU sensors available on this Mac.
/// The plot is drawn with SwiftUI paths so it works on macOS 11 without Charts.framework.
struct TemperatureChart: View {
    static let historyDuration: TimeInterval = 10 * 60

    let samples: [ThermalReading]

    private var latest: ThermalReading? { samples.last }

    /// Keeps the x-axis stable at ten minutes even while the initial history fills in.
    private var timeRange: ClosedRange<Date> {
        let end = latest?.sampledAt ?? Date()
        return end.addingTimeInterval(-Self.historyDuration)...end
    }

    private var plottedValues: [Double] {
        samples.flatMap { [$0.cpuCelsius, $0.gpuCelsius].compactMap { $0 } }
    }

    private let smoothingRadius = 3

    /// Applies a short low-pass window only to the rendered trace. The raw
    /// readings remain the source of the legend and control logic.
    private var chartSamples: [ThermalReading] {
        guard samples.count > smoothingRadius * 2 else { return samples }

        return samples.indices.map { index in
            let sample = samples[index]
            return ThermalReading(
                sampledAt: sample.sampledAt,
                cpuCelsius: smoothedValue(at: index, keyPath: \.cpuCelsius),
                gpuCelsius: smoothedValue(at: index, keyPath: \.gpuCelsius)
            )
        }
    }

    private func smoothedValue(
        at index: Int,
        keyPath: KeyPath<ThermalReading, Double?>
    ) -> Double? {
        let lowerBound = max(0, index - smoothingRadius)
        let upperBound = min(samples.count - 1, index + smoothingRadius)
        let values = (lowerBound...upperBound).compactMap {
            samples[$0][keyPath: keyPath]
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = plottedValues.min(),
              let maximum = plottedValues.max() else {
            return 40...60
        }

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
                Text(fanBarText("芯片温度", "Chip temperature"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                temperatureLegend(title: "CPU", value: latest?.cpuCelsius, color: .orange)
                temperatureLegend(title: "GPU", value: latest?.gpuCelsius, color: .accentColor)
            }

            if samples.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                    Text(fanBarText("正在读取温度", "Reading temperature"))
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
            } else {
                TemperaturePlot(
                    samples: chartSamples,
                    yDomain: yDomain,
                    timeRange: timeRange
                )
                .frame(height: 116)
                .accessibilityLabel(fanBarText("最近十分钟芯片温度曲线", "Chip temperature over the last ten minutes"))
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
                .foregroundColor(.secondary)
            Text(value.map { "\($0, specifier: "%.0f")°" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .font(.system(size: 11))
    }
}

private struct TemperaturePlot: View {
    let samples: [ThermalReading]
    let yDomain: ClosedRange<Double>
    let timeRange: ClosedRange<Date>

    private let leftInset: CGFloat = 29
    private let rightInset: CGFloat = 6
    private let topInset: CGFloat = 5
    private let bottomInset: CGFloat = 21

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter
    }()

    private var yTicks: [Double] {
        let midpoint = (yDomain.lowerBound + yDomain.upperBound) / 2
        return [yDomain.upperBound, midpoint, yDomain.lowerBound]
    }

    var body: some View {
        GeometryReader { proxy in
            let plotRect = CGRect(
                x: leftInset,
                y: topInset,
                width: max(1, proxy.size.width - leftInset - rightInset),
                height: max(1, proxy.size.height - topInset - bottomInset)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.025))

                ForEach(yTicks, id: \.self) { tick in
                    let y = yPosition(tick, in: plotRect)
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX, y: y))
                        path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                    }
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)

                    Text("\(Int(tick.rounded()))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: leftInset - 5, alignment: .leading)
                        .position(x: (leftInset - 5) / 2, y: y)
                }

                curvePath(
                    values: samples.map(\.cpuCelsius),
                    in: plotRect
                )
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )

                curvePath(
                    values: samples.map(\.gpuCelsius),
                    in: plotRect
                )
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )

                xAxisLabels(in: plotRect, width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func xAxisLabels(in plotRect: CGRect, width: CGFloat) -> some View {
        let midpoint = timeRange.lowerBound.addingTimeInterval(
            timeRange.upperBound.timeIntervalSince(timeRange.lowerBound) / 2
        )
        let dates = [
            timeRange.lowerBound,
            midpoint,
            timeRange.upperBound
        ]

        return HStack {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                Text(Self.timeFormatter.string(from: date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == dates.count - 1 ? .trailing : .center))
            }
        }
        .padding(.leading, plotRect.minX)
        .padding(.trailing, max(0, width - plotRect.maxX))
        .frame(width: width, height: 16)
        .position(x: width / 2, y: plotRect.maxY + 13)
    }

    private func yPosition(_ value: Double, in rect: CGRect) -> CGFloat {
        let span = max(yDomain.upperBound - yDomain.lowerBound, 1)
        let fraction = (value - yDomain.lowerBound) / span
        return rect.maxY - CGFloat(fraction) * rect.height
    }

    private func curvePath(values: [Double?], in rect: CGRect) -> Path {
        var path = Path()
        var segment: [CGPoint] = []

        func flushSegment() {
            guard !segment.isEmpty else { return }
            appendSmoothSegment(segment, to: &path)
            segment.removeAll(keepingCapacity: true)
        }

        let firstDate = timeRange.lowerBound
        let timeSpan = max(timeRange.upperBound.timeIntervalSince(firstDate), 1)

        for (index, value) in values.enumerated() {
            guard let value else {
                flushSegment()
                continue
            }
            let date = samples[index].sampledAt
            let position = min(1, max(0, date.timeIntervalSince(firstDate) / timeSpan))
            let x = rect.minX + CGFloat(position) * rect.width
            segment.append(CGPoint(x: x, y: yPosition(value, in: rect)))
        }
        flushSegment()
        return path
    }

    private func appendSmoothSegment(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        guard points.count > 1 else {
            path.move(to: first)
            path.addLine(to: first)
            return
        }

        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }
}
