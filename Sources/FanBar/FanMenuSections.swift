import AppKit
import FanBarShared
import SwiftUI

// MARK: - Tokens

enum PanelLayout {
    static let columnInset: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 12
    static let separatorWidth: CGFloat = 1
}

/// One flat material with shared separators; color is reserved for data and state.
struct PanelPalette {
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }

    private static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Solid fallback when Reduce Transparency is on.
    var surface: Color { isDark ? Self.rgb(0x161617) : .white }
    /// Tint laid over the popover's own material: light stays airy, dark reads near-black.
    var materialTint: Color { isDark ? Self.rgb(0x161617, 0.86) : Color.white.opacity(0.80) }
    /// Empty part of bars and meters.
    var well: Color { isDark ? Color.white.opacity(0.13) : Self.rgb(0x141E2D, 0.09) }
    /// Background of segmented controls and quiet notices.
    var track: Color { isDark ? Color.white.opacity(0.06) : Self.rgb(0x141E2D, 0.055) }
    /// The well while a borderless button is held down: about 1.6× the hover well.
    var pressedWell: Color { isDark ? Color.white.opacity(0.20) : Self.rgb(0x141E2D, 0.15) }
    var raised: Color { isDark ? Self.rgb(0x3A3A3C) : .white }
    var hairline: Color { isDark ? Color.white.opacity(0.1) : Self.rgb(0x1E2837, 0.12) }
    var secondaryText: Color { isDark ? Self.rgb(0xA8A8AD) : Self.rgb(0x5F6670) }
    var tertiaryText: Color { isDark ? Self.rgb(0x8E8E93) : Self.rgb(0x6E7581) }

    // Status: color says how much, never which. The three steps also differ in lightness.
    var accent: Color { isDark ? Self.rgb(0x4CC38A) : Self.rgb(0x1D7A57) }
    var warm: Color { isDark ? Self.rgb(0xF0A050) : Self.rgb(0xE08A2E) }
    /// Text in the warm state, dark enough to read on the panel.
    var warmInk: Color { isDark ? Self.rgb(0xF5B26B) : Self.rgb(0x9A4F0C) }
    var hot: Color { isDark ? Self.rgb(0xF07070) : Self.rgb(0xA82424) }

    // Series identity for the temperature chart; kept clear of green, orange, and red.
    var cpu: Color { isDark ? Self.rgb(0x7AA2FF) : Self.rgb(0x2F64D6) }
    var gpu: Color { isDark ? Self.rgb(0xB794F0) : Self.rgb(0x8456CF) }
    var ssd: Color { isDark ? Self.rgb(0x5BC8E8) : Self.rgb(0x0E8FB3) }
    /// Brighter than the SSD line it often sits on, so its dots stay visible.
    var battery: Color { isDark ? Self.rgb(0xD1D1D6) : Self.rgb(0x5F6670) }

    /// Reclaimable cache: memory macOS can hand back, so it never takes a status color.
    var memoryCache: Color { isDark ? Self.rgb(0x636366) : Self.rgb(0xBCC2CA) }

    func color(for level: ThermalLevel) -> Color {
        switch level {
        case .normal: accent
        case .warm: warm
        case .hot: hot
        }
    }
}

/// CPU/GPU share the configured alert threshold with notifications and CSV logs.
/// Storage and battery retain their lower, part-specific health limits.
enum ThermalPart: CaseIterable, Equatable {
    case cpu
    case gpu
    case ssd
    case battery

    var name: String {
        switch self {
        case .cpu: fanBarText("CPU 平均", "CPU average")
        case .gpu: "GPU"
        case .ssd: "SSD"
        case .battery: fanBarText("电池", "Battery")
        }
    }

    /// The header's calm line has room for a temperature but not a qualifier, so it reads
    /// "CPU 65°" (the average); the chart legend carries the qualified "CPU max" / "CPU avg".
    var headerName: String {
        self == .cpu ? "CPU" : name
    }

    /// Heat assessment uses the same average as notifications and the CSV log.
    var keyPath: KeyPath<ThermalReading, Double?> {
        switch self {
        case .cpu: \.cpuCelsius
        case .gpu: \.gpuCelsius
        case .ssd: \.ssdCelsius
        case .battery: \.batteryCelsius
        }
    }

    /// Leave a warm band below the configured chip alert, without raising the
    /// usual 85 °C warm boundary when the user raises the alert threshold.
    var warmThreshold: Double {
        switch self {
        case .cpu, .gpu: min(85, hotThreshold - 5)
        case .ssd: 65
        case .battery: 40
        }
    }

    var hotThreshold: Double {
        switch self {
        case .cpu, .gpu: ThermalAlertSettings.thresholdCelsius
        case .ssd: 75
        case .battery: 45
        }
    }
}

/// How urgent a reading is for its part: the only thing besides data that earns color.
enum ThermalLevel: Int, Comparable {
    case normal
    case warm
    case hot

    init(celsius: Double?, part: ThermalPart) {
        guard let celsius else {
            self = .normal
            return
        }
        self = celsius >= part.hotThreshold ? .hot : celsius >= part.warmThreshold ? .warm : .normal
    }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The reading the panel leads with: the part that most needs attention, or
/// the hottest one when every part is within its limits.
struct ThermalFocus: Equatable {
    var part: ThermalPart
    var celsius: Double

    var level: ThermalLevel { ThermalLevel(celsius: celsius, part: part) }

    /// True when the focus is an alert rather than simply the warmest part.
    var isAlert: Bool { level > .normal }

    static func from(_ reading: ThermalReading?) -> ThermalFocus? {
        guard let reading else { return nil }
        let readings = ThermalPart.allCases.compactMap { part in
            reading[keyPath: part.keyPath].map { ThermalFocus(part: part, celsius: $0) }
        }
        // Most urgent first; among equals, the one closest to its hot limit.
        let mostUrgent = readings.max { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level < rhs.level }
            return lhs.celsius / lhs.part.hotThreshold < rhs.celsius / rhs.part.hotThreshold
        }
        if let mostUrgent, mostUrgent.isAlert { return mostUrgent }
        // The battery runs far cooler than chips, so it never leads when all is normal.
        return readings.filter { $0.part != .battery }.max { $0.celsius < $1.celsius } ?? mostUrgent
    }
}

/// Lays out the header's status line in the width left beside the app icon and settings button.
/// Parts are joined with " · " on one line; when that does not fit, the line breaks before the
/// last part, so no language truncates the temperature, the controller or the restore countdown.
@MainActor
enum PanelHeaderStatus {
    static let fontSize: CGFloat = 11
    static let indicatorSpacing: CGFloat = 6
    static let separator = " · "

    /// Room for the status text beside the 32pt icon, the gaps, and the settings button
    /// (whose hover well hangs 6pt past the content edge), less the status indicator.
    static func textWidth(indicatorWidth: CGFloat) -> CGFloat {
        let content = FanMenu.panelWidth - FanMenu.padding * 2
        let beside = content - FanMenu.headerIconSize - FanMenu.headerSpacing * 3
            - FanMenu.headerSpacerMinimum - FanMenu.settingsButtonSize + FanMenu.settingsButtonOverhang
        return beside - indicatorWidth - indicatorSpacing
    }

    /// One line when the joined parts and the trailing control fit, else two.
    static func lines(
        _ parts: [String], weight: NSFont.Weight, trailingWidth: CGFloat, fitting width: CGFloat
    ) -> [String] {
        let joined = parts.joined(separator: separator)
        let trailing = trailingWidth > 0 ? trailingWidth + indicatorSpacing : 0
        guard parts.count > 1, measure(joined, weight: weight) + trailing > width else { return [joined] }
        return [parts.dropLast().joined(separator: separator), parts[parts.count - 1]]
    }

    /// Whether the trailing control still fits after the last line. An alert title is a single part
    /// that cannot break, so in manual mode the restore countdown moves to a line of its own instead.
    static func trailingFits(after lines: [String], weight: NSFont.Weight, trailingWidth: CGFloat,
                             fitting width: CGFloat) -> Bool {
        guard trailingWidth > 0, let last = lines.last else { return true }
        return measure(last, weight: weight) + indicatorSpacing + trailingWidth <= width
    }

    static func measure(_ text: String, weight: NSFont.Weight = .regular, monospacedDigits: Bool = false) -> CGFloat {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
            : NSFont.systemFont(ofSize: fontSize, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// A one-point rule in the panel's hairline color.
struct PanelDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(PanelPalette(colorScheme: colorScheme).hairline)
            .frame(height: PanelLayout.separatorWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Equal-width segments with a flat, bordered selection.
struct PanelSegmentedControl<ID: Hashable>: View {
    let options: [(id: ID, title: String)]
    let selection: ID?
    var compact = false
    var systemImage: (ID) -> String? = { _ in nil }
    let onSelect: (ID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var namespace

    var body: some View {
        let palette = PanelPalette(colorScheme: colorScheme)
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                segment(option, selected: option.id == selection, palette: palette)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                .fill(palette.track)
        )
    }

    private func segment(_ option: (id: ID, title: String), selected: Bool, palette: PanelPalette) -> some View {
        let radius: CGFloat = compact ? 5 : 7
        return Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: 4) {
                if let symbol = systemImage(option.id) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                }
                Text(option.title)
            }
                .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .primary : palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, compact ? 2 : 8)
                .padding(.horizontal, compact ? 7 : 4)
                .frame(maxWidth: compact ? nil : .infinity)
                .background(
                    Group {
                        if selected {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(palette.raised)
                                .shadow(color: Color.black.opacity(0.10), radius: 1, y: 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Borderless panel buttons: the well shows on hover and deepens the instant the button is
/// pressed, easing back on release. No scale; macOS acknowledges a press by darkening.
struct PanelWellButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        PanelPressBody(configuration: configuration) { isPressed, palette in
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isPressed ? palette.pressedWell : isHovered ? palette.well : Color.clear)
                )
        }
    }
}

/// Filled buttons and whole-cell buttons dim while held, then ease back.
struct PanelDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelPressBody(configuration: configuration) { isPressed, _ in
            configuration.label.opacity(isPressed ? 0.75 : 1)
        }
    }
}

/// Shared timing: instant on press, 0.1 s ease-out on release, instant when panel animation is off.
private struct PanelPressBody<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let content: (Bool, PanelPalette) -> Content

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PanelAnimationPreferences.preferenceKey) private var panelAnimationEnabled = true

    var body: some View {
        content(configuration.isPressed, PanelPalette(colorScheme: colorScheme))
            .animation(
                configuration.isPressed || !panelAnimationEnabled ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

// MARK: - Fan glyph

private struct PanelVisibleKey: EnvironmentKey {
    /// Views hosted anywhere other than the menu bar popover (settings,
    /// previews) are visible whenever they exist.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the menu bar popover that hosts this view is closed.
    var isPanelVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

/// Turns at a speed derived from RPM, only while the panel is on screen and motion is allowed.
struct SpinningFanGlyph: View {
    let rpm: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPanelVisible) private var isPanelVisible
    @AppStorage(PanelAnimationPreferences.preferenceKey)
    private var panelAnimationEnabled = true
    @State private var isSpinning = false

    private var shouldSpin: Bool {
        rpm > 0 && isPanelVisible && panelAnimationEnabled && !reduceMotion
    }

    /// One turn every 40 / (RPM / 60) seconds, so faster fans visibly turn faster.
    private var period: Double {
        min(max(60 / Double(max(rpm, 1)) * 40, 0.4), 4)
    }

    var body: some View {
        // Fit the symbol to the caller's frame: at a fixed point size it is wider than
        // the frame and its overflow gets clipped by the fan row's scroll view.
        glyph
            .padding(1)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(
                isSpinning ? .linear(duration: period).repeatForever(autoreverses: false) : .default,
                value: isSpinning
            )
            .onAppear { isSpinning = shouldSpin }
            .onChange(of: shouldSpin) { isSpinning = $0 }
            .accessibilityHidden(true)
    }

    // The old check sent macOS 11-12 to "fan", which only exists from macOS 14.
    private var glyph: some View {
        Image(systemName: FanBarSymbols.fanBlades)
            .resizable()
            .scaledToFit()
    }
}

// MARK: - Formatting

/// Byte formatting tuned for the narrow panel.
enum PanelByteFormat {
    static let gibibyte = 1_073_741_824.0
    static let gigabyte = 1_000_000_000.0

    /// Short size such as "0 B", "512 MB", or "3.7 GB".
    static func compact(_ bytes: UInt64, unit: Double = gibibyte) -> String {
        let value = Double(bytes)
        if bytes == 0 { return "0 B" }
        if value >= unit { return String(format: "%.1f GB", value / unit) }
        return String(format: "%.0f MB", value / (unit / 1024))
    }
}
