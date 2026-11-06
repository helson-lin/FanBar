import FanBarShared
import SwiftUI

/// Formats the chart's x-axis as wall-clock hour:minute. `mm:ss` would drop
/// the hour, so a window ending at 17:09 must still read `16:59  17:04  17:09`
/// when it crosses an hour boundary.
enum TemperatureChartTimeAxis {
    /// The window shown when the chart opens.
    static let historyDuration: TimeInterval = 10 * 60

    /// Longest window the chart can show. Samples older than this are dropped.
    static let retainedDuration: TimeInterval = 60 * 60

    /// Allow scheduling jitter around the two-second cadence without drawing a gap.
    static let maximumContinuousGap: TimeInterval = 5
    /// Short missing intervals may be bridged with a dashed line, never a filled area.
    /// Longer interruptions (sleep/restarts) remain disconnected.
    static let maximumSampleGap: TimeInterval = 15

    static func missingIntervals(dates: [Date], values: [Double?]) -> [ClosedRange<Int>] {
        guard dates.count == values.count else { return [] }
        var result: [ClosedRange<Int>] = []
        var previous: Int?
        for index in values.indices {
            guard let value = values[index], value.isFinite else { continue }
            if let previous {
                let elapsed = dates[index].timeIntervalSince(dates[previous])
                if elapsed > 0, elapsed <= maximumSampleGap,
                   index > previous + 1 || elapsed > maximumContinuousGap {
                    result.append(previous...index)
                }
            }
            previous = index
        }
        return result
    }

    /// Splits sample dates into runs of consecutive indices that are close
    /// enough in time to be drawn and smoothed as one continuous curve.
    static func segments(for dates: [Date]) -> [ClosedRange<Int>] {
        guard !dates.isEmpty else { return [] }

        var result: [ClosedRange<Int>] = []
        var start = dates.startIndex

        for index in dates.indices.dropFirst()
            where dates[index].timeIntervalSince(dates[index - 1]) > maximumContinuousGap {
            result.append(start...(index - 1))
            start = index
        }
        result.append(start...(dates.endIndex - 1))
        return result
    }

    /// The x-axis always spans the selected window ending at the newest sample
    /// (or now while no sample exists), so the axis stays predictable across
    /// app launches.
    static func displayRange(
        lastSample: Date?,
        duration: TimeInterval = historyDuration,
        now: Date = Date()
    ) -> ClosedRange<Date> {
        let end = lastSample ?? now
        return end.addingTimeInterval(-duration)...end
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
        formatter.dateFormat = "H:mm"
        return tickDates(in: timeRange).map { formatter.string(from: $0) }
    }
}

enum TemperatureChartScale {
    /// Fits the visible readings with 5° of air, on whole tens, at least 40° tall, so the
    /// traces fill the plot instead of hugging the floor under a distant alert line.
    static func fitted(to values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 20...100 }
        let lower = max(0, ((low - 5) / 10).rounded(.down) * 10)
        let upper = max(((high + 5) / 10).rounded(.up) * 10, lower + 40)
        return lower...upper
    }

    /// Every 10°, or every 20° when the range is tall enough to crowd the axis.
    static func ticks(in domain: ClosedRange<Double>) -> [Double] {
        let step: Double = domain.upperBound - domain.lowerBound > 60 ? 20 : 10
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
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
        let cutoff = now.addingTimeInterval(-TemperatureChartTimeAxis.retainedDuration)
        return decoded.filter { $0.sampledAt >= cutoff }
    }

    static func save(_ samples: [ThermalReading], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: preferenceKey)
    }
}

/// Time windows the trace can show. Raw values are seconds, so `duration` is the window length.
enum TemperatureChartRange: TimeInterval, CaseIterable, Identifiable {
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: TimeInterval { rawValue }

    var duration: TimeInterval { rawValue }

    /// Short labels for the compact segmented control.
    var title: String {
        switch self {
        case .tenMinutes: fanBarText("10 分", "10m")
        case .thirtyMinutes: fanBarText("30 分", "30m")
        case .oneHour: fanBarText("1 时", "1h")
        }
    }
}

/// CPU (hottest core), GPU, SSD, and battery temperature over the selected
/// window, with a reference line at the configured high-temperature alert threshold. The legend doubles as the
/// current reading and toggles each series. Drawn with SwiftUI paths so it
/// works on macOS 11 without Charts.framework.
struct TemperatureChart: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    static let historyDuration = TemperatureChartTimeAxis.historyDuration

    /// Everything the controller retains, newest last. `samples` narrows it to the selected window.
    let allSamples: [ThermalReading]
    let alertThreshold: Double
    @Binding var range: TemperatureChartRange

    @State private var hiddenSeries: Set<TemperatureSeries> = []
    @Environment(\.colorScheme) private var colorScheme

    init(samples: [ThermalReading], range: Binding<TemperatureChartRange>, alertThreshold: Double) {
        self.alertThreshold = ThermalAlertSettings.clampedThreshold(alertThreshold)
        allSamples = samples
        _range = range
    }

    private var palette: PanelPalette { PanelPalette(colorScheme: colorScheme) }

    /// The newest sample always stays inside the window, so the legend and axis
    /// keep their values when the user switches to a shorter range.
    private var samples: [ThermalReading] {
        guard let newest = allSamples.last else { return [] }
        let start = newest.sampledAt.addingTimeInterval(-range.duration)
        return allSamples.filter { $0.sampledAt >= start }
    }

    private var latest: ThermalReading? { samples.last }

    private var drawnSeries: [TemperatureSeries] {
        TemperatureSeries.allCases.filter { series in
            !hiddenSeries.contains(series) && samples.contains { $0[keyPath: series.keyPath] != nil }
        }
    }

    /// CPU, GPU, and SSD always have a legend slot (greyed when a sensor is
    /// missing); the battery appears only on Macs that have one.
    private var legendSeries: [TemperatureSeries] {
        TemperatureSeries.allCases.filter { series in
            series != .battery || allSamples.contains { $0.batteryCelsius != nil }
        }
    }

    private var timeRange: ClosedRange<Date> {
        TemperatureChartTimeAxis.displayRange(lastSample: latest?.sampledAt, duration: range.duration)
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
        let samples = samples
        guard samples.count > smoothingRadius * 2 else { return samples }

        return sampleSegments.flatMap { segment in
            segment.map { index in
                ThermalReading(
                    sampledAt: samples[index].sampledAt,
                    cpuCelsius: smoothedValue(samples, at: index, within: segment, keyPath: \.cpuCelsius),
                    gpuCelsius: smoothedValue(samples, at: index, within: segment, keyPath: \.gpuCelsius),
                    ssdCelsius: smoothedValue(samples, at: index, within: segment, keyPath: \.ssdCelsius),
                    batteryCelsius: smoothedValue(samples, at: index, within: segment, keyPath: \.batteryCelsius),
                    cpuHottestCelsius: smoothedValue(samples, at: index, within: segment, keyPath: \.cpuHottestCelsius)
                )
            }
        }
    }

    private func smoothedValue(
        _ samples: [ThermalReading],
        at index: Int,
        within segment: ClosedRange<Int>,
        keyPath: KeyPath<ThermalReading, Double?>
    ) -> Double? {
        // Smoothing must not turn an absent sensor reading into a measured value.
        guard let current = samples[index][keyPath: keyPath], current.isFinite else { return nil }
        let lowerBound = max(segment.lowerBound, index - smoothingRadius)
        let upperBound = min(segment.upperBound, index + smoothingRadius)
        let values = (lowerBound...upperBound).compactMap { samples[$0][keyPath: keyPath] }.filter { $0.isFinite }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(fanBarText("温度", "Temperature"))
                    .font(.system(size: TemperatureHeadingLayout.headingFontSize, weight: .semibold))

                if let power = SystemPowerReadout.current(from: allSamples) {
                    powerReadout(power)
                        .padding(.leading, TemperatureHeadingLayout.readoutLeading)
                }

                Spacer(minLength: TemperatureHeadingLayout.minimumGap)

                PanelSegmentedControl(
                    options: TemperatureChartRange.allCases.map { ($0, $0.title) },
                    selection: range,
                    compact: true
                ) { range = $0 }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(fanBarText("温度曲线时长", "Temperature window"))
            }

            legend
                .padding(.top, 8)
                .padding(.bottom, 4)
                .padding(.leading, -6)

            if samples.isEmpty {
                Text(fanBarText("正在读取温度", "Reading temperature"))
                    .font(.system(size: 11))
                    .foregroundColor(palette.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
            } else {
                TemperaturePlot(
                    samples: chartSamples,
                    series: drawnSeries,
                    timeRange: timeRange,
                    palette: palette,
                    warningLine: alertThreshold
                )
                .frame(height: 96)
                .accessibilityLabel(fanBarText("温度曲线", "Temperature trends"))
                .help(fanBarText(
                    "CPU 告警按平均温度判断；最高温度曲线用于观察瞬时峰值。",
                    "CPU alerts use the average temperature; the highest-temperature trace shows peaks."
                ))
            }

            axisLabels
                .padding(.top, 5)
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    /// Secondary to the heading and never a status color: power has no high threshold.
    private func powerReadout(_ power: SystemPowerReadout) -> some View {
        let size = TemperatureHeadingLayout.readoutFontSize
        let showsTitle = TemperatureHeadingLayout.showsPowerTitle(
            heading: fanBarText("温度", "Temperature"),
            rangeTitles: TemperatureChartRange.allCases.map(\.title),
            powerTitle: SystemPowerReadout.title,
            valueText: power.valueText
        )
        return HStack(spacing: TemperatureHeadingLayout.titleSpacing) {
            if showsTitle {
                Text(SystemPowerReadout.title)
                    .font(.system(size: size))
                    .foregroundColor(palette.secondaryText)
            }
            Text(power.valueText)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(power.accessibilityLabel)
        .help(SystemPowerReadout.help)
    }

    private var legend: some View {
        HStack(spacing: 2) {
            ForEach(legendSeries) { series in
                legendItem(series)
            }
            Spacer(minLength: 0)
            // Four series fill the row; the "Now" caption yields to the battery.
            if legendSeries.count < 4 {
                Text(fanBarText("现在", "Now"))
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.tertiaryText)
            }
        }
    }

    private func legendItem(_ series: TemperatureSeries) -> some View {
        let value = latest?[keyPath: series.keyPath]
        let isShown = !hiddenSeries.contains(series)
        return Button {
            if hiddenSeries.contains(series) {
                hiddenSeries.remove(series)
            } else {
                hiddenSeries.insert(series)
            }
        } label: {
            HStack(spacing: 5) {
                SeriesSwatch(series: series, color: series.color(in: palette))
                    .frame(width: 12, height: 3)
                // Long names (Russian "Аккумулятор") shrink, then truncate; the reading never does.
                // A fixed-size legend wider than the panel would widen the whole column off-center.
                Text(series == .cpu ? cpuLegendTitle : series.title)
                    .foregroundColor(palette.secondaryText)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                Text(value.map { "\(Int($0.rounded()))°" } ?? "—")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .font(.system(size: 11).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .opacity(value == nil ? 0.45 : isShown ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
        .help(value == nil ? fanBarText("传感器不可用", "Sensor unavailable")
              : series == .cpu ? latest?.cpuTemperatureSummary ?? "" : "")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    private var cpuLegendTitle: String {
        latest?.cpuHottestCelsius == nil
            ? fanBarText("CPU 平均", "CPU avg")
            : fanBarText("CPU 最高", "CPU max")
    }

    private var axisLabels: some View {
        let labels = TemperatureChartTimeAxis.labels(in: timeRange)
        return HStack {
            Text(labels[0])
            Spacer()
            Text(labels[1])
            Spacer()
            Text(fanBarText("现在", "Now"))
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundColor(palette.tertiaryText)
        .padding(.trailing, TemperaturePlot.axisWidth)
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
        case .ssd: fanBarText("SSD", "SSD")
        case .battery: fanBarText("电池", "Battery")
        }
    }

    func color(in palette: PanelPalette) -> Color {
        switch self {
        case .cpu: palette.cpu
        case .gpu: palette.gpu
        case .ssd: palette.ssd
        case .battery: palette.battery
        }
    }

    var keyPath: KeyPath<ThermalReading, Double?> {
        switch self {
        case .cpu: \.cpuDisplayCelsius
        case .gpu: \.gpuCelsius
        case .ssd: \.ssdCelsius
        case .battery: \.batteryCelsius
        }
    }

    /// Line style is a second cue beside color: GPU dashed, battery dotted.
    var dash: [CGFloat] {
        switch self {
        case .cpu, .ssd: []
        case .gpu: [5, 3]
        case .battery: [0.5, 3.5]
        }
    }
}

/// The legend's sample of a series' line, dash and all.
private struct SeriesSwatch: View {
    let series: TemperatureSeries
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 1, y: proxy.size.height / 2))
                path.addLine(to: CGPoint(x: proxy.size.width - 1, y: proxy.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: series == .battery ? 2.5 : 2,
                lineCap: .round,
                dash: series == .battery ? [0.5, 3] : series.dash
            ))
        }
        .accessibilityHidden(true)
    }
}

private struct TemperaturePlot: View {
    let samples: [ThermalReading]
    let series: [TemperatureSeries]
    let timeRange: ClosedRange<Date>
    let palette: PanelPalette

    /// Room on the right for the tick labels.
    static let axisWidth: CGFloat = 26
    /// Drawn only when it falls inside the fitted range; otherwise it would flatten every trace.
    let warningLine: Double
    /// Fitted once per plot: every point's y position reads it, so it must not be recomputed per point.
    private let domain: ClosedRange<Double>

    init(
        samples: [ThermalReading],
        series: [TemperatureSeries],
        timeRange: ClosedRange<Date>,
        palette: PanelPalette,
        warningLine: Double
    ) {
        self.samples = samples
        self.series = series
        self.timeRange = timeRange
        self.palette = palette
        self.warningLine = warningLine
        domain = TemperatureChartScale.fitted(to: series.flatMap { series in
            samples.compactMap { $0[keyPath: series.keyPath] }.filter(\.isFinite)
        })
    }

    private var showsWarningLine: Bool { domain.contains(warningLine) }
    private var gridTicks: [Double] {
        TemperatureChartScale.ticks(in: domain).filter { !showsWarningLine || abs($0 - warningLine) > 4 }
    }

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: 0, y: 0, width: max(1, proxy.size.width - Self.axisWidth), height: proxy.size.height)

            ZStack(alignment: .topLeading) {
                ForEach(gridTicks, id: \.self) { tick in
                    gridLine(at: tick, in: plot)
                        .stroke(palette.hairline, lineWidth: 1)
                }
                if showsWarningLine {
                    gridLine(at: warningLine, in: plot)
                        .stroke(palette.warm.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }

                ForEach(series) { series in
                    let values = samples.map { $0[keyPath: series.keyPath] }
                    // Only CPU carries a faint fill; more fills would outshout the panel's conclusion.
                    if series == .cpu {
                        areaPath(values: values, in: plot)
                            .fill(LinearGradient(
                                colors: [series.color(in: palette).opacity(0.10), series.color(in: palette).opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    missingIntervalPath(values: values, in: plot)
                        .stroke(
                            series.color(in: palette).opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3])
                        )
                    curvePath(values: values, in: plot)
                        .stroke(
                            series.color(in: palette),
                            style: StrokeStyle(
                                lineWidth: series == .battery ? 2.6 : 1.6,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: series.dash
                            )
                        )
                }

                if showsWarningLine {
                    axisLabel("\(Int(warningLine))°", at: warningLine, in: plot, color: palette.warm)
                }
                ForEach(gridTicks, id: \.self) { tick in
                    axisLabel("\(Int(tick))°", at: tick, in: plot, color: palette.tertiaryText)
                }
            }
        }
    }

    private func axisLabel(_ text: String, at value: Double, in plot: CGRect, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10).monospacedDigit())
            .foregroundColor(color)
            .frame(width: Self.axisWidth - 4, alignment: .leading)
            .position(x: plot.maxX + 4 + (Self.axisWidth - 4) / 2, y: yPosition(value, in: plot))
    }

    private func gridLine(at value: Double, in plot: CGRect) -> Path {
        Path { path in
            let y = yPosition(value, in: plot)
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
    }

    private func yPosition(_ value: Double, in rect: CGRect) -> CGFloat {
        let domain = self.domain
        let clamped = min(domain.upperBound, max(domain.lowerBound, value))
        let fraction = (clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return rect.maxY - CGFloat(fraction) * rect.height
    }

    /// Splits a series into drawable runs: a missing value or a gap in time ends a run.
    private func runs(values: [Double?], in rect: CGRect) -> [[CGPoint]] {
        let firstDate = timeRange.lowerBound
        let timeSpan = max(timeRange.upperBound.timeIntervalSince(firstDate), 1)
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []

        for (index, value) in values.enumerated() {
            let date = samples[index].sampledAt
            if index > 0,
               date.timeIntervalSince(samples[index - 1].sampledAt) > TemperatureChartTimeAxis.maximumContinuousGap {
                if !current.isEmpty { result.append(current) }
                current = []
            }
            guard let value, value.isFinite else {
                if !current.isEmpty { result.append(current) }
                current = []
                continue
            }
            let position = min(1, max(0, date.timeIntervalSince(firstDate) / timeSpan))
            current.append(CGPoint(x: rect.minX + CGFloat(position) * rect.width, y: yPosition(value, in: rect)))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func missingIntervalPath(values: [Double?], in rect: CGRect) -> Path {
        let dates = samples.map(\.sampledAt)
        let intervals = TemperatureChartTimeAxis.missingIntervals(dates: dates, values: values)
        let span = max(timeRange.upperBound.timeIntervalSince(timeRange.lowerBound), 1)
        return Path { path in
            for interval in intervals {
                guard let start = values[interval.lowerBound], let end = values[interval.upperBound] else { continue }
                let startX = dates[interval.lowerBound].timeIntervalSince(timeRange.lowerBound) / span
                let endX = dates[interval.upperBound].timeIntervalSince(timeRange.lowerBound) / span
                path.move(to: CGPoint(x: rect.minX + CGFloat(startX) * rect.width, y: yPosition(start, in: rect)))
                path.addLine(to: CGPoint(x: rect.minX + CGFloat(endX) * rect.width, y: yPosition(end, in: rect)))
            }
        }
    }

    private func curvePath(values: [Double?], in rect: CGRect) -> Path {
        var path = Path()
        for run in runs(values: values, in: rect) {
            appendSmoothRun(run, to: &path)
        }
        return path
    }

    private func areaPath(values: [Double?], in rect: CGRect) -> Path {
        var path = Path()
        for run in runs(values: values, in: rect) where run.count > 1 {
            var line = Path()
            appendSmoothRun(run, to: &line)
            path.addPath(line)
            path.addLine(to: CGPoint(x: run[run.count - 1].x, y: rect.maxY))
            path.addLine(to: CGPoint(x: run[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    private func appendSmoothRun(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return
        }
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }
}
