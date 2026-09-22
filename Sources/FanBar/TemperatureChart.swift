import FanBarShared
import SwiftUI

/// Formats the ten-minute chart's x-axis as wall-clock hour:minute:second.
/// `mm:ss` drops the hour, so a window ending at 17:09:52 would read
/// `59:52  04:52  09:52` when it crosses an hour boundary.
enum TemperatureChartTimeAxis {
    static let historyDuration: TimeInterval = 10 * 60

    /// Samples arrive every two seconds. Anything beyond this is a real break in
    /// the trace (sleep, lock screen, app restart) and must not be bridged.
    static let maximumSampleGap: TimeInterval = 15

    /// Splits sample dates into runs of consecutive indices that are close
    /// enough in time to be drawn and smoothed as one continuous curve.
    static func segments(for dates: [Date]) -> [ClosedRange<Int>] {
        guard !dates.isEmpty else { return [] }

        var result: [ClosedRange<Int>] = []
        var start = dates.startIndex

        for index in dates.indices.dropFirst() {
            if dates[index].timeIntervalSince(dates[index - 1]) > maximumSampleGap {
                result.append(start...(index - 1))
                start = index
            }
        }
        result.append(start...(dates.endIndex - 1))
        return result
    }

    /// The x-axis is always the ten minutes ending at the newest sample (or now
    /// while no sample exists). Keeping the full span makes the axis predictable
    /// and preserves the "last ten minutes" contract across app launches.
    static func displayRange(lastSample: Date?, now: Date = Date()) -> ClosedRange<Date> {
        let end = lastSample ?? now
        return end.addingTimeInterval(-historyDuration)...end
    }

    static func tickDates(in timeRange: ClosedRange<Date>) -> [Date] {
        let start = timeRange.lowerBound
        let end = timeRange.upperBound
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return [start, midpoint, end]
    }

    static func labels(
        in timeRange: ClosedRange<Date>,
        timeZone: TimeZone = .current
    ) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return tickDates(in: timeRange).map { formatter.string(from: $0) }
    }
}

enum TemperatureHistoryStore {
    static let preferenceKey = "fanbar.temperatureHistory"

    static func load(
        from defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [ThermalReading] {
        guard let data = defaults.data(forKey: preferenceKey),
              let decoded = try? JSONDecoder().decode([ThermalReading].self, from: data) else {
            return []
        }
        let cutoff = now.addingTimeInterval(-TemperatureChartTimeAxis.historyDuration)
        return decoded.filter { $0.sampledAt >= cutoff }
    }

    static func save(_ samples: [ThermalReading], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: preferenceKey)
    }
}

/// A ten-minute rolling trace built from the CPU, GPU, SSD, and battery sensors available on this Mac.
/// The plot is drawn with SwiftUI paths so it works on macOS 11 without Charts.framework.
struct TemperatureChart: View {
    static let historyDuration = TemperatureChartTimeAxis.historyDuration

    let samples: [ThermalReading]

    private var latest: ThermalReading? { samples.last }

    private var visibleSeries: [TemperatureSeries] {
        TemperatureSeries.allCases.filter { series in
            samples.contains { $0[keyPath: series.keyPath] != nil }
        }
    }

    private var timeRange: ClosedRange<Date> {
        TemperatureChartTimeAxis.displayRange(
            lastSample: latest?.sampledAt
        )
    }

    private var plottedValues: [Double] {
        samples.flatMap { sample in
            TemperatureSeries.allCases.compactMap { sample[keyPath: $0.keyPath] }
        }
    }

    private let smoothingRadius = 3

    private var sampleSegments: [ClosedRange<Int>] {
        TemperatureChartTimeAxis.segments(for: samples.map(\.sampledAt))
    }

    /// Applies a short low-pass window only to the rendered trace. The raw
    /// readings remain the source of the legend and control logic. The window
    /// never reaches across a break, so a resumed trace cannot drag the
    /// pre-break readings toward it.
    private var chartSamples: [ThermalReading] {
        guard samples.count > smoothingRadius * 2 else { return samples }

        return sampleSegments.flatMap { segment in
            segment.map { index in
                let sample = samples[index]
                return ThermalReading(
                    sampledAt: sample.sampledAt,
                    cpuCelsius: smoothedValue(at: index, within: segment, keyPath: \.cpuCelsius),
                    gpuCelsius: smoothedValue(at: index, within: segment, keyPath: \.gpuCelsius),
                    ssdCelsius: smoothedValue(at: index, within: segment, keyPath: \.ssdCelsius),
                    batteryCelsius: smoothedValue(at: index, within: segment, keyPath: \.batteryCelsius)
                )
            }
        }
    }

    private func smoothedValue(
        at index: Int,
        within segment: ClosedRange<Int>,
        keyPath: KeyPath<ThermalReading, Double?>
    ) -> Double? {
        let lowerBound = max(segment.lowerBound, index - smoothingRadius)
        let upperBound = min(segment.upperBound, index + smoothingRadius)
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
                Text(fanBarText("温度曲线", "Temperature trends"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                ForEach(visibleSeries) { series in
                    temperatureLegend(series)
                }
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
                    series: visibleSeries,
                    yDomain: yDomain,
                    timeRange: timeRange
                )
                .frame(height: 116)
                .accessibilityLabel(fanBarText("最近十分钟温度曲线", "Temperature trends over the last ten minutes"))
            }
        }
    }

    private func temperatureLegend(_ series: TemperatureSeries) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(series.color)
                .frame(width: 6, height: 6)
            Text(series.title)
                .foregroundColor(.secondary)
            Text(series.value(in: latest).map { "\($0, specifier: "%.0f")°" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .font(.system(size: 11))
    }
}

private enum TemperatureSeries: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case ssd
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ssd: fanBarText("硬盘（SSD）", "SSD")
        case .battery: fanBarText("电池", "Battery")
        }
    }

    var color: Color {
        switch self {
        case .cpu: .orange
        case .gpu: .accentColor
        case .ssd: Color(red: 0.18, green: 0.72, blue: 0.82)
        case .battery: .green
        }
    }

    var keyPath: KeyPath<ThermalReading, Double?> {
        switch self {
        case .cpu: \.cpuCelsius
        case .gpu: \.gpuCelsius
        case .ssd: \.ssdCelsius
        case .battery: \.batteryCelsius
        }
    }

    func value(in reading: ThermalReading?) -> Double? {
        guard let reading else { return nil }
        return reading[keyPath: keyPath]
    }
}

private struct TemperaturePlot: View {
    let samples: [ThermalReading]
    let series: [TemperatureSeries]
    let yDomain: ClosedRange<Double>
    let timeRange: ClosedRange<Date>

    private let leftInset: CGFloat = 29
    private let rightInset: CGFloat = 6
    private let topInset: CGFloat = 5
    private let bottomInset: CGFloat = 21

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

                ForEach(series) { series in
                    curvePath(
                        values: samples.map { $0[keyPath: series.keyPath] },
                        in: plotRect
                    )
                    .stroke(
                        series.color,
                        style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                    )
                }

                xAxisLabels(in: plotRect, width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func xAxisLabels(in plotRect: CGRect, width: CGFloat) -> some View {
        let labels = TemperatureChartTimeAxis.labels(in: timeRange)

        return HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == labels.count - 1 ? .trailing : .center))
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
            let date = samples[index].sampledAt
            if index > 0,
               date.timeIntervalSince(samples[index - 1].sampledAt) > TemperatureChartTimeAxis.maximumSampleGap {
                flushSegment()
            }
            guard let value else {
                flushSegment()
                continue
            }
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
