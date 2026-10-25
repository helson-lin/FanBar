import AppKit
import FanBarShared
import Foundation

/// Decodes SMC power keys such as `PSTR` (whole-system power, in watts).
/// Apple Silicon reports a native-endian `flt `; Intel generations use
/// big-endian fixed point (`spXY` signed, `fpXY` unsigned, where the last hex
/// digit is the number of fraction bits) or plain unsigned integers. Any other
/// type is unknown here and decodes to nil instead of a guessed value.
enum SMCPowerDecoder {
    static func watts(dataType: String, bytes: [UInt8]) -> Double? {
        switch dataType {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 ":
            return bytes.first.map { Double($0) }
        case "ui16":
            return bigEndian(bytes, width: 2).map { Double($0) }
        case "ui32":
            return bigEndian(bytes, width: 4).map { Double($0) }
        case "ioft":
            // 48.16 fixed point, native-endian, on Apple Silicon.
            guard bytes.count >= 8 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }) / 65536
        default:
            return fixedPoint(dataType: dataType, bytes: bytes)
        }
    }

    /// The four-character type code AppleSMC returns, e.g. `0x666c7420` → "flt ".
    static func typeName(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static func bigEndian(_ bytes: [UInt8], width: Int) -> UInt64? {
        guard bytes.count >= width else { return nil }
        return bytes.prefix(width).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    /// `sp96` is 1 sign, 9 integer and 6 fraction bits; `fpe2` is 14 integer
    /// and 2 fraction bits. A code whose bits do not add up to 16 is rejected.
    private static func fixedPoint(dataType: String, bytes: [UInt8]) -> Double? {
        let code = Array(dataType)
        guard code.count == 4,
              let integer = Int(String(code[2]), radix: 16),
              let fraction = Int(String(code[3]), radix: 16),
              let raw = bigEndian(bytes, width: 2) else { return nil }
        let scale = Double(1 << fraction)
        switch String(code[0...1]) {
        case "sp" where integer + fraction == 15:
            return Double(Int16(bitPattern: UInt16(raw))) / scale
        case "fp" where integer + fraction == 16:
            return Double(raw) / scale
        default:
            return nil
        }
    }
}

/// The whole-system power shown after the Temperature heading.
struct SystemPowerReadout: Equatable {
    /// No Mac idles at 0 W, and a reading above 500 W is a misdecoded key
    /// rather than a measurement; neither is shown.
    static let plausibleWatts: ClosedRange<Double> = 0.5...500

    let watts: Int

    init?(watts: Double?) {
        guard let watts = Self.plausible(watts) else { return nil }
        self.watts = Int(watts.rounded())
    }

    /// Nil unless the value is finite and in range, so the history never
    /// stores a value JSON cannot encode or the panel cannot show.
    static func plausible(_ watts: Double?) -> Double? {
        guard let watts, watts.isFinite, plausibleWatts.contains(watts) else { return nil }
        return watts
    }

    static var title: String { fanBarText("整机功耗", "Power") }

    static var help: String {
        fanBarText(
            "整机功耗，来自系统管理控制器，每 2 秒更新",
            "Whole-system power from the System Management Controller, updated every 2 seconds"
        )
    }

    var valueText: String { fanBarFormat("%d W", "%d W", watts) }

    var accessibilityLabel: String { fanBarFormat("整机功耗 %d 瓦", "Power %d watts", watts) }
}

/// Paces reads of an SMC key that may not exist on this Mac. A missing or
/// undecodable key is asked again only after `retryInterval`, so Macs without
/// it do not pay for a failed SMC call on every refresh, while a key that
/// is absent only right after wake comes back on its own.
struct SMCOptionalKeyPacer {
    let retryInterval: TimeInterval
    private(set) var missingSince: Date?

    init(retryInterval: TimeInterval) {
        self.retryInterval = retryInterval
    }

    func shouldRead(at date: Date) -> Bool {
        guard let missingSince else { return true }
        return date.timeIntervalSince(missingSince) >= retryInterval
    }

    mutating func record(found: Bool, at date: Date) {
        missingSince = found ? nil : date
    }
}

extension SystemPowerReadout {
    /// A stale sample is not a current reading: history restored at launch can
    /// be minutes old, and the panel only shows what the Mac draws now.
    static let maximumSampleAge: TimeInterval = 10

    static func current(from samples: [ThermalReading], now: Date = Date()) -> SystemPowerReadout? {
        guard let latest = samples.last,
              now.timeIntervalSince(latest.sampledAt) <= maximumSampleAge else { return nil }
        return SystemPowerReadout(watts: latest.systemWatts)
    }
}

/// Fits the power readout into the Temperature heading. `ViewThatFits` needs
/// macOS 13 and the app supports macOS 11, so the heading measures its own text.
@MainActor
enum TemperatureHeadingLayout {
    static let headingFontSize: CGFloat = 12
    static let readoutFontSize: CGFloat = 11
    static let readoutLeading: CGFloat = 8
    static let titleSpacing: CGFloat = 4
    static let minimumGap: CGFloat = 8

    /// Whether "Power 38 W" fits; when it does not, only "38 W" is shown so the
    /// heading and the range control never move.
    static func showsPowerTitle(
        heading: String, rangeTitles: [String], powerTitle: String, valueText: String
    ) -> Bool {
        let full = measure(powerTitle, size: readoutFontSize) + titleSpacing + valueWidth(valueText)
        return full <= room(heading: heading, rangeTitles: rangeTitles)
    }

    /// The width left for the readout between the heading and the range control.
    static func room(heading: String, rangeTitles: [String]) -> CGFloat {
        let content = FanMenu.panelWidth - FanMenu.padding * 2
        return content - measure(heading, size: headingFontSize, weight: .semibold)
            - readoutLeading - minimumGap - compactSegmentedWidth(rangeTitles)
    }

    static func valueWidth(_ valueText: String) -> CGFloat {
        measure(valueText, size: readoutFontSize, weight: .semibold, monospacedDigits: true)
    }

    /// Mirrors `PanelSegmentedControl(compact: true)`: 7pt side padding per
    /// segment, 2pt between segments and around the track. Every title is
    /// measured semibold, the width it takes when selected.
    static func compactSegmentedWidth(_ titles: [String]) -> CGFloat {
        let segments = titles.map { measure($0, size: readoutFontSize, weight: .semibold) + 14 }
        return segments.reduce(0, +) + CGFloat(max(titles.count - 1, 0)) * 2 + 4
    }

    static func measure(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular, monospacedDigits: Bool = false
    ) -> CGFloat {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
