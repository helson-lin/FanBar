import FanBarShared
import SwiftUI

/// Inline editor for a hand-entered fixed RPM. A slider covers the hardware
/// range for quick coarse moves; the field takes an exact value. Apply is only
/// enabled for values the fans can actually hold.
struct CustomFixedRPMEditor: View {
    let range: ClosedRange<Int>
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String

    /// Slider moves snap to this step; typed values can be any whole number.
    private static let sliderStep = 50

    init(
        range: ClosedRange<Int>,
        initialRPM: Int?,
        onApply: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.range = range
        self.onApply = onApply
        self.onCancel = onCancel
        let start = initialRPM.map { Self.clamped($0, in: range) }
            ?? Self.snapped((range.lowerBound + range.upperBound) / 2, in: range)
        _text = State(initialValue: String(start))
    }

    /// Accepts grouped input such as "3,400".
    private var parsedRPM: Int? {
        Int(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    private var validRPM: Int? {
        guard let rpm = parsedRPM, range.contains(rpm) else { return nil }
        return rpm
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                Double(Self.clamped(parsedRPM ?? range.lowerBound, in: range))
            },
            set: { text = String(Self.snapped(Int($0.rounded()), in: range)) }
        )
    }

    private var rangeText: String {
        fanBarFormat(
            "可输入 %@–%@ RPM",
            "Enter %@–%@ RPM",
            FanBarNumberFormatter.grouped(range.lowerBound),
            FanBarNumberFormatter.grouped(range.upperBound)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(fanBarText("自定义转速", "Custom RPM"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer(minLength: 8)

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .frame(width: 64)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        // Border only when the entry needs attention.
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.orange.opacity(validRPM == nil ? 0.8 : 0), lineWidth: 1)
                    )
                    .accessibilityLabel(fanBarText("自定义转速", "Custom RPM"))
                    .accessibilityHint(rangeText)

                Text("RPM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Slider(value: sliderValue, in: Double(range.lowerBound)...Double(range.upperBound)) {
                Text(fanBarText("自定义转速", "Custom RPM"))
            } minimumValueLabel: {
                rangeLabel(range.lowerBound)
            } maximumValueLabel: {
                rangeLabel(range.upperBound)
            }
            .labelsHidden()
            .controlSize(.small)

            HStack(spacing: 8) {
                // The slider ends already show the range; only call out an
                // invalid entry here.
                if validRPM == nil {
                    Label(statusText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(fanBarText("取消", "Cancel"), action: onCancel)
                    .buttonStyle(EditorButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)
                Button(action: apply) {
                    Label(fanBarText("应用", "Apply"), systemImage: "checkmark")
                }
                .buttonStyle(EditorButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .focusable(false)
                .disabled(validRPM == nil)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func rangeLabel(_ rpm: Int) -> some View {
        Text(FanBarNumberFormatter.grouped(rpm))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
    }

    /// The icon and wording, not only the color, mark an invalid entry.
    private var statusText: String {
        parsedRPM == nil
            ? fanBarText("请输入整数", "Enter a whole number")
            : fanBarText("超出硬件范围", "Outside the hardware range")
    }

    private func apply() {
        guard let rpm = validRPM else { return }
        onApply(rpm)
    }

    /// Snaps to the slider step while keeping both hardware ends reachable.
    private static func snapped(_ rpm: Int, in range: ClosedRange<Int>) -> Int {
        let step = sliderStep
        let snapped = Int((Double(rpm) / Double(step)).rounded()) * step
        return clamped(snapped, in: range)
    }

    private static func clamped(_ rpm: Int, in range: ClosedRange<Int>) -> Int {
        min(max(rpm, range.lowerBound), range.upperBound)
    }
}

/// Compact capsule buttons matching the popover's own controls: a filled
/// accent capsule for the primary action, a quiet text button for the
/// secondary one that only gains a fill on hover or press.
private struct EditorButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        EditorButton(configuration: configuration, prominent: prominent)
    }

    private struct EditorButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foreground)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            if prominent {
                return isEnabled ? .white : .secondary
            }
            return isHovered ? .primary : .secondary
        }

        private var background: Color {
            if prominent {
                return isEnabled ? .accentColor : Color.primary.opacity(0.06)
            }
            return Color.primary.opacity(isHovered || configuration.isPressed ? 0.07 : 0)
        }
    }
}
