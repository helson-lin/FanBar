import Foundation
import FanBarShared
import FanBarUI
import SwiftUI
import WidgetKit

@available(macOS 14.0, *)
struct FanBarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FanBarWidgetSnapshot
}

@available(macOS 14.0, *)
struct FanBarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FanBarWidgetEntry {
        FanBarWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (FanBarWidgetEntry) -> Void
    ) {
        completion(FanBarWidgetEntry(
            date: Date(),
            snapshot: FanBarWidgetSnapshot.load() ?? .placeholder
        ))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<FanBarWidgetEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = FanBarWidgetSnapshot.load() ?? .placeholder
        let entry = FanBarWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = now.addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

@available(macOS 14.0, *)
struct FanBarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FanBarWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if entry.snapshot.isAvailable {
                switch family {
                case .systemSmall:
                    compactContent
                case .systemLarge:
                    largeContent
                default:
                    mediumContent
                }
            } else {
                unavailableContent
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text(entry.snapshot.isEnglish ? "Updated" : "更新于")
                Text(entry.snapshot.updatedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "fan.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(entry.snapshot.isEnglish ? "Fans" : "风扇")
                .font(.headline)
            Spacer()
            Text(modeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Small widgets use one aggregate rotor, keeping the primary decision data visible.
    private var compactContent: some View {
        VStack(spacing: 3) {
            if let averageRPM {
                FanRotorGraphic(
                    currentRPM: averageRPM,
                    minimumRPM: averageMinimumRPM,
                    maximumRPM: averageMaximumRPM,
                    tint: aggregateTint
                )
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .accessibilityHidden(true)
            }

            Text(rpmLabel)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
            Text(entry.snapshot.isEnglish ? "Average RPM" : "平均转速")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let temperature = entry.snapshot.cpuCelsius {
                Text(temperatureLabel(temperature))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// `mediumContent` and `largeContent` lay every visible fan out in one
    /// row with no scrolling, so the fan count is capped per family and any
    /// remaining fans are summarized by a compact "+N average" gauge rather
    /// than being silently dropped.
    private static let mediumFanLimit = 2
    private static let largeFanLimit = 4

    private var mediumContent: some View {
        fanRow(limit: Self.mediumFanLimit, spacing: 8, graphicSize: 66)
    }

    private var largeContent: some View {
        VStack(spacing: 6) {
            fanRow(limit: Self.largeFanLimit, spacing: 14, graphicSize: 90)
            if let temperature = entry.snapshot.cpuCelsius {
                Text(temperatureLabel(temperature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fanRow(limit: Int, spacing: CGFloat, graphicSize: CGFloat) -> some View {
        let fans = entry.snapshot.fans
        let visibleFans = Array(fans.prefix(limit))
        let hiddenFans = Array(fans.dropFirst(limit))

        return HStack(alignment: .top, spacing: spacing) {
            ForEach(visibleFans) { fan in
                WidgetFanGauge(
                    fan: fan,
                    isEnglish: entry.snapshot.isEnglish,
                    graphicSize: graphicSize
                )
            }
            if !hiddenFans.isEmpty {
                WidgetHiddenFanSummary(
                    hiddenFans: hiddenFans,
                    isEnglish: entry.snapshot.isEnglish,
                    graphicSize: graphicSize
                )
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(entry.snapshot.isEnglish ? "Fan data unavailable" : "风扇数据不可用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var averageRPM: Int? {
        guard !entry.snapshot.fans.isEmpty else { return nil }
        let total = entry.snapshot.fans.reduce(0) { $0 + $1.currentRPM }
        return Int((Double(total) / Double(entry.snapshot.fans.count)).rounded())
    }

    private var averageMinimumRPM: Int {
        guard !entry.snapshot.fans.isEmpty else { return 0 }
        let total = entry.snapshot.fans.reduce(0) { $0 + $1.minimumRPM }
        return Int((Double(total) / Double(entry.snapshot.fans.count)).rounded())
    }

    private var averageMaximumRPM: Int {
        guard !entry.snapshot.fans.isEmpty else { return 1 }
        let total = entry.snapshot.fans.reduce(0) { $0 + $1.maximumRPM }
        return max(Int((Double(total) / Double(entry.snapshot.fans.count)).rounded()), 1)
    }

    private var aggregateTint: Color {
        let intensity = Double(averageRPM ?? 0) / Double(averageMaximumRPM)
        return intensity > 0.6
            ? Color(red: 0.20, green: 0.88, blue: 1.0)
            : Color(red: 0.32, green: 0.55, blue: 0.95)
    }

    private var rpmLabel: String {
        guard let averageRPM else { return "— RPM" }
        return "\(averageRPM) RPM"
    }

    private var modeLabel: String {
        switch entry.snapshot.mode {
        case .automatic:
            return entry.snapshot.isEnglish ? "Automatic" : "自动"
        case .temperatureCurve:
            return entry.snapshot.isEnglish ? "Smart" : "智能"
        case .fixed:
            return entry.snapshot.isEnglish ? "Manual" : "手动"
        }
    }

    private func temperatureLabel(_ value: Double) -> String {
        let formatted = String(format: "%.0f°C", value)
        return "CPU \(formatted)"
    }
}

@available(macOS 14.0, *)
private struct WidgetFanGauge: View {
    let fan: FanBarWidgetSnapshot.Fan
    let isEnglish: Bool
    let graphicSize: CGFloat

    private var tint: Color {
        let intensity = fan.maximumRPM > 0
            ? Double(fan.currentRPM) / Double(fan.maximumRPM)
            : 0
        return intensity > 0.6
            ? Color(red: 0.20, green: 0.88, blue: 1.0)
            : Color(red: 0.32, green: 0.55, blue: 0.95)
    }

    var body: some View {
        VStack(spacing: 2) {
            // FanRotorGraphic has a 104×96 drawing canvas. Scale the drawing,
            // rather than placing its full-size canvas in a smaller frame.
            FanRotorGraphic(
                currentRPM: fan.currentRPM,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM,
                tint: tint
            )
            .scaleEffect(graphicSize / 104)
            .frame(width: graphicSize, height: graphicSize * 96 / 104)

            Text(isEnglish ? "Fan \(fan.index + 1)" : "风扇 \(fan.index + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(fan.currentRPM) RPM")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text("\(fan.minimumRPM)–\(fan.maximumRPM)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEnglish ? "Fan \(fan.index + 1)" : "风扇 \(fan.index + 1)")
        .accessibilityValue("\(fan.currentRPM) RPM")
    }
}

@available(macOS 14.0, *)
@main
struct FanBarWidget: Widget {
    let kind = FanBarWidgetSnapshot.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FanBarWidgetProvider()) { entry in
            FanBarWidgetView(entry: entry)
        }
        .configurationDisplayName(
            LocalizedStringKey("widget.displayName")
        )
        .description(
            LocalizedStringKey("widget.description")
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Compact "+N" summary shown when a widget family's fan row is too narrow
/// to lay out every fan, showing the average RPM of the hidden fans so the
/// truncated data is still represented rather than silently dropped.
@available(macOS 14.0, *)
private struct WidgetHiddenFanSummary: View {
    let hiddenFans: [FanBarWidgetSnapshot.Fan]
    let isEnglish: Bool
    let graphicSize: CGFloat

    private var averageRPM: Int {
        guard !hiddenFans.isEmpty else { return 0 }
        let total = hiddenFans.reduce(0) { $0 + $1.currentRPM }
        return Int((Double(total) / Double(hiddenFans.count)).rounded())
    }

    private var accessibilityLabelText: String {
        isEnglish
            ? "\(hiddenFans.count) more fans, average \(averageRPM) RPM"
            : "另外 \(hiddenFans.count) 个风扇，平均 \(averageRPM) RPM"
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                Text("+\(hiddenFans.count)")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.7)
            }
            .frame(width: graphicSize * 0.6, height: graphicSize * 0.6)

            Text(isEnglish ? "More" : "更多")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(averageRPM) RPM")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

private extension FanBarWidgetSnapshot {
    static let placeholder = FanBarWidgetSnapshot(
        fans: [Fan(index: 0, currentRPM: 1_800, minimumRPM: 1_200, maximumRPM: 5_000, isManual: false)],
        cpuCelsius: 48,
        mode: .automatic,
        isAvailable: true,
        isEnglish: false
    )
}
