import FanBarShared
import SwiftUI

// MARK: - Resources

/// A two-column resource grid held together by whitespace; disk details expand beneath it.
/// Shows the modules chosen in Settings, in order; an odd last module spans its row.
struct PanelResourceList: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    typealias Resource = PanelMonitorModule

    let usage: SystemUsage
    let thermal: ThermalReading?
    let cpuHistory: [Double]
    let gpuHistory: [Double]
    let animates: Bool
    var modules: [PanelMonitorModule] = PanelMonitorPreferences.defaultModules

    @Binding var expanded: Resource?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDiskDetailRevealed = false

    private var palette: PanelPalette { PanelPalette(colorScheme: colorScheme) }

    /// Every cell stacks label, value, a visualization `vizHeight` tall (bars sit on its
    /// bottom edge) and a `captionHeight` caption, so any two modules side by side line up.
    private static let vizHeight: CGFloat = 20
    private static let captionHeight: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            resourceGrid
                .padding(.vertical, 7)
            if expanded == .disk, modules.contains(.disk) {
                PanelDivider()
                diskDetail
                    .padding(.vertical, PanelLayout.rowVerticalPadding)
                    // Height changes instantly (see setExpanded); only the drawing eases in.
                    .opacity(isDiskDetailRevealed ? 1 : 0)
                    .scaleEffect(isDiskDetailRevealed ? 1 : 0.98, anchor: .top)
                    .onAppear {
                        guard animates else {
                            isDiskDetailRevealed = true
                            return
                        }
                        withAnimation(.easeOut(duration: 0.15)) { isDiskDetailRevealed = true }
                    }
                    .onDisappear { isDiskDetailRevealed = false }
            }
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func setExpanded(_ resource: Resource?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { expanded = resource }
    }

    private var resourceGrid: some View {
        VStack(spacing: 0) {
            ForEach(PanelMonitorPreferences.rows(modules), id: \.self) { row in
                if row.count == 2 {
                    gridRow { moduleCell(row[0]) } trailing: { moduleCell(row[1]) }
                } else if let only = row.first {
                    moduleCell(only)
                }
            }
        }
    }

    @ViewBuilder
    private func moduleCell(_ module: PanelMonitorModule) -> some View {
        switch module {
        case .cpu: cpuCell
        case .memory: memoryCell
        case .gpu: gpuCell
        case .disk: diskCell
        }
    }

    private var cpuCell: some View {
        cell(.cpu, title: "CPU", value: percent(usage.cpuFraction)) {
            CoreGroups(
                fractions: usage.cpuCoreFractions,
                kinds: usage.cpuCoreKinds,
                coreCount: usage.cpuCoreCount,
                color: resourceColor(.cpu),
                barHeight: Self.vizHeight,
                palette: palette
            )
            .padding(.top, 4)
        }
    }

    private var memoryCell: some View {
        cell(
            .memory,
            title: fanBarText("内存", "Memory"),
            meta: usage.memory.map(memoryMeta),
            value: percent(usage.memoryFraction)
        ) {
            let used = resourceColor(.memory)
            VStack(alignment: .leading, spacing: 6) {
                MemoryBar(memory: usage.memory, usedColor: used, palette: palette)
                    .frame(height: 6)
                    .frame(height: Self.vizHeight, alignment: .bottom)
                HStack(spacing: 9) {
                    memoryKey(used, fanBarText("应用", "App"))
                    memoryKey(used.opacity(MemoryBar.compressedOpacity), fanBarText("压缩", "Comp."))
                    memoryKey(palette.memoryCache, fanBarText("缓存", "Cache"))
                }
                .frame(height: Self.captionHeight, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    private var gpuCell: some View {
        cell(
            .gpu,
            title: "GPU",
            meta: usage.gpuCoreCount.map { fanBarFormat("%d 核", "%d cores", $0) },
            value: percent(usage.gpuFraction)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                CapacityBar(fraction: usage.gpuFraction, color: resourceColor(.gpu), palette: palette)
                    .frame(height: 6)
                    .frame(height: Self.vizHeight, alignment: .bottom)
                summaryText(usage.gpuMemoryInUseBytes.map {
                    fanBarFormat("显存 %@", "Memory %@", PanelByteFormat.compact($0))
                } ?? "—")
                .frame(height: Self.captionHeight, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    /// Equal-height halves separated by a 24pt gutter.
    private func gridRow(
        @ViewBuilder leading: () -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 0) {
            leading()
                .padding(.trailing, 12)
            trailing()
                .padding(.leading, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Cells

    /// Label and meta, the value, then one visualization; every cell shares this rhythm.
    private func cell(
        _ resource: Resource,
        title: String,
        meta: String? = nil,
        value: String,
        @ViewBuilder viz: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow(title: title, meta: meta, level: level(resource))
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundColor(.primary)
            viz()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue([value, meta, level(resource).spokenName].compactMap { $0 }.joined(separator: ", "))
    }

    private func labelRow(
        title: String,
        meta: String?,
        level: ResourceLevel = .normal,
        chevron: String? = nil
    ) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.secondaryText)
            // Color is never the only cue: a raised level is also said in words.
            if let name = level.spokenName {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(level == .critical ? palette.hot : palette.warmInk)
                    .padding(.leading, 3)
            }
            Spacer(minLength: 4)
            if let meta {
                Text(meta)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(palette.tertiaryText)
            }
            if let chevron {
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(palette.tertiaryText)
            }
        }
        .lineLimit(1)
    }

    /// Leads with free space, the number the disk rule is judged by, and says what it means.
    private var diskCell: some View {
        let isOpen = expanded == .disk
        let level = diskLevel
        let summary: Text = {
            let total = Text(fanBarFormat("共 %@", "%@ total", wholeGigabytes(diskTotalBytes)))
            switch level {
            case .normal:
                return total
            case .elevated:
                return Text(fanBarText("空间偏低", "Space low")).fontWeight(.semibold).foregroundColor(palette.warmInk)
                    + Text(" · ") + total
            case .critical:
                return Text(fanBarText("空间不足", "Almost full")).fontWeight(.semibold).foregroundColor(palette.hot)
                    + Text(" · ") + total
            }
        }()
        let used = percent(diskFraction)
        return Button {
            setExpanded(isOpen ? nil : .disk)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                labelRow(
                    title: diskTitle,
                    meta: fanBarFormat("已用 %@", "%@ used", used),
                    chevron: isOpen ? "chevron.up" : "chevron.down"
                )
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(wholeGigabytes(freeDiskBytes))
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundColor(.primary)
                    Text(fanBarText("可用", "free"))
                        .font(.system(size: 11))
                        .foregroundColor(palette.secondaryText)
                }
                VStack(alignment: .leading, spacing: 6) {
                    CapacityBar(fraction: diskFraction, color: level.color(palette),
                                palette: palette)
                        .frame(height: 6)
                        .frame(height: Self.vizHeight, alignment: .bottom)
                    summary
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: Self.captionHeight, alignment: .leading)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelDimButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(diskTitle)
        .accessibilityValue([
            fanBarFormat("可用 %@", "%@ free", wholeGigabytes(freeDiskBytes)),
            fanBarFormat("已用 %@", "%@ used", used),
            level.diskSpokenName
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityHint(isOpen ? fanBarText("收起磁盘详情", "Hide disk details") : fanBarText("展开磁盘详情", "Show disk details"))
    }

    private func summaryText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(palette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    // MARK: Levels

    /// Processors by load; memory by app and compressed pages. Disks use free space instead.
    private func level(_ resource: Resource) -> ResourceLevel {
        switch resource {
        case .cpu: ResourceLevel(fraction: usage.cpuFraction, thresholds: .processor)
        case .memory: ResourceLevel(fraction: usage.memoryFraction, thresholds: .capacity)
        case .gpu: ResourceLevel(fraction: usage.gpuFraction, thresholds: .processor)
        case .disk: diskLevel
        }
    }

    private func resourceColor(_ resource: Resource) -> Color {
        level(resource).color(palette)
    }

    // Every overview value describes the startup volume. Free space on an
    // external volume cannot make room for system updates or swap on this one.
    private var startupDisk: DiskVolumeUsage? { usage.disks.first { $0.id == "/" } }

    var diskTitle: String { fanBarText("启动盘", "Startup disk") }

    var diskTotalBytes: UInt64? { startupDisk?.totalBytes }

    var diskFraction: Double? { startupDisk?.fraction }

    var freeDiskBytes: UInt64? {
        guard let disk = startupDisk else { return nil }
        let used = disk.usedBytes
        let total = disk.totalBytes
        return total > used ? total - used : 0
    }

    var diskLevel: ResourceLevel {
        ResourceLevel(freeBytes: freeDiskBytes, totalBytes: diskTotalBytes)
    }

    // MARK: Formatting

    private func memoryKey(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(palette.secondaryText)
    }

    private var diskDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(usage.disks.count > 1
                     ? fanBarFormat("磁盘 · %d 块", "Disks · %d", usage.disks.count)
                     : fanBarText("磁盘", "Disk"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.secondaryText)
                Spacer()
                Button {
                    setExpanded(nil)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PanelDimButtonStyle())
                .foregroundColor(palette.secondaryText)
                .padding(.trailing, -5)
                .accessibilityLabel(fanBarText("收起磁盘详情", "Hide disk details"))
            }
            ForEach(usage.disks) { disk in
                let free = disk.totalBytes > disk.usedBytes ? disk.totalBytes - disk.usedBytes : 0
                let level = ResourceLevel(freeBytes: free, totalBytes: disk.totalBytes)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        (Text(disk.name).fontWeight(.medium).foregroundColor(.primary)
                            + Text(disk.isInternal ? "" : fanBarText(" · 外置", " · External"))
                            .foregroundColor(palette.tertiaryText)
                            + ssdTemperatureText(for: disk))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(fanBarFormat("可用 %@ / %@", "%@ free of %@",
                                          wholeGigabytes(free), wholeGigabytes(disk.totalBytes)))
                            .foregroundColor(level == .normal ? palette.secondaryText
                                             : level == .elevated ? palette.warmInk : palette.hot)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(.system(size: 12).monospacedDigit())
                    CapacityBar(fraction: disk.fraction, color: level.color(palette),
                                palette: palette)
                        .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The SSD sensor only describes the internal drive, so only the startup disk shows it.
    /// Quiet when normal; takes the SSD warm/hot colors only once it nears its limits.
    private func ssdTemperatureText(for disk: DiskVolumeUsage) -> Text {
        guard disk.id == "/", disk.isInternal, let celsius = thermal?.ssdCelsius else { return Text("") }
        let color: Color = switch ThermalLevel(celsius: celsius, part: .ssd) {
        case .normal: palette.tertiaryText
        case .warm: palette.warmInk
        case .hot: palette.hot
        }
        return Text(String(format: " · %.0f°C", celsius)).foregroundColor(color)
    }

    private func percent(_ fraction: Double?) -> String {
        fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    /// "29 GB" above ten gigabytes, "4.2 GB" below, where the tenth matters.
    private func wholeGigabytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let gigabytes = Double(bytes) / PanelByteFormat.gibibyte
        return String(format: gigabytes >= 10 ? "%.0f GB" : "%.1f GB", gigabytes)
    }

    /// "8.4 / 16 GB": used to a tenth, installed memory as the whole number Apple sells.
    private func memoryMeta(_ memory: MemoryBreakdown) -> String {
        String(
            format: "%.1f / %.0f GB",
            Double(memory.usedBytes) / PanelByteFormat.gibibyte,
            Double(memory.totalBytes) / PanelByteFormat.gibibyte
        )
    }
}

/// How much attention a resource needs. Processors spike briefly and recover, so they warn
/// later than memory, which only fills up; disks are judged by the space left.
enum ResourceLevel: Equatable {
    case normal
    case elevated
    case critical

    struct Thresholds {
        var elevated: Double
        var critical: Double

        static let processor = Thresholds(elevated: 0.7, critical: 0.9)
        static let capacity = Thresholds(elevated: 0.8, critical: 0.9)
    }

    init(fraction: Double?, thresholds: Thresholds) {
        switch fraction ?? 0 {
        case thresholds.critical...: self = .critical
        case thresholds.elevated...: self = .elevated
        default: self = .normal
        }
    }

    /// Low under 10% or 20 GB free; almost full under 2% or 5 GB.
    init(freeBytes: UInt64?, totalBytes: UInt64?) {
        guard let freeBytes, let totalBytes, totalBytes > 0 else {
            self = .normal
            return
        }
        let free = Double(freeBytes)
        let freeFraction = free / Double(totalBytes)
        let gigabyte = PanelByteFormat.gibibyte
        if free < 5 * gigabyte || freeFraction < 0.02 {
            self = .critical
        } else if free < 20 * gigabyte || freeFraction < 0.10 {
            self = .elevated
        } else {
            self = .normal
        }
    }

    /// Green, orange, red: the same steps as temperature, for load and disk space alike.
    func color(_ palette: PanelPalette) -> Color {
        switch self {
        case .normal: palette.accent
        case .elevated: palette.warm
        case .critical: palette.hot
        }
    }

    /// VoiceOver hears the state the color shows; sighted users read the percentage.
    var spokenName: String? {
        switch self {
        case .normal: nil
        case .elevated: fanBarText("偏高", "High")
        case .critical: fanBarText("很高", "Very high")
        }
    }

    var diskSpokenName: String? {
        switch self {
        case .normal: nil
        case .elevated: fanBarText("空间偏低", "Space low")
        case .critical: fanBarText("空间不足", "Almost full")
        }
    }
}

// MARK: - Visualizations

/// App and compressed memory, which set the level, in its color; reclaimable cache stays neutral.
private struct MemoryBar: View {
    static let compressedOpacity = 0.55

    let memory: MemoryBreakdown?
    let usedColor: Color
    let palette: PanelPalette

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                if let memory, memory.totalBytes > 0 {
                    let total = Double(memory.totalBytes)
                    segment(Double(memory.appBytes) / total, usedColor, width: proxy.size.width)
                    segment(
                        Double(memory.compressedBytes) / total,
                        usedColor.opacity(Self.compressedOpacity),
                        width: proxy.size.width
                    )
                    segment(Double(memory.cachedBytes) / total, palette.memoryCache, width: proxy.size.width)
                }
                Spacer(minLength: 0)
            }
            .background(palette.well)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private func segment(_ fraction: Double, _ color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, CGFloat(fraction) * width - 1))
    }
}

/// One filled bar for load or capacity.
private struct CapacityBar: View {
    let fraction: Double?
    let color: Color
    let palette: PanelPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                palette.well
                color.frame(width: CGFloat(min(1, max(0, fraction ?? 0))) * proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

/// Per-core load bars in performance and efficiency groups, labelled under their own bars.
/// Every bar takes the overall CPU color: efficiency cores often run full, which is not an alarm.
/// A group's bars can be narrower than its label (4 P-cores beside 6 E-cores, or 2 E-cores
/// beside 8 P-cores), so the labels share one row instead of each column's width: the first
/// starts at the leading edge and the last ends at the trailing edge, under its own bars.
struct CoreGroups: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    let fractions: [Double]
    let kinds: [CPUCoreKind]
    let coreCount: Int?
    let color: Color
    let barHeight: CGFloat
    let palette: PanelPalette

    private static let groupGap: CGFloat = 6
    static let labelFontSize: CGFloat = 11

    struct CoreGroup: Identifiable {
        var id: String { title }
        var title: String
        var loads: [Double]
    }

    var groups: [CoreGroup] {
        let placeholderCount = coreCount ?? (kinds.isEmpty ? ProcessInfo.processInfo.activeProcessorCount : kinds.count)
        let loads = fractions.isEmpty ? Array(repeating: 0, count: placeholderCount) : fractions
        guard kinds.count == loads.count, Set(kinds.map { $0 == .performance }).count > 1 else {
            return [CoreGroup(title: fanBarFormat("%d 核", "%d cores", loads.count), loads: loads)]
        }
        let performance = zip(kinds, loads).filter { $0.0 == .performance }.map(\.1)
        let efficiency = zip(kinds, loads).filter { $0.0 == .efficiency }.map(\.1)
        return [
            CoreGroup(title: fanBarFormat("性能核 ×%d", "P-cores ×%d", performance.count), loads: performance),
            CoreGroup(title: fanBarFormat("能效核 ×%d", "E-cores ×%d", efficiency.count), loads: efficiency)
        ]
    }

    var body: some View {
        let groups = groups
        let total = max(groups.reduce(0) { $0 + $1.loads.count }, 1)
        // Mac Pro and Ultra chips have 24+ cores; tighter gaps keep each bar readable.
        let barSpacing: CGFloat = total > 16 ? 1 : 2
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let available = proxy.size.width - CGFloat(groups.count - 1) * Self.groupGap
                HStack(alignment: .top, spacing: Self.groupGap) {
                    ForEach(groups) { group in
                        HStack(spacing: barSpacing) {
                            ForEach(Array(group.loads.enumerated()), id: \.offset) { _, load in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 2).fill(palette.well)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color)
                                        .frame(height: max(2, barHeight * CGFloat(min(1, max(0, load)))))
                                }
                                .frame(height: barHeight)
                            }
                        }
                        .frame(width: available * CGFloat(group.loads.count) / CGFloat(total))
                    }
                }
            }
            .frame(height: barHeight)
            HStack(spacing: Self.groupGap) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(group.title)
                        .font(.system(size: Self.labelFontSize))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fanBarText("每核 CPU 使用率", "CPU usage per core"))
        .accessibilityValue(fractions.map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: ", "))
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}
