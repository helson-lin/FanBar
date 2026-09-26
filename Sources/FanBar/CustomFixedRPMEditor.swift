import FanBarShared
import SwiftUI

/// Inline editor for a hand-entered fixed RPM. Shows the hardware range up
/// front and only enables Apply for values the fans can actually hold.
struct CustomFixedRPMEditor: View {
    let range: ClosedRange<Int>
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(
        range: ClosedRange<Int>,
        initialRPM: Int?,
        onApply: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.range = range
        self.onApply = onApply
        self.onCancel = onCancel
        let start = initialRPM.map { min(max($0, range.lowerBound), range.upperBound) }
            ?? Self.rounded(midpointOf: range)
        _text = State(initialValue: String(start))
    }

    private var parsedRPM: Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    private var validRPM: Int? {
        guard let rpm = parsedRPM, range.contains(rpm) else { return nil }
        return rpm
    }

    private var rangeText: String {
        fanBarFormat(
            "可输入 %d–%d RPM",
            "Enter %d–%d RPM",
            range.lowerBound,
            range.upperBound
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 76)
                    .accessibilityLabel(fanBarText("自定义转速", "Custom RPM"))
                    .accessibilityHint(rangeText)

                Stepper(
                    fanBarText("自定义转速", "Custom RPM"),
                    onIncrement: { step(by: 100) },
                    onDecrement: { step(by: -100) }
                )
                .labelsHidden()

                Text("RPM")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 4)

                Button(fanBarText("取消", "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(fanBarText("应用", "Apply"), action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validRPM == nil)
            }
            .controlSize(.small)

            Label(statusText, systemImage: validRPM == nil ? "exclamationmark.triangle" : "info.circle")
                .font(.caption)
                .foregroundColor(validRPM == nil ? .orange : .secondary)
        }
        .padding(.horizontal, 4)
    }

    /// Always shows the range; the icon and wording (not only color) change
    /// when the entry is invalid.
    private var statusText: String {
        guard parsedRPM != nil else {
            return fanBarFormat("请输入整数，%@", "Enter a whole number. %@", rangeText)
        }
        guard validRPM != nil else {
            return fanBarFormat("超出硬件范围，%@", "Outside the hardware range. %@", rangeText)
        }
        return rangeText
    }

    private func step(by delta: Int) {
        let base = parsedRPM ?? range.lowerBound
        let next = min(max(base + delta, range.lowerBound), range.upperBound)
        text = String(next)
    }

    private func apply() {
        guard let rpm = validRPM else { return }
        onApply(rpm)
    }

    private static func rounded(midpointOf range: ClosedRange<Int>) -> Int {
        let mid = (range.lowerBound + range.upperBound) / 2
        return min(max((mid / 100) * 100, range.lowerBound), range.upperBound)
    }
}
