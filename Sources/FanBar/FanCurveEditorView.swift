import AppKit
import FanBarShared
import SwiftUI

/// Smart-cooling settings: curve first, advanced controls behind disclosure.
struct FanCurveEditorView: View {
    @ObservedObject var controller: FanController
    @State private var showAdvanced = false

    private var profile: FanCurveProfile { controller.curveProfile }

    /// Stable identity for forcing the canvas to redraw when anchors change.
    private var curveCanvasIdentity: String {
        let points = profile.points
            .map { "\($0.celsius)-\($0.fraction)" }
            .joined(separator: "|")
        return "\(controller.curveBuiltInSelection.rawValue);\(points)"
    }

    private var selectionTitle: String {
        controller.curveBuiltInSelection.title
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
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            primaryCurveSection
            advancedSection
        }
    }

    // MARK: - Primary path

    private var primaryCurveSection: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            SettingsChrome.sectionHeader(
                fanBarText("智能温控曲线", "Smart cooling curve"),
                trailing: selectionTitle
            )

            SettingsChrome.settingsCard {
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
                .id(curveCanvasIdentity)
                .frame(height: 188)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if controller.mode == .temperatureCurve,
                   let temperature = controller.curveTemperatureCelsius,
                   let fraction = controller.curveOutputFraction {
                    Text(fanBarFormat(
                        "当前：%.0f°C → %.0f%%",
                        "Now: %.0f°C → %.0f%%",
                        temperature,
                        fraction * 100
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                    .padding(.bottom, 8)
                }

                SettingsChrome.rowDivider

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(fanBarText("预设", "Preset"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(fanBarText("恢复出厂形状", "Reset to factory")) {
                            controller.resetActiveCurvePresetToFactory()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .help(fanBarText(
                            "将当前预设的锚点恢复为出厂默认，不影响另外两个预设",
                            "Restore this preset’s anchors to factory defaults without changing the other presets"
                        ))
                    }

                    // Native AppKit control — three editable slots, always one selected.
                    CurvePresetSegmentedControl(
                        selection: controller.curveBuiltInSelection,
                        onSelect: { builtIn in
                            controller.applyCurveBuiltIn(builtIn)
                        }
                    )
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                .padding(.vertical, SettingsChrome.rowVerticalPadding)

                SettingsChrome.rowDivider

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
                .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                .padding(.vertical, SettingsChrome.rowVerticalPadding)
            }

            SettingsChrome.sectionFooter(primaryFooter)
        }
    }

    private var primaryFooter: String {
        fanBarText(
            "默认 / 静音 / 激进是三个独立预设槽；拖动锚点只改当前槽并自动保存。0% 表示目标停转。开启菜单栏「智能」后立即生效。",
            "Default / Quiet / Aggressive are three slots; dragging anchors edits the active slot and saves automatically. 0% targets idle RPM. Takes effect when Smart mode is on."
        )
    }

    // MARK: - Advanced (collapsed by default)

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAdvanced.toggle()
                }
                SettingsChrome.requestWindowRefit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                        .foregroundColor(.secondary)
                    Text(fanBarText("高级", "Advanced"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(advancedSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(fanBarText(
                "展开以编辑锚点、磁滞与步进限制",
                "Expand to edit anchors, hysteresis, and step limit"
            ))

            if showAdvanced {
                SettingsChrome.settingsCard {
                    pointEditorBlock

                    SettingsChrome.rowDivider

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fanBarText("降温磁滞", "Falling hysteresis"))
                            Text(fanBarText(
                                "降温时保持较高转速，减少抖动。",
                                "Holds higher RPM while cooling to reduce chatter."
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
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
                    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                    .padding(.vertical, SettingsChrome.rowVerticalPadding)

                    SettingsChrome.rowDivider

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fanBarText("每步最大变化", "Max step per tick"))
                            Text(fanBarText(
                                "限制转速一次跳变的幅度。",
                                "Limits how far speed can jump each tick."
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
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
                    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
                    .padding(.vertical, SettingsChrome.rowVerticalPadding)
                }

                SettingsChrome.sectionFooter(fanBarText(
                    "步进器可精确编辑锚点；与拖动曲线等效。",
                    "Steppers edit anchors precisely; equivalent to dragging the chart."
                ))
            }
        }
        .onChange(of: showAdvanced) { _ in
            SettingsChrome.requestWindowRefit()
        }
    }

    private var advancedSummary: String {
        fanBarFormat(
            "%d 点 · 磁滞 %d°C · 步进 %d%%",
            "%d pts · hyst %d°C · step %d%%",
            profile.points.count,
            Int(profile.hysteresisCelsius.rounded()),
            Int((profile.maxFractionStepPerUpdate * 100).rounded())
        )
    }

    private var pointEditorBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fanBarText("锚点", "Anchors"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
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
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(profile.points) { point in
                curvePointRow(point)
            }

            HStack {
                Button {
                    controller.addCurvePoint()
                    SettingsChrome.requestWindowRefit()
                } label: {
                    Label(
                        fanBarText("添加锚点", "Add point"),
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(.plain)
                .disabled(profile.points.count >= FanCurveProfile.maximumPointCount)

                Spacer()
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.vertical, 8)
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
                SettingsChrome.requestWindowRefit()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(profile.points.count <= FanCurveProfile.minimumPointCount)
            .help(fanBarText("删除锚点", "Remove point"))
        }
        .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
        .padding(.vertical, 4)
    }
}

// MARK: - Native preset control

/// AppKit segmented control — always has one of three presets selected.
struct CurvePresetSegmentedControl: NSViewRepresentable {
    var selection: FanCurveProfile.BuiltIn
    var onSelect: (FanCurveProfile.BuiltIn) -> Void

    final class Coordinator: NSObject {
        var onSelect: (FanCurveProfile.BuiltIn) -> Void
        init(onSelect: @escaping (FanCurveProfile.BuiltIn) -> Void) {
            self.onSelect = onSelect
        }

        @MainActor
        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard FanCurveProfile.BuiltIn.allCases.indices.contains(index) else { return }
            onSelect(FanCurveProfile.BuiltIn.allCases[index])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let titles = FanCurveProfile.BuiltIn.allCases.map(\.title)
        let control = NSSegmentedControl(
            labels: titles,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:))
        )
        control.segmentStyle = .rounded
        control.controlSize = .regular
        applySelection(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        let titles = FanCurveProfile.BuiltIn.allCases.map(\.title)
        for (index, title) in titles.enumerated() where index < control.segmentCount {
            control.setLabel(title, forSegment: index)
        }
        applySelection(control)
    }

    private func applySelection(_ control: NSSegmentedControl) {
        if let index = FanCurveProfile.BuiltIn.allCases.firstIndex(of: selection),
           control.selectedSegment != index {
            control.selectedSegment = index
        }
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
    /// Left gutter for Y-axis speed labels (e.g. "100%").
    private let yAxisWidth: CGFloat = 36
    /// Bottom gutter for X-axis temperature labels (e.g. "60°C").
    private let xAxisHeight: CGFloat = 22
    private let plotTopInset: CGFloat = 6
    private let plotTrailingInset: CGFloat = 8

    /// Major X ticks every 10°C across the full temperature domain.
    private var temperatureTicks: [Double] {
        stride(
            from: FanCurveProfile.minimumCelsius,
            through: FanCurveProfile.maximumCelsius,
            by: 10
        ).map { $0 }
    }

    /// Major Y ticks every 10% across the full speed domain.
    private var fractionPercentTicks: [Int] {
        stride(
            from: Int((FanCurveProfile.minimumFraction * 100).rounded()),
            through: Int((FanCurveProfile.maximumFraction * 100).rounded()),
            by: 10
        ).map { $0 }
    }

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
            let plot = plotRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                axisChrome(plot: plot, canvasSize: geometry.size)

                // Plot contents use the full canvas coordinate space; mapping
                // functions already account for the axis gutters.
                Path { path in
                    let samples = samplePoints(for: displayProfile, plot: plot)
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
                                plot: plot
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
                    .position(position(celsius: point.celsius, fraction: point.fraction, plot: plot))
                    .gesture(dragGesture(for: point, plot: plot))
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

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: yAxisWidth,
            y: plotTopInset,
            width: max(1, size.width - yAxisWidth - plotTrailingInset),
            height: max(1, size.height - plotTopInset - xAxisHeight)
        )
    }

    @ViewBuilder
    private func axisChrome(plot: CGRect, canvasSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .frame(width: plot.width, height: plot.height)
                .position(x: plot.midX, y: plot.midY)

            // Grid lines aligned to every major tick.
            Path { path in
                for percent in fractionPercentTicks {
                    let y = position(
                        celsius: temperatureRange.lowerBound,
                        fraction: Float(percent) / 100,
                        plot: plot
                    ).y
                    path.move(to: CGPoint(x: plot.minX, y: y))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                for celsius in temperatureTicks {
                    let x = position(
                        celsius: celsius,
                        fraction: Float(fractionRange.lowerBound),
                        plot: plot
                    ).x
                    path.move(to: CGPoint(x: x, y: plot.minY))
                    path.addLine(to: CGPoint(x: x, y: plot.maxY))
                }
            }
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)

            // Plot border
            Path { path in
                path.addRect(plot)
            }
            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)

            // Y-axis: full speed scale (0% … 100%)
            ForEach(fractionPercentTicks, id: \.self) { percent in
                let y = position(
                    celsius: temperatureRange.lowerBound,
                    fraction: Float(percent) / 100,
                    plot: plot
                ).y
                Text("\(percent)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: yAxisWidth - 4, alignment: .trailing)
                    .position(x: yAxisWidth / 2 - 1, y: y)
            }

            // X-axis: full temperature scale (30°C … 100°C)
            ForEach(temperatureTicks, id: \.self) { celsius in
                let x = position(
                    celsius: celsius,
                    fraction: Float(fractionRange.lowerBound),
                    plot: plot
                ).x
                Text("\(Int(celsius))°C")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .position(x: x, y: plot.maxY + xAxisHeight / 2)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func dragGesture(for point: FanCurvePoint, plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if draggingPointID == nil {
                    // Only claim the drag if the press landed near this handle.
                    let origin = position(
                        celsius: point.celsius,
                        fraction: point.fraction,
                        plot: plot
                    )
                    let distance = hypot(value.startLocation.x - origin.x, value.startLocation.y - origin.y)
                    guard distance <= handleHitRadius else { return }
                    draggingPointID = point.id
                }
                guard draggingPointID == point.id else { return }

                let mapped = values(at: value.location, plot: plot)
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
                let mapped = values(at: value.location, plot: plot)
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

    private func samplePoints(for profile: FanCurveProfile, plot: CGRect) -> [CGPoint] {
        // Dense sampling so the monotone cubic reads as a continuous curve.
        let steps = 96
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let celsius = temperatureRange.lowerBound
                + (temperatureRange.upperBound - temperatureRange.lowerBound) * t
            let fraction = profile.fraction(at: celsius)
            return position(celsius: celsius, fraction: fraction, plot: plot)
        }
    }

    private func position(celsius: Double, fraction: Float, plot: CGRect) -> CGPoint {
        let clampedT = min(max(celsius, temperatureRange.lowerBound), temperatureRange.upperBound)
        let clampedF = min(
            max(Double(fraction), fractionRange.lowerBound),
            fractionRange.upperBound
        )
        let x = plot.minX + CGFloat(
            (clampedT - temperatureRange.lowerBound)
                / (temperatureRange.upperBound - temperatureRange.lowerBound)
        ) * plot.width
        let y = plot.maxY - CGFloat(
            (clampedF - fractionRange.lowerBound)
                / (fractionRange.upperBound - fractionRange.lowerBound)
        ) * plot.height
        return CGPoint(x: x, y: y)
    }

    private func values(at location: CGPoint, plot: CGRect) -> (celsius: Double, fraction: Float) {
        let width = max(plot.width, 1)
        let height = max(plot.height, 1)
        let tx = min(max(Double((location.x - plot.minX) / width), 0), 1)
        let ty = min(max(Double((plot.maxY - location.y) / height), 0), 1)
        let celsius = temperatureRange.lowerBound
            + (temperatureRange.upperBound - temperatureRange.lowerBound) * tx
        let fraction = Float(
            fractionRange.lowerBound
                + (fractionRange.upperBound - fractionRange.lowerBound) * ty
        )
        return (celsius, fraction)
    }
}
