import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case cpuTemperature
    case fanSpeed
    case temperatureAndFanSpeed

    static let preferenceKey = "fanbar.menuBarDisplayMode"
    static let defaultMode = MenuBarDisplayMode.iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: "仅图标"
        case .cpuTemperature: "CPU 温度"
        case .fanSpeed: "风扇转速"
        case .temperatureAndFanSpeed: "温度与转速"
        }
    }

    var detail: String {
        switch self {
        case .iconOnly: "保持菜单栏最简洁，只显示当前控制模式图标。"
        case .cpuTemperature: "显示当前 CPU 温度，适合快速观察负载变化。"
        case .fanSpeed: "显示全部风扇的平均 RPM，并使用紧凑格式。"
        case .temperatureAndFanSpeed: "同时显示 CPU 温度和平均风扇转速。"
        }
    }
}

/// The single source of truth for both the real menu bar label and its settings preview.
struct MenuBarStatusLabel: View {
    @ObservedObject var controller: FanController
    let displayMode: MenuBarDisplayMode

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: controller.statusIcon)
                .symbolRenderingMode(.hierarchical)

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
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
        case .temperatureAndFanSpeed:
            "\(temperatureText) · \(fanSpeedText)"
        }
    }

    private var temperatureText: String {
        guard let temperature = controller.temperatureHistory.last?.cpuCelsius else { return "—°" }
        return "\(Int(temperature.rounded()))°"
    }

    private var fanSpeedText: String {
        guard !controller.fans.isEmpty else { return "— RPM" }
        let average = controller.fans.map(\.currentRPM).reduce(0, +) / controller.fans.count
        if average >= 1_000 {
            return String(format: "%.1fK", Double(average) / 1_000)
        }
        return "\(average)"
    }

    private var accessibilityText: String {
        guard let statusText else { return "FanBar，\(controller.mode == .automatic ? "自动" : "手动")模式" }
        return "FanBar，\(statusText)"
    }
}
