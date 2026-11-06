import AppKit
import FanBarShared
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case cpuTemperature
    case fanSpeed
    case temperatureAndFanSpeed
    case temperatureOverFanSpeed

    static let preferenceKey = "fanbar.menuBarDisplayMode"
    static let defaultMode = MenuBarDisplayMode.iconOnly

    var id: String { rawValue }

    /// Two lines must fit the 22pt menu bar, so the stacked mode uses the
    /// compact size system extras use for two-row readouts.
    static let stackedFontSize: CGFloat = 9

    var title: String {
        switch self {
        case .iconOnly: fanBarText("仅图标", "Icon only")
        case .cpuTemperature: fanBarText("CPU 最高温度", "CPU highest temperature")
        case .fanSpeed: fanBarText("风扇转速", "Fan speed")
        case .temperatureAndFanSpeed: fanBarText("温度与转速", "Temperature + fan speed")
        case .temperatureOverFanSpeed: fanBarText("温度与转速（上下排列）", "Temperature over fan speed")
        }
    }

    var detail: String {
        switch self {
        case .iconOnly: fanBarText("保持菜单栏最简洁，只显示当前控制模式图标。", "Keep the menu bar minimal with only the current mode icon.")
        case .cpuTemperature: fanBarText("显示当前 CPU 最高温度，适合快速观察负载变化。", "Show the highest CPU temperature for a quick load check.")
        case .fanSpeed: fanBarText("显示全部风扇的平均 RPM，并使用千位分隔。", "Show the average RPM across all fans with grouping separators.")
        case .temperatureAndFanSpeed: fanBarText("同时显示 CPU 最高温度和平均风扇转速。", "Show highest CPU temperature and average fan speed together.")
        case .temperatureOverFanSpeed: fanBarText("温度在上、转速在下，占用更少的菜单栏宽度。", "Stack temperature above fan speed to take less menu bar width.")
        }
    }
}

/// The single source of truth for both the real menu bar label and its settings preview.
struct MenuBarStatusLabel: View {
    @ObservedObject var controller: FanController
    let displayMode: MenuBarDisplayMode
    @AppStorage(MenuBarIconStyle.preferenceKey)
    private var iconStyleRawValue = MenuBarIconStyle.defaultStyle.rawValue

    private var iconStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: iconStyleRawValue) ?? .defaultStyle
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: iconStyle.image(isManual: controller.isManualStatus))
                .renderingMode(.template)
                .foregroundColor(.primary)

            if displayMode == .temperatureOverFanSpeed {
                VStack(alignment: .leading, spacing: -1) {
                    Text(temperatureText)
                    Text(fanSpeedText)
                }
                .font(.system(size: MenuBarDisplayMode.stackedFontSize, weight: .medium).monospacedDigit())
            } else if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .accessibilityLabel(accessibilityText)
        .help(controller.temperatureHistory.last?.cpuTemperatureSummary ?? "FanBar")
    }

    private var statusText: String? {
        switch displayMode {
        case .iconOnly:
            nil
        case .cpuTemperature:
            temperatureText
        case .fanSpeed:
            fanSpeedText
        case .temperatureAndFanSpeed, .temperatureOverFanSpeed:
            "\(temperatureText) · \(fanSpeedText)"
        }
    }

    private var temperatureText: String {
        guard let temperature = controller.temperatureHistory.last?.cpuDisplayCelsius else { return "—°" }
        return "\(Int(temperature.rounded()))°"
    }

    private var fanSpeedText: String {
        guard !controller.fans.isEmpty else { return "— RPM" }
        let total = controller.fans.map(\.currentRPM).reduce(0, +)
        let average = Int((Double(total) / Double(controller.fans.count)).rounded())
        return FanBarNumberFormatter.grouped(average)
    }

    private var accessibilityText: String {
        guard let statusText else {
            return fanBarFormat(
                "FanBar，%@模式",
                "FanBar, %@ mode",
                controller.mode == .automatic
                    ? fanBarText("系统", "automatic")
                    : fanBarText("手动", "manual")
            )
        }
        return fanBarFormat("FanBar，%@", "FanBar, %@", statusText)
    }
}

/// Optional independent status items. Missing preferences deliberately default to off.
enum MenuBarResource: String, CaseIterable {
    case cpu, memory, gpu

    var preferenceKey: String { "fanbar.menuBarResource.\(rawValue)" }
    var stylePreferenceKey: String { "\(preferenceKey).style" }
    /// A shared template glyph keeps the settings preview and status item identical.
    var icon: NSImage {
        let resource = self
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            func line(_ a: NSPoint, _ b: NSPoint) {
                let path = NSBezierPath()
                path.lineWidth = 1.1
                path.lineCapStyle = .round
                path.move(to: a)
                path.line(to: b)
                path.stroke()
            }
            let rect: NSRect = resource == .memory
                ? NSRect(x: 1.5, y: 4.0, width: 11, height: 6)
                : NSRect(x: 3, y: 3, width: 8, height: 8)
            if resource != .gpu {
                let outline = NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6)
                outline.lineWidth = 1.1
                outline.stroke()
            }
            switch resource {
            case .cpu:
                for position in [5.0, 9.0] {
                    line(NSPoint(x: position, y: 1.5), NSPoint(x: position, y: 3))
                    line(NSPoint(x: position, y: 11), NSPoint(x: position, y: 12.5))
                    line(NSPoint(x: 1.5, y: position), NSPoint(x: 3, y: position))
                    line(NSPoint(x: 11, y: position), NSPoint(x: 12.5, y: position))
                }
                NSBezierPath(roundedRect: NSRect(x: 5.25, y: 5.25, width: 3.5, height: 3.5), xRadius: 0.8, yRadius: 0.8).fill()
            case .memory:
                for x in [4.5, 7.0, 9.5] {
                    line(NSPoint(x: x, y: 6), NSPoint(x: x, y: 8))
                }
            case .gpu:
                // A horizontal expansion card: bracket, vents, fan and contacts.
                // The off-centre fan avoids a camera-like silhouette.
                let board = NSBezierPath(roundedRect: NSRect(x: 2, y: 4, width: 10, height: 6), xRadius: 0.7, yRadius: 0.7)
                board.lineWidth = 1.1
                board.stroke()
                line(NSPoint(x: 1, y: 3), NSPoint(x: 1, y: 11))
                line(NSPoint(x: 1, y: 4), NSPoint(x: 2, y: 4))
                line(NSPoint(x: 1, y: 10), NSPoint(x: 2, y: 10))
                for x in [4.0, 6.0, 8.0, 10.0] {
                    line(NSPoint(x: x, y: 3), NSPoint(x: x, y: 4))
                }
                line(NSPoint(x: 3.8, y: 5.7), NSPoint(x: 3.8, y: 8.3))
                line(NSPoint(x: 5.5, y: 5.7), NSPoint(x: 5.5, y: 8.3))
                let fan = NSBezierPath(ovalIn: NSRect(x: 7, y: 5.25, width: 3.5, height: 3.5))
                fan.lineWidth = 1.1
                fan.stroke()
                NSBezierPath(ovalIn: NSRect(x: 8.3, y: 6.55, width: 0.9, height: 0.9)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    var currentStyle: MenuBarResourceStyle {
        guard let saved = UserDefaults.standard.string(forKey: stylePreferenceKey) else { return .icon }
        return MenuBarResourceStyle(rawValue: saved) ?? .label
    }
    var label: String {
        switch self { case .cpu: "CPU"; case .memory: "MEM"; case .gpu: "GPU" }
    }
    var title: String {
        switch self {
        case .cpu: fanBarText("CPU 使用率", "CPU usage")
        case .memory: fanBarText("内存使用率", "Memory usage")
        case .gpu: fanBarText("GPU 使用率", "GPU usage")
        }
    }
    var panelResource: PanelResourceList.Resource {
        switch self { case .cpu: .cpu; case .memory: .memory; case .gpu: .gpu }
    }
    func text(for usage: SystemUsage, style: MenuBarResourceStyle = .label) -> String {
        let value = valueText(for: usage)
        return style == .label ? "\(label) \(value)" : value
    }
    private func valueText(for usage: SystemUsage) -> String {
        let fraction: Double?
        switch self { case .cpu: fraction = usage.cpuFraction; case .memory: fraction = usage.memoryFraction; case .gpu: fraction = usage.gpuFraction }
        guard let value = fraction, value.isFinite else { return "—" }
        return "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

/// Per-resource presentation. Explicitly saved choices are preserved.
enum MenuBarResourceStyle: String, CaseIterable, Identifiable {
    case label, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .label: fanBarText("名称与数值", "Label and value")
        case .icon: fanBarText("图标与数值", "Icon and value")
        }
    }
}
