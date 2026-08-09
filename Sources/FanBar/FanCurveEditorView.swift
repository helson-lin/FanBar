import FanBarShared
import SwiftUI

/// Settings pane fragment: preview + presets + sensor + editable points.
struct FanCurveEditorView: View {
    @ObservedObject var controller: FanController

    private static let integerFieldFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 100
        return formatter
    }()

    private var profile: FanCurveProfile { controller.curveProfile }

    private var selectedBuiltIn: FanCurveProfile.BuiltIn? {
        profile.matchingBuiltIn()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(fanBarText("智能温控曲线", "Smart cooling curve"))

            settingsCard {
                FanCurvePreview(
                    profile: profile,
                    currentCelsius: controller.curveTemperatureCelsius,
                    currentFraction: controller.curveOutputFraction
                )
                .frame(height: 140)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                rowDivider

                HStack {
                    Text(fanBarText("预设", "Presets"))
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ForEach(FanCurveProfile.BuiltIn.allCases) { builtIn in
                            Button(builtIn.title) {
                                controller.applyCurveBuiltIn(builtIn)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .foregroundColor(
                                selectedBuiltIn == builtIn ? Color.accentColor : Color.secondary
                            )
                            .font(
                                .system(
                                    size: 11,
                                    weight: selectedBuiltIn == builtIn ? .semibold : .regular
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                rowDivider

                HStack {
                    Text(fanBarText("温度来源", "Temperature source"))
                    Spacer(minLength: 12)
                    Picker(
                        "",
                        selection: Binding(
                            get: { profile.sensor },
                            set: { controller.setCurveSensor($0) }
                        )
                    ) {
                        ForEach(FanCurveSensor.allCases) { sensor in
                            Text(sensor.title).tag(sensor)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                rowDivider

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(fanBarText("温度", "Temp"))
                            .frame(width: 72, alignment: .leading)
                        Text(fanBarText("转速", "Speed"))
                            .frame(width: 72, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ForEach(profile.points) { point in
                        curvePointRow(point)
                    }

                    HStack(spacing: 8) {
                        Button {
                            controller.addCurvePoint()
                        } label: {
                            Label(
                                fanBarText("添加锚点", "Add point"),
                                systemImage: "plus.circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(profile.points.count >= FanCurveProfile.maximumPointCount)

                        Spacer()

                        Text(fanBarFormat(
                            "%d / %d",
                            "%d / %d",
                            profile.points.count,
                            FanCurveProfile.maximumPointCount
                        ))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            sectionFooter(fanBarText(
                "纵轴为每台风扇最大转速的百分比（30%–100%）。智能温控开启时，修改会立即生效。",
                "The Y-axis is each fan's maximum RPM percentage (30%–100%). Changes apply immediately while smart cooling is on."
            ))
        }
    }

    private func curvePointRow(_ point: FanCurvePoint) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                TextField(
                    "",
                    value: Binding(
                        get: { Int(point.celsius.rounded()) },
                        set: { controller.updateCurvePoint(id: point.id, celsius: Double($0)) }
                    ),
                    formatter: Self.integerFieldFormatter
                )
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                Text("°C")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            HStack(spacing: 2) {
                TextField(
                    "",
                    value: Binding(
                        get: { Int((point.fraction * 100).rounded()) },
                        set: {
                            controller.updateCurvePoint(
                                id: point.id,
                                fraction: Float($0) / 100
                            )
                        }
                    ),
                    formatter: Self.integerFieldFormatter
                )
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                Text("%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            Spacer()

            Button {
                controller.removeCurvePoint(id: point.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(profile.points.count <= FanCurveProfile.minimumPointCount)
            .help(fanBarText("删除锚点", "Remove point"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Local chrome (mirrors settings cards)

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 4)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(macOS 12.0, *) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 12)
    }
}

// MARK: - Curve preview

struct FanCurvePreview: View {
    let profile: FanCurveProfile
    var currentCelsius: Double?
    var currentFraction: Float?

    private let temperatureRange = FanCurveProfile.minimumCelsius...FanCurveProfile.maximumCelsius
    private let fractionRange = Double(FanCurveProfile.minimumFraction)...Double(FanCurveProfile.maximumFraction)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                grid(in: size)

                Path { path in
                    let points = samplePoints(in: size)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                ForEach(profile.points) { point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(position(celsius: point.celsius, fraction: point.fraction, in: size))
                }

                if let currentCelsius, let currentFraction {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                        .background(Circle().fill(Color.primary.opacity(0.15)))
                        .frame(width: 10, height: 10)
                        .position(
                            position(
                                celsius: currentCelsius,
                                fraction: currentFraction,
                                in: size
                            )
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fanBarText("温控曲线预览", "Cooling curve preview"))
    }

    private func grid(in size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
            Path { path in
                for step in 0...4 {
                    let y = size.height * CGFloat(step) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    let x = size.width * CGFloat(step) / 4
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)

            VStack {
                HStack {
                    Text("100%")
                    Spacer()
                    Text("\(Int(temperatureRange.upperBound))°C")
                }
                Spacer()
                HStack {
                    Text("30%")
                    Spacer()
                    Text("\(Int(temperatureRange.lowerBound))°C")
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(4)
        }
    }

    private func samplePoints(in size: CGSize) -> [CGPoint] {
        let steps = 40
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let celsius = temperatureRange.lowerBound
                + (temperatureRange.upperBound - temperatureRange.lowerBound) * t
            let fraction = profile.fraction(at: celsius)
            return position(celsius: celsius, fraction: fraction, in: size)
        }
    }

    private func position(celsius: Double, fraction: Float, in size: CGSize) -> CGPoint {
        let clampedT = min(max(celsius, temperatureRange.lowerBound), temperatureRange.upperBound)
        let clampedF = min(
            max(Double(fraction), fractionRange.lowerBound),
            fractionRange.upperBound
        )
        let x = CGFloat(
            (clampedT - temperatureRange.lowerBound)
                / (temperatureRange.upperBound - temperatureRange.lowerBound)
        ) * size.width
        let y = size.height - CGFloat(
            (clampedF - fractionRange.lowerBound)
                / (fractionRange.upperBound - fractionRange.lowerBound)
        ) * size.height
        return CGPoint(x: x, y: y)
    }
}
