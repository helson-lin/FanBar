import FanBarShared
import Foundation

/// Human-readable rendering of app replies; `--json` bypasses all of this.
enum CLIOutput {
    static func status(_ response: FanBarCLIResponse) -> String {
        guard let status = response.status else { return response.message }
        var lines = ["Mode:    \(response.message)"]
        if let percent = status.curveOutputPercent {
            lines.append("Curve:   \(Int(percent.rounded()))% output")
        }
        if !status.helperEnabled {
            lines.append("Helper:  not enabled. Approve FanBar's control service to change fan modes.")
        }
        for fan in status.fans {
            lines.append(
                "Fan \(fan.index + 1):   \(grouped(fan.currentRPM)) RPM " +
                    "(\(grouped(fan.minimumRPM))–\(grouped(fan.maximumRPM)))"
            )
        }
        lines.append(contentsOf: temperatureLines(status))
        return lines.joined(separator: "\n")
    }

    static func temps(_ response: FanBarCLIResponse) -> String {
        guard let status = response.status else { return response.message }
        let lines = temperatureLines(status)
        return lines.isEmpty ? "No temperature readings yet." : lines.joined(separator: "\n")
    }

    static func presets(_ response: FanBarCLIResponse) -> String {
        let presets = response.presets ?? []
        let width = presets.map(\.key.count).max() ?? 0
        return presets.map { preset in
            let marker = preset.selected ? "*" : " "
            // Custom presets have only their name; padding it would leave trailing spaces.
            guard preset.builtIn, preset.name != preset.key else { return "\(marker) \(preset.key)" }
            let key = preset.key.padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(marker) \(key)  \(preset.name)"
        }.joined(separator: "\n")
    }

    static func json(_ response: FanBarCLIResponse) -> String {
        let encoder = FanBarCLIContract.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(response),
              let text = String(bytes: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func temperatureLines(_ status: FanBarCLIStatus) -> [String] {
        [("CPU", status.cpuCelsius), ("GPU", status.gpuCelsius), ("SSD", status.ssdCelsius)]
            .compactMap { label, value in
                value.map { String(format: "%@:     %.1f °C", label, $0) }
            }
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
