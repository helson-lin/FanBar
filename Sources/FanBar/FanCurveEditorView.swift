import AppKit
import FanBarShared
import SwiftUI

/// Smart-cooling editor: one card with the curve, an inspector for the
/// selected control point, and behavior tuning behind a disclosure.
struct FanCurveEditorView: View {
    @ObservedObject var controller: FanController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @State private var showAdvanced = false
    @State private var selectedPointID: UUID?

    private var profile: FanCurveProfile { controller.curveProfile }

    private var sortedPoints: [FanCurvePoint] {
        profile.points.sorted { $0.celsius < $1.celsius }
    }

    /// The selected point, falling back to the first one when the stored
    /// selection belongs to another preset or was removed.
    private var selectedIndex: Int? {
        guard !sortedPoints.isEmpty else { return nil }
        return sortedPoints.firstIndex { $0.id == selectedPointID } ?? 0
    }

    /// Stable identity for forcing the canvas to redraw when control points change.
    private var curveCanvasIdentity: String {
        let points = profile.points
            .map { "\($0.celsius)-\($0.fraction)" }
            .joined(separator: "|")
        return "\(controller.curveCoolingPreset.rawValue);\(points)"
    }

    private var fractionPercentRange: ClosedRange<Int> {
        let lower = Int((FanCurveProfile.minimumFraction * 100).rounded())
        let upper = Int((FanCurveProfile.maximumFraction * 100).rounded())
        return lower...upper
    }

    private var hysteresisRange: ClosedRange<Int> {
        Int(FanCurveProfile.minimumHysteresisCelsius)...Int(FanCurveProfile.maximumHysteresisCelsius)
    }

    private var rateLimitPercentRange: ClosedRange<Int> {
        let lower = Int((FanCurveProfile.minimumFractionStep * 100).rounded())
        let upper = Int((FanCurveProfile.maximumFractionStep * 100).rounded())
        return lower...upper
    }

    var body: some View {
        SettingsChrome.settingsCard {
            header

            FanCurveCanvas(
                profile: profile,
                // Resolved selection, so the canvas highlights the point the
                // inspector shows even before anything was clicked.
                selectedPointID: Binding(
                    get: { selectedIndex.map { sortedPoints[$0].id } },
                    set: { selectedPointID = $0 }
                ),
                currentCelsius: controller.curveTemperatureCelsius,
                currentFraction: controller.curveOutputFraction,
                currentSummary: controller.curveOutputSummary,
                onPointChange: { id, celsius, fraction in
                    controller.updateCurvePoint(
                        id: id,
                        celsius: celsius,
                        fraction: fraction
                    )
                }
            )
            .id(curveCanvasIdentity)
            .frame(height: 204)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)

            inspector

            footer

            advancedDisclosure
            if showAdvanced {
                advancedRows
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: showAdvanced) { _ in
            SettingsChrome.requestWindowRefit()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(fanBarFormat("%@曲线", "%@ curve", controller.curveCoolingPreset.title))
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 8)

            // The source defines the horizontal axis, so it sits above the chart.
            Text(fanBarText("温度来源", "Temperature source"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Picker(
                fanBarText("温度来源", "Temperature source"),
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
        .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
        .padding(.top, 11)
        .padding(.bottom, 4)
    }

    // MARK: - Selected control point

    @ViewBuilder
    private var inspector: some View {
        if let index = selectedIndex {
            let points = sortedPoints
            let point = points[index]
            // Steppers keep the point between its neighbors so a precise edit
            // never reorders the curve or changes which point is selected.
            let lower = index > 0 ? points[index - 1].celsius + 1 : FanCurveProfile.minimumCelsius
            let upper = index < points.count - 1
                ? points[index + 1].celsius - 1
                : FanCurveProfile.maximumCelsius
            let celsiusRange = Int(lower)...Int(max(lower, upper))

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fanBarFormat("控制点 %d / %d", "Point %d of %d", index + 1, points.count))
                        .font(.system(size: 12, weight: .semibold))
                    Text(targetSummary(for: point.fraction))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 116, alignment: .leading)

                labeledStepper(
                    fanBarText("温度", "Temp"),
                    value: Binding(
                        get: { Int(point.celsius.rounded()) },
                        set: { controller.updateCurvePoint(id: point.id, celsius: Double($0)) }
                    ),
                    range: celsiusRange,
                    valueText: fanBarFormat("%d°C", "%d°C", Int(point.celsius.rounded())),
                    valueWidth: 44
                )

                labeledStepper(
                    fanBarText("转速", "Speed"),
                    value: Binding(
                        get: { Int((point.fraction * 100).rounded()) },
                        set: { controller.updateCurvePoint(id: point.id, fraction: Float($0) / 100) }
                    ),
                    range: fractionPercentRange,
                    valueText: fanBarFormat("%d%%", "%d%%", Int((point.fraction * 100).rounded())),
                    valueWidth: 40
                )

                Spacer(minLength: 0)

                Button {
                    if let newID = controller.insertCurvePoint(after: point.id) {
                        selectedPointID = newID
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 14)
                }
                .disabled(points.count >= FanCurveProfile.maximumPointCount)
                .help(fanBarText("在此控制点后添加控制点", "Add a control point after this one"))
                .accessibilityLabel(fanBarText("在此控制点后添加控制点", "Add a control point after this one"))

                Button {
                    selectedPointID = points[index > 0 ? index - 1 : min(1, points.count - 1)].id
                    controller.removeCurvePoint(id: point.id)
                } label: {
                    Image(systemName: "minus").frame(width: 14)
                }
                .disabled(points.count <= FanCurveProfile.minimumPointCount)
                .help(fanBarText("删除此控制点", "Remove this control point"))
                .accessibilityLabel(fanBarText("删除此控制点", "Remove this control point"))
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
            .padding(.vertical, 8)
        }
    }

    private func labeledStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        valueText: String,
        valueWidth: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Stepper(value: value, in: range) {
                Text(valueText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: valueWidth, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
    }

    /// The per-fan RPM this fraction targets, or a plain idle note at 0%.
    private func targetSummary(for fraction: Float) -> String {
        guard fraction > 0 else {
            return fanBarText("怠速（目标 0 RPM）", "Idle (target 0 RPM)")
        }
        guard let range = FanController.curveTargetRange(fraction: fraction, fans: controller.fans) else {
            return "—"
        }
        let low = FanBarNumberFormatter.grouped(range.lowerBound)
        let high = FanBarNumberFormatter.grouped(range.upperBound)
        return fanBarFormat(
            "≈ %@ RPM",
            "≈ %@ RPM",
            range.lowerBound == range.upperBound ? low : "\(low)–\(high)"
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(fanBarText(
                "拖动控制点，或选中后用上方步进器微调。0% 表示风扇回到怠速。",
                "Drag a control point, or select one and fine-tune it above. 0% returns the fans to idle."
            ))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(fanBarText("恢复默认", "Reset to Default")) {
                controller.resetActiveCurvePresetToFactory(
                    undoManager: undoManager,
                    actionName: fanBarText("恢复默认曲线", "Reset Default Curve")
                )
            }
            .controlSize(.small)
            .disabled(profile.hasFactoryCurve(for: controller.curveCoolingPreset))
            .help(fanBarText(
                "恢复当前预设的默认曲线；可使用撤销恢复修改",
                "Restore this preset's default curve; use Undo to recover edits"
            ))
        }
        .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
        .padding(.vertical, 8)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Advanced (collapsed by default)

    private var advancedDisclosure: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1)) {
                showAdvanced.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(fanBarText("高级", "Advanced"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(advancedSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Divider(), alignment: .top)
        .accessibilityValue(showAdvanced ? fanBarText("已展开", "Expanded") : fanBarText("已收起", "Collapsed"))
        .accessibilityHint(fanBarText(
            "展开以编辑降温缓冲与每步最大变化",
            "Expand to edit the cooling buffer and maximum step"
        ))
    }

    private var advancedRows: some View {
        VStack(spacing: 0) {
            Divider()
            behaviorRow(
                title: fanBarText("降温缓冲", "Cooling buffer"),
                detail: fanBarText(
                    "降温时保持较高转速，减少来回抖动。",
                    "Holds higher RPM while cooling to reduce chatter."
                ),
                value: Binding(
                    get: { Int(profile.hysteresisCelsius.rounded()) },
                    set: { controller.setCurveHysteresisCelsius(Double($0)) }
                ),
                range: hysteresisRange,
                valueText: fanBarFormat("%d°C", "%d°C", Int(profile.hysteresisCelsius.rounded()))
            )
            Divider().padding(.leading, SettingsChrome.rowHorizontalPadding)
            behaviorRow(
                title: fanBarText("每步最大变化", "Max step per update"),
                detail: fanBarText(
                    "限制转速一次更新可变化的幅度。",
                    "Limits how far speed can change in one update."
                ),
                value: Binding(
                    get: { Int((profile.maxFractionStepPerUpdate * 100).rounded()) },
                    set: { controller.setCurveMaxFractionStep(Float($0) / 100) }
                ),
                range: rateLimitPercentRange,
                valueText: fanBarFormat(
                    "%d%%",
                    "%d%%",
                    Int((profile.maxFractionStepPerUpdate * 100).rounded())
                )
            )
        }
    }

    private func behaviorRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        valueText: String
    ) -> some View {
        HStack {
            SettingsRowText(title: title, detail: detail)
            Spacer(minLength: 12)
            Stepper(value: value, in: range) {
                Text(valueText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
        .padding(.horizontal, SettingsChrome.rowHorizontalPadding + 2)
        .padding(.vertical, SettingsChrome.rowVerticalPadding)
    }

    private var advancedSummary: String {
        fanBarFormat(
            "缓冲 %d°C · 步进 %d%%",
            "buffer %d°C · step %d%%",
            Int(profile.hysteresisCelsius.rounded()),
            Int((profile.maxFractionStepPerUpdate * 100).rounded())
        )
    }
}

// MARK: - Draggable curve canvas

/// Interactive temperature → fraction chart. Drag control points to reshape
/// the curve; pressing a point also selects it for the inspector.
struct FanCurveCanvas: View {
    let profile: FanCurveProfile
    @Binding var selectedPointID: UUID?
    var currentCelsius: Double?
    var currentFraction: Float?
    /// Target RPM and curve output for the live reading, shown beside the marker.
    var currentSummary: String?
    var onPointChange: (UUID, Double, Float) -> Void

    @State private var draggingPointID: UUID?
    @State private var hoveringPointID: UUID?
    @State private var dragCelsius: Double?
    @State private var dragFraction: Float?
    @State private var dragGrabOffset = CGSize.zero

    private static let canvasCoordinateSpace = "fanbar.curveCanvas"
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

    /// Subtle grid remains precise while labels use a calmer 20% cadence.
    private var fractionGridPercentTicks: [Int] {
        stride(
            from: Int((FanCurveProfile.minimumFraction * 100).rounded()),
            through: Int((FanCurveProfile.maximumFraction * 100).rounded()),
            by: 10
        ).map { $0 }
    }

    private var fractionLabelPercentTicks: [Int] {
        stride(
            from: Int((FanCurveProfile.minimumFraction * 100).rounded()),
            through: Int((FanCurveProfile.maximumFraction * 100).rounded()),
            by: 20
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
                    currentMarker(celsius: currentCelsius, fraction: currentFraction, plot: plot)
                }

                ForEach(Array(displayPoints.enumerated()), id: \.element.id) { index, point in
                    let isDragging = point.id == draggingPointID
                    let isHighlighted = isDragging || point.id == hoveringPointID
                    let isSelected = point.id == selectedPointID
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor.opacity(0.22))
                                .frame(width: 22, height: 22)
                        }
                        // Expanded hit target for easier grabbing on dense charts.
                        Circle()
                            .fill(Color.primary.opacity(0.001))
                            .frame(width: handleHitRadius * 2, height: handleHitRadius * 2)
                        Circle()
                            .fill(isDragging ? Color.accentColor : Color.accentColor.opacity(0.95))
                            .frame(
                                width: isDragging ? 12 : (isHighlighted ? 11 : 9),
                                height: isDragging ? 12 : (isHighlighted ? 11 : 9)
                            )
                            .shadow(
                                color: Color.accentColor.opacity(isHighlighted ? 0.3 : 0),
                                radius: 4
                            )

                        if isHighlighted {
                            Text(fanBarFormat(
                                "%.0f°C · %.0f%%",
                                "%.0f°C · %.0f%%",
                                point.celsius,
                                point.fraction * 100
                            ))
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(NSColor.windowBackgroundColor).opacity(0.94))
                            )
                            .offset(y: point.fraction > 0.85 ? 21 : -21)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
                    .position(position(celsius: point.celsius, fraction: point.fraction, plot: plot))
                    .gesture(dragGesture(for: point, plot: plot))
                    .onHover { hovering in
                        hoveringPointID = hovering ? point.id : nil
                    }
                    .help(fanBarFormat(
                        "%.0f°C · %.0f%%",
                        "%.0f°C · %.0f%%",
                        point.celsius,
                        point.fraction * 100
                    ))
                    .accessibilityElement()
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityLabel(fanBarFormat(
                        "控制点 %d",
                        "Control point %d",
                        index + 1
                    ))
                    .accessibilityValue(fanBarFormat(
                        "%.0f°C，%.0f%%",
                        "%.0f°C, %.0f%%",
                        point.celsius,
                        point.fraction * 100
                    ))
                    .accessibilityHint(fanBarText(
                        "使用自定义操作调整温度或转速",
                        "Use custom actions to adjust temperature or fan speed"
                    ))
                    .accessibilityAction(named: Text(fanBarText("温度增加", "Increase temperature"))) {
                        nudge(point: point, celsiusDelta: 1)
                    }
                    .accessibilityAction(named: Text(fanBarText("温度降低", "Decrease temperature"))) {
                        nudge(point: point, celsiusDelta: -1)
                    }
                    .accessibilityAction(named: Text(fanBarText("转速增加", "Increase fan speed"))) {
                        nudge(point: point, fractionDelta: 0.01)
                    }
                    .accessibilityAction(named: Text(fanBarText("转速降低", "Decrease fan speed"))) {
                        nudge(point: point, fractionDelta: -0.01)
                    }
                }
            }
            .contentShape(Rectangle())
            // Handles request locations in this shared canvas space so their
            // gesture values use the same coordinates as the plot geometry.
            .coordinateSpace(name: Self.canvasCoordinateSpace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fanBarText("可拖动温控曲线", "Draggable cooling curve"))
        .accessibilityValue(fanBarFormat(
            "%d 个控制点",
            "%d control points",
            profile.points.count
        ))
        .accessibilityHint(fanBarText(
            "拖动控制点调整温度与转速；也可用下方步进器微调所选控制点",
            "Drag control points to set temperature and speed; use the steppers below for the selected point"
        ))
    }

    /// Vertical guide, dot and label for the live temperature and its output.
    private func currentMarker(celsius: Double, fraction: Float, plot: CGRect) -> some View {
        let location = position(celsius: celsius, fraction: fraction, plot: plot)
        // The RPM target is what the fans are asked to do; without fan readings
        // fall back to the curve output alone.
        let label = fanBarFormat(
            "当前 %.0f°C → %@",
            "Now %.0f°C → %@",
            celsius,
            currentSummary ?? String(format: "%.0f%%", fraction * 100)
        )
        // Keep the label inside the plot: flip it left of the guide past the middle.
        let labelOnLeft = location.x > plot.midX

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: location.x, y: plot.minY))
                path.addLine(to: CGPoint(x: location.x, y: plot.maxY))
            }
            .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            Circle()
                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                .frame(width: 10, height: 10)
                .position(location)

            Color.clear
                .frame(width: plot.width, height: 20)
                .overlay(currentLabel(label, onLeft: labelOnLeft, inset: labelOnLeft
                    ? plot.maxX - location.x + 6
                    : location.x - plot.minX + 6),
                    alignment: labelOnLeft ? .trailing : .leading)
                .position(x: plot.midX, y: plot.minY + 22)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The live-reading chip. Wraps to two lines so the RPM range never runs off the plot.
    private func currentLabel(_ text: String, onLeft: Bool, inset: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .multilineTextAlignment(onLeft ? .trailing : .leading)
            .lineLimit(2)
            .frame(maxWidth: 200, alignment: onLeft ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .padding(onLeft ? .trailing : .leading, inset)
    }

    private func highTemperatureBand(plot: CGRect) -> some View {
        let x = position(celsius: ThermalAlertSettings.thresholdCelsius, fraction: 0, plot: plot).x
        let width = max(0, plot.maxX - x)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: width, height: plot.height)
                .position(x: x + width / 2, y: plot.midY)
            Path { path in
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
            .stroke(Color.orange.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text(fanBarText("高温提醒", "Heat alert"))
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .fixedSize()
                .position(x: plot.maxX - 26, y: plot.maxY - 9)
        }
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

            // Range where the high-temperature notification fires.
            highTemperatureBand(plot: plot)

            // Grid lines aligned to every major tick.
            Path { path in
                for percent in fractionGridPercentTicks {
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
            ForEach(fractionLabelPercentTicks, id: \.self) { percent in
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
        .accessibilityHidden(true)
    }

    /// Gives VoiceOver users the same precise one-unit edits available in the
    /// visual drag interaction without requiring Advanced to be expanded.
    private func nudge(
        point: FanCurvePoint,
        celsiusDelta: Double = 0,
        fractionDelta: Float = 0
    ) {
        let constrained = constrain(
            pointID: point.id,
            celsius: point.celsius + celsiusDelta,
            fraction: point.fraction + fractionDelta
        )
        onPointChange(point.id, constrained.celsius, constrained.fraction)
    }

    private func dragGesture(for point: FanCurvePoint, plot: CGRect) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.canvasCoordinateSpace)
        )
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
                    // Preserve the exact point where the handle was grabbed;
                    // otherwise its center would jump under the pointer.
                    dragGrabOffset = FanCurveDragGeometry.grabOffset(
                        pointer: value.startLocation,
                        handleCenter: origin
                    )
                    draggingPointID = point.id
                    selectedPointID = point.id
                }
                guard draggingPointID == point.id else { return }

                let mapped = values(
                    at: FanCurveDragGeometry.handleCenter(
                        pointer: value.location,
                        grabOffset: dragGrabOffset
                    ),
                    plot: plot
                )
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
                let mapped = values(
                    at: FanCurveDragGeometry.handleCenter(
                        pointer: value.location,
                        grabOffset: dragGrabOffset
                    ),
                    plot: plot
                )
                let constrained = constrain(
                    pointID: point.id,
                    celsius: mapped.celsius,
                    fraction: mapped.fraction
                )
                onPointChange(point.id, constrained.celsius, constrained.fraction)
                draggingPointID = nil
                dragCelsius = nil
                dragFraction = nil
                dragGrabOffset = .zero
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

/// Pure drag-coordinate helpers shared by the canvas and unit tests.
/// Keeping these calculations independent from SwiftUI prevents local/canvas
/// coordinate regressions from being hidden inside gesture closures.
enum FanCurveDragGeometry {
    static func grabOffset(pointer: CGPoint, handleCenter: CGPoint) -> CGSize {
        CGSize(
            width: pointer.x - handleCenter.x,
            height: pointer.y - handleCenter.y
        )
    }

    static func handleCenter(pointer: CGPoint, grabOffset: CGSize) -> CGPoint {
        CGPoint(
            x: pointer.x - grabOffset.width,
            y: pointer.y - grabOffset.height
        )
    }
}
