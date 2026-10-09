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
        case .cpuTemperature: fanBarText("CPU 温度", "CPU temperature")
        case .fanSpeed: fanBarText("风扇转速", "Fan speed")
        case .temperatureAndFanSpeed: fanBarText("温度与转速", "Temperature + fan speed")
        case .temperatureOverFanSpeed: fanBarText("温度与转速（上下排列）", "Temperature over fan speed")
        }
    }

    var detail: String {
        switch self {
        case .iconOnly: fanBarText("保持菜单栏最简洁，只显示当前控制模式图标。", "Keep the menu bar minimal with only the current mode icon.")
        case .cpuTemperature: fanBarText("显示当前 CPU 温度，适合快速观察负载变化。", "Show the current CPU temperature for a quick load check.")
        case .fanSpeed: fanBarText("显示全部风扇的平均 RPM，并使用千位分隔。", "Show the average RPM across all fans with grouping separators.")
        case .temperatureAndFanSpeed: fanBarText("同时显示 CPU 温度和平均风扇转速。", "Show CPU temperature and average fan speed together.")
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
        guard let temperature = controller.temperatureHistory.last?.cpuCelsius else { return "—°" }
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
