import FanBarShared
import SwiftUI

/// The popover's system material with a light or near-black tint; solid under Reduce Transparency.
struct PanelGlassBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = PanelPalette(colorScheme: scheme)
        // The popover already draws the system material; tint it rather than paint over it.
        reduceTransparency ? palette.surface : palette.materialTint
    }
}

/// How fast a fan is turning within its own range, said in words beside the number.
enum FanSpeedBand {
    /// Apple silicon Macs stop their fans entirely when cool; that is not "low speed".
    case stopped
    case low
    case medium
    case high

    init(rpm: Int, fraction: Double) {
        if rpm <= 0 {
            self = .stopped
        } else {
            self = fraction < 0.35 ? .low : fraction < 0.7 ? .medium : .high
        }
    }

    var title: String {
        switch self {
        case .stopped: fanBarText("已停转", "Stopped")
        case .low: fanBarText("低速运行", "Low speed")
        case .medium: fanBarText("中速运行", "Medium speed")
        case .high: fanBarText("高速运行", "High speed")
        }
    }
}

/// One fan: name and speed band, the RPM, and a read-only meter across its range.
struct PanelFanReadout: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    let fan: FanReading
    var isSingleFan = false
    @Environment(\.colorScheme) private var scheme

    private var fraction: Double {
        let span = Double(fan.maximumRPM - fan.minimumRPM)
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(fan.currentRPM - fan.minimumRPM) / span))
    }

    /// The meter runs from 0 to the maximum, so an idle fan at its floor still
    /// reads as turning instead of an empty bar.
    private func shareOfMaximum(_ rpm: Int) -> Double {
        guard fan.maximumRPM > 0 else { return 0 }
        return min(1, max(0, Double(rpm) / Double(fan.maximumRPM)))
    }

    var body: some View {
        let palette = PanelPalette(colorScheme: scheme)
        let band = FanSpeedBand(rpm: fan.currentRPM, fraction: fraction)
        let name = isSingleFan ? fanBarText("风扇", "Fan") : fanBarFormat("风扇 %d", "Fan %d", fan.index + 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                SpinningFanGlyph(rpm: fan.currentRPM)
                    .frame(width: 13, height: 13)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 6)
                Text(band.title)
                    .font(.system(size: 11, weight: band == .high ? .semibold : .regular))
                    .foregroundColor(band == .high ? palette.warmInk : palette.tertiaryText)
            }
            .foregroundColor(palette.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(FanBarNumberFormatter.grouped(fan.currentRPM))
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
                    .tracking(-0.5)
                    // A fan at the bottom of its range recedes; it comes forward as it speeds up.
                    .foregroundColor(band == .low || band == .stopped ? palette.secondaryText : .primary)
                Text("RPM")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(palette.tertiaryText)
            }

            FanRangeMeter(
                fraction: shareOfMaximum(fan.currentRPM),
                floor: shareOfMaximum(fan.minimumRPM),
                color: band == .high ? palette.warm : palette.accent,
                palette: palette
            )
            .frame(height: 4)
            .padding(.top, 4)

            HStack {
                Text(fanBarFormat("最低 %@", "Min %@", FanBarNumberFormatter.grouped(fan.minimumRPM)))
                Spacer(minLength: 6)
                Text(fanBarFormat("最高 %@", "Max %@", FanBarNumberFormatter.grouped(fan.maximumRPM)))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundColor(palette.tertiaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PanelLayout.columnInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(fanBarFormat(
            "%@ RPM，%@，范围 %@ 到 %@",
            "%@ RPM, %@, range %@ to %@",
            FanBarNumberFormatter.grouped(fan.currentRPM),
            band.title,
            FanBarNumberFormatter.grouped(fan.minimumRPM),
            FanBarNumberFormatter.grouped(fan.maximumRPM)
        ))
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}

/// A filled bar with no knob, so it never reads as a slider. A hairline marks
/// the fan's minimum, the speed it idles at under macOS control.
private struct FanRangeMeter: View {
    let fraction: Double
    let floor: Double
    let color: Color
    let palette: PanelPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                palette.well
                color.frame(width: proxy.size.width * CGFloat(fraction))
                if floor > 0, floor < 1 {
                    palette.tertiaryText
                        .frame(width: 1)
                        .offset(x: proxy.size.width * CGFloat(floor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
