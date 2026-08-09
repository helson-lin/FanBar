import FanBarShared
import SwiftUI

/// Settings pane fragment: draggable curve + presets + sensor + point table + smoothing.
struct FanCurveEditorView: View {
    @ObservedObject var controller: FanController

    private var profile: FanCurveProfile { controller.curveProfile }

    private var selectedBuiltIn: FanCurveProfile.BuiltIn? {
        profile.matchingBuiltIn()
    }

    private var temperatureStepRange: ClosedRange<Int> {
        Int(FanCurveProfile.minimumCelsius)...Int(FanCurveProfile.maximumCelsius)
    }

    private var fractionPercentStepRange: ClosedRange<Int> {
        let lower = Int((FanCurveProfile.minimumFraction * 100).rounded())
        let upper = Int((FanCurveProfile.maximumFraction * 100).rounded())
        return lower...upper
    }

    private var hysteresisStepRange: ClosedRange<Int> {
        let lower = Int(FanCurveProfile.minimumHysteresisCelsius)
        let upper = Int(FanCurveProfile.maximumHysteresisCelsius)
        return lower...upper
    }

    private var rateLimitPercentStepRange: ClosedRange<Int> {
        let lower = Int((FanCurveProfile.minimumFractionStep * 100).rounded())
        let upper = Int((FanCurveProfile.maximumFractionStep * 100).rounded())
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                fanBarText("智能温控曲线", "Smart cooling curve"),
                trailing: profile.displayName
            )

            settingsCard {
                FanCurveCanvas(
                    profile: profile,
                    currentCelsius: controller.curveTemperatureCelsius,
                    currentFraction: controller.curveOutputFraction,
                    onPointChange: { id, celsius, fraction in
                        controller.updateCurvePoint(
                            id: id,
                            celsius: celsius,
                            fraction: fraction
                        )
                    }
                )
                .frame(height: 176)
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
                            .frame(minWidth: 100, alignment: .leading)
                        Text(fanBarText("转速", "Speed"))
                            .frame(minWidth: 100, alignment: .leading)
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

                rowDivider

                HStack {
                    Text(fanBarText("降温磁滞", "Falling hysteresis"))
                    Spacer(minLength: 12)
                    Stepper(
                        value: Binding(
                            get: { Int(profile.hysteresisCelsius.rounded()) },
                            set: { controller.setCurveHysteresisCelsius(Double($0)) }
                        ),
                        in: hysteresisStepRange
                    ) {
                        Text(fanBarFormat("%d°C", "%d°C", Int(profile.hysteresisCelsius.rounded())))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                rowDivider

                HStack {
                    Text(fanBarText("每步最大变化", "Max step per tick"))
                    Spacer(minLength: 12)
                    Stepper(
                        value: Binding(
                            get: { Int((profile.maxFractionStepPerUpdate * 100).rounded()) },
                            set: { controller.setCurveMaxFractionStep(Float($0) / 100) }
                        ),
                        in: rateLimitPercentStepRange
                    ) {
                        Text(fanBarFormat(
                            "%d%%",
                            "%d%%",
                            Int((profile.maxFractionStepPerUpdate * 100).rounded())
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            sectionFooter(fanBarText(
                "拖动图上的锚点，或用步进器微调。磁滞在降温时保持较高转速；每步限制防止转速跳变。智能温控开启时修改会立即生效。",
                "Drag anchors on the chart or fine-tune with steppers. Hysteresis holds higher RPM while cooling; the step limit smooths jumps. Changes apply immediately while smart cooling is on."
            ))
        }
    }

    private func curvePointRow(_ point: FanCurvePoint) -> some View {
        HStack(spacing: 12) {
            Stepper(
                value: Binding(
                    get: { Int(point.celsius.rounded()) },
                    set: { controller.updateCurvePoint(id: point.id, celsius: Double($0)) }
                ),
                in: temperatureStepRange
            ) {
                Text(fanBarFormat("%d°C", "%d°C", Int(point.celsius.rounded())))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(minWidth: 120, alignment: .leading)

            Stepper(
                value: Binding(
                    get: { Int((point.fraction * 100).rounded()) },
                    set: {
                        controller.updateCurvePoint(
                            id: point.id,
                            fraction: Float($0) / 100
                        )
                    }
                ),
                in: fractionPercentStepRange
            ) {
                Text(fanBarFormat("%d%%", "%d%%", Int((point.fraction * 100).rounded())))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 0)

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

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
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

// MARK: - Draggable curve canvas

/// Interactive temperature → fraction chart. Drag anchors to reshape the curve.
struct FanCurveCanvas: View {
    let profile: FanCurveProfile
    var currentCelsius: Double?
    var currentFraction: Float?
    var onPointChange: (UUID, Double, Float) -> Void

    @State private var draggingPointID: UUID?
    @State private var dragCelsius: Double?
    @State private var dragFraction: Float?

    private let temperatureRange = FanCurveProfile.minimumCelsius...FanCurveProfile.maximumCelsius
    private let fractionRange = Double(FanCurveProfile.minimumFraction)...Double(FanCurveProfile.maximumFraction)
    private let handleHitRadius: CGFloat = 14

    private var displayPoints: [FanCurvePoint] {
        profile.points.map { point in
            guard point.id == draggingPointID,
                  let dragCelsius,
                  let dragFraction else { return point }
            return FanCurvePoint(id: point.id, celsius: dragCelsius, fraction: dragFraction)
        }
        .sorted { $0.celsius < $1.celsius }
    }

    private var displayProfile: FanCurveProfile {
        FanCurveProfile(
            sensor: profile.sensor,
            points: displayPoints,
            hysteresisCelsius: profile.hysteresisCelsius,
            maxFractionStepPerUpdate: profile.maxFractionStepPerUpdate
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                grid(in: size)

                Path { path in
                    let samples = samplePoints(for: displayProfile, in: size)
                    guard let first = samples.first else { return }
                    path.move(to: first)
                    for sample in samples.dropFirst() {
                        path.addLine(to: sample)
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                if let currentCelsius, let currentFraction {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                        .background(Circle().fill(Color.primary.opacity(0.12)))
                        .frame(width: 10, height: 10)
                        .position(
                            position(
                                celsius: currentCelsius,
                                fraction: currentFraction,
                                in: size
                            )
                        )
                        .allowsHitTesting(false)
                }

                ForEach(displayPoints) { point in
                    let isDragging = point.id == draggingPointID
                    ZStack {
                        // Expanded hit target for easier grabbing on dense charts.
                        Circle()
                            .fill(Color.primary.opacity(0.001))
                            .frame(width: handleHitRadius * 2, height: handleHitRadius * 2)
                        Circle()
                            .fill(isDragging ? Color.accentColor : Color.accentColor.opacity(0.95))
                            .frame(width: isDragging ? 12 : 9, height: isDragging ? 12 : 9)
                            .shadow(
                                color: Color.accentColor.opacity(isDragging ? 0.35 : 0),
                                radius: 4
                            )
                    }
                    .position(position(celsius: point.celsius, fraction: point.fraction, in: size))
                    .gesture(dragGesture(for: point, in: size))
                    .help(fanBarFormat(
                        "%.0f°C · %.0f%%",
                        "%.0f°C · %.0f%%",
                        point.celsius,
                        point.fraction * 100
                    ))
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fanBarText("可拖动温控曲线", "Draggable cooling curve"))
        .accessibilityValue(fanBarFormat(
            "%d 个锚点，当前曲线 %@",
            "%d anchors, curve %@",
            profile.points.count,
            profile.displayName
        ))
        .accessibilityHint(fanBarText(
            "拖动锚点调整温度与转速；也可用下方步进器微调",
            "Drag anchors to set temperature and speed; use steppers below for fine control"
        ))
    }

    private func dragGesture(for point: FanCurvePoint, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if draggingPointID == nil {
                    // Only claim the drag if the press landed near this handle.
                    let origin = position(
                        celsius: point.celsius,
                        fraction: point.fraction,
                        in: size
                    )
                    let distance = hypot(value.startLocation.x - origin.x, value.startLocation.y - origin.y)
                    guard distance <= handleHitRadius else { return }
                    draggingPointID = point.id
                }
                guard draggingPointID == point.id else { return }

                let mapped = values(at: value.location, in: size)
                let constrained = constrain(
                    pointID: point.id,
                    celsius: mapped.celsius,
                    fraction: mapped.fraction
                )
                dragCelsius = constrained.celsius
                dragFraction = constrained.fraction
            }
            .onEnded { value in
                guard draggingPointID == point.id else { return }
                let mapped = values(at: value.location, in: size)
                let constrained = constrain(
                    pointID: point.id,
                    celsius: mapped.celsius,
                    fraction: mapped.fraction
                )
                onPointChange(point.id, constrained.celsius, constrained.fraction)
                draggingPointID = nil
                dragCelsius = nil
                dragFraction = nil
            }
    }

    private func constrain(
        pointID: UUID,
        celsius: Double,
        fraction: Float
    ) -> (celsius: Double, fraction: Float) {
        let sorted = profile.points.sorted { $0.celsius < $1.celsius }
        guard let index = sorted.firstIndex(where: { $0.id == pointID }) else {
            return (
                min(max(celsius.rounded(), FanCurveProfile.minimumCelsius), FanCurveProfile.maximumCelsius),
                min(max(fraction, FanCurveProfile.minimumFraction), FanCurveProfile.maximumFraction)
            )
        }

        let lowerBound: Double
        if index > 0 {
            lowerBound = sorted[index - 1].celsius + 1
        } else {
            lowerBound = FanCurveProfile.minimumCelsius
        }
        let upperBound: Double
        if index < sorted.count - 1 {
            upperBound = sorted[index + 1].celsius - 1
        } else {
            upperBound = FanCurveProfile.maximumCelsius
        }

        let clampedCelsius = min(max(celsius.rounded(), lowerBound), max(lowerBound, upperBound))
        let clampedFraction = min(
            max(fraction, FanCurveProfile.minimumFraction),
            FanCurveProfile.maximumFraction
        )
        // Quantize fraction to 1% for stable drag feedback.
        let quantizedFraction = (clampedFraction * 100).rounded() / 100
        return (clampedCelsius, quantizedFraction)
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
            .allowsHitTesting(false)
        }
    }

    private func samplePoints(for profile: FanCurveProfile, in size: CGSize) -> [CGPoint] {
        let steps = 48
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

    private func values(at location: CGPoint, in size: CGSize) -> (celsius: Double, fraction: Float) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let tx = min(max(Double(location.x / width), 0), 1)
        let ty = min(max(Double(1 - location.y / height), 0), 1)
        let celsius = temperatureRange.lowerBound
            + (temperatureRange.upperBound - temperatureRange.lowerBound) * tx
        let fraction = Float(
            fractionRange.lowerBound
                + (fractionRange.upperBound - fractionRange.lowerBound) * ty
        )
        return (celsius, fraction)
    }
}
