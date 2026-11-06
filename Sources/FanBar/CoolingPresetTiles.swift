import AppKit
import FanBarShared
import SwiftUI

/// Every cooling preset as one control: built-ins on the first row, custom
/// presets after them, and an add tile that fills the rest of the last row.
/// Selecting a tile edits that preset's curve; its checkbox decides whether
/// the menu panel shows it.
struct CoolingPresetTiles: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    @ObservedObject private var rename = PresetRenameCoordinator.shared
    @AppStorage(CoolingPresetPreferences.preferenceKey)
    private var menuPresetsRawValue = CoolingPresetPreferences.defaultRawValue
    @State private var isShowingNewPreset = false
    @State private var renameText = ""
    @State private var renameProblem: CustomPresetRules.NameProblem?

    private static let columns = 4
    private static let spacing: CGFloat = 8
    /// The settings pane has a fixed width, so columns are known up front and
    /// the add tile can span several of them without measuring.
    private static let columnWidth: CGFloat = (
        SettingsChrome.contentWidth
            - SettingsChrome.horizontalPadding * 2
            - spacing * CGFloat(columns - 1)
    ) / CGFloat(columns)

    private var presets: [CoolingPresetSummary] { controller.allPresets }

    private var menuPresets: [CoolingPresetID] {
        CoolingPresetPreferences.presets(from: menuPresetsRawValue, available: presets.map(\.id))
    }

    private var isMenuFull: Bool {
        menuPresets.count >= CoolingPresetPreferences.menuLimit
    }

    private var menuLimitMessage: String {
        fanBarText(
            "菜单面板最多显示 2 个预设，取消勾选一个后可换成其他预设。",
            "The menu panel shows up to two presets. Uncheck one to choose another."
        )
    }

    private var footerText: String {
        if let renameProblem {
            return fanBarFormat("%@，已保留原名。", "%@. The previous name was kept.", renameProblem.message)
        }
        if !controller.canAddCustomPreset {
            return fanBarText(
                "最多 6 个自定义预设，删除一个后可以再新建。",
                "You can have up to six custom presets. Delete one to create another."
            )
        }
        if isMenuFull { return menuLimitMessage }
        return fanBarText(
            "点按预设编辑它的曲线，右键查看更多操作。勾选“显示在菜单”可加入菜单面板，最多 2 个。",
            "Select a preset to edit its curve; Control-click it for more actions. “Show in menu” adds up to two to the panel."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.headerToCardSpacing) {
            SettingsChrome.sectionHeader(
                fanBarText("预设", "Presets"),
                trailing: fanBarFormat(
                    "菜单里显示 %d / %d",
                    "Shown in menu %d / %d",
                    menuPresets.count,
                    CoolingPresetPreferences.menuLimit
                )
            )

            VStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(row) { preset in
                            tile(for: preset)
                                .frame(width: Self.columnWidth)
                        }
                        if index == rows.count - 1 {
                            addTile(span: Self.columns - row.count)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsChrome.sectionFooter(footerText)
                .foregroundColor(renameProblem == nil ? .secondary : .red)
        }
        .onChange(of: rename.renaming) { renaming in
            guard let renaming else { return }
            renameText = controller.presetTitle(for: renaming)
            renameProblem = nil
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    /// Built-ins fill the first row; custom presets wrap after them. When the
    /// custom presets end a row exactly, an empty row holds the add tile.
    private var rows: [[CoolingPresetSummary]] {
        let builtIns = presets.filter(\.isBuiltIn)
        let customs = presets.filter { !$0.isBuiltIn }
        var rows = [builtIns]
        var start = 0
        while start < customs.count {
            rows.append(Array(customs[start..<min(start + Self.columns, customs.count)]))
            start += Self.columns
        }
        if customs.count % Self.columns == 0 { rows.append([]) }
        return rows
    }

    // MARK: - Preset tile

    private func tile(for preset: CoolingPresetSummary) -> some View {
        let isSelected = controller.curveCoolingPreset == preset.id
        let isRunning = isSelected && controller.mode == .temperatureCurve
        let profile = controller.curveProfile(for: preset.id)
        let shape = RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)

        return VStack(spacing: 0) {
            Button {
                controller.selectCoolingCurvePreset(preset.id, enableControl: false)
            } label: {
                tileLabel(for: preset, profile: profile, isSelected: isSelected, isRunning: isRunning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preset.title)
            .accessibilityValue(isRunning ? fanBarText("运行中", "Running") : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Divider()

            menuToggle(for: preset)
        }
        .background(SettingsChrome.cardBackground)
        .clipShape(shape)
        .overlay(
            shape.stroke(
                isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                lineWidth: isSelected ? 2 : 0.5
            )
        )
        .contextMenu { PresetActionsMenu(controller: controller, preset: preset.id) }
    }

    private func tileLabel(
        for preset: CoolingPresetSummary,
        profile: FanCurveProfile,
        isSelected: Bool,
        isRunning: Bool
    ) -> some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                        if rename.renaming == preset.id {
                            renameField(for: preset.id)
                        } else {
                            Text(preset.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(preset.title)
                        }
                    }
                    .frame(height: 18)

                    PresetCurveThumbnail(profile: profile)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(height: 30)
                        .padding(.vertical, 2)

                    HStack {
                        Text(fanBarFormat("最高 %d%%", "Max %d%%", Int((profile.peakFraction * 100).rounded())))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        if isRunning {
                            Label(fanBarText("运行中", "Running"), systemImage: "circle.fill")
                                .labelStyle(RunningLabelStyle())
                        }
                    }
                    .frame(minHeight: 14)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
    }

    private func renameField(for preset: CoolingPresetID) -> some View {
        TextField(
            fanBarText("预设名称", "Preset name"),
            text: $renameText,
            onCommit: { commitRename(preset) }
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, weight: .semibold))
        .onExitCommand { rename.renaming = nil }
        .accessibilityLabel(fanBarText("预设名称", "Preset name"))
    }

    private func commitRename(_ preset: CoolingPresetID) {
        guard rename.renaming == preset else { return }
        if let problem = controller.renameCustomPreset(preset, to: renameText) {
            renameProblem = problem
        } else {
            renameProblem = nil
        }
        rename.renaming = nil
    }

    /// A labeled checkbox: whether this preset is a shortcut in the menu panel.
    /// The system checkbox supplies keyboard focus, the VoiceOver checkbox
    /// role and the dimmed disabled look.
    private func menuToggle(for preset: CoolingPresetSummary) -> some View {
        let isShown = menuPresets.contains(preset.id)
        let isBlocked = !isShown && isMenuFull

        return Toggle(
            isOn: Binding(
                get: { isShown },
                set: { _ in toggleMenuShortcut(preset.id) }
            )
        ) {
            Text(fanBarText("显示在菜单", "Show in menu"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(isBlocked)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(isBlocked ? menuLimitMessage : fanBarFormat(
            "在菜单面板里为“%@”显示快捷按钮",
            "Show a shortcut button for %@ in the menu panel",
            preset.title
        ))
        .accessibilityLabel(fanBarFormat(
            "在菜单面板显示“%@”",
            "Show %@ in the menu panel",
            preset.title
        ))
    }

    private func toggleMenuShortcut(_ preset: CoolingPresetID) {
        guard let next = CoolingPresetPreferences.toggling(
            preset,
            in: menuPresets,
            order: presets.map(\.id)
        ) else { return }
        CoolingPresetPreferences.save(next)
    }

    // MARK: - Add tile

    /// Fills `span` columns. Alone on its row it is a short banner; with 2–3
    /// columns it lays out horizontally; in one column it is a normal tile.
    private func addTile(span: Int) -> some View {
        let count = controller.customPresets.count
        let isFull = !controller.canAddCustomPreset
        let isAlone = span == Self.columns
        let width = Self.columnWidth * CGFloat(span) + Self.spacing * CGFloat(span - 1)
        let shape = RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius, style: .continuous)

        return Button {
            isShowingNewPreset = true
        } label: {
            addTileLabel(span: span, count: count, isFull: isFull)
                .frame(maxWidth: .infinity, minHeight: isAlone ? 60 : nil, maxHeight: .infinity)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isFull)
        .opacity(isFull ? 0.5 : 1)
        .overlay(shape.strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .frame(width: width)
        .help(isFull
            ? fanBarText("最多 6 个自定义预设", "Up to six custom presets")
            : fanBarText("新建预设", "New Preset"))
        .accessibilityLabel(fanBarText("新建预设", "New Preset"))
        .popover(isPresented: $isShowingNewPreset, arrowEdge: .bottom) {
            NewCustomPresetForm(controller: controller, isPresented: $isShowingNewPreset)
        }
    }

    @ViewBuilder
    private func addTileLabel(span: Int, count: Int, isFull: Bool) -> some View {
        let counter = Text("\(count) / \(CustomPresetRules.maximumCount)")
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.secondary)
                if span >= 2 {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addTitle(isFull: isFull, isFirst: count == 0))
                                .font(.system(size: 13, weight: .semibold))
                            Text(addSubtitle(isFull: isFull, isFirst: count == 0, isWide: span >= 3))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if count == 0 {
                            Text(fanBarText("新建…", "New…"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                        } else {
                            counter
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                        Text(fanBarText("新建预设", "New Preset"))
                            .font(.system(size: 12))
                        counter
                    }
                    .foregroundColor(.secondary)
                }
    }

    private func addTitle(isFull: Bool, isFirst: Bool) -> String {
        if isFull { return fanBarText("已达上限", "Limit reached") }
        return isFirst
            ? fanBarText("新建自己的预设", "Create your own preset")
            : fanBarText("新建预设", "New Preset")
    }

    private func addSubtitle(isFull: Bool, isFirst: Bool, isWide: Bool) -> String {
        if isFull { return fanBarText("删除一个后可以再新建", "Delete one to create another") }
        if isFirst {
            return fanBarText(
                "为剪辑、游戏、会议等场景单独设定一条温度曲线，可以设为菜单快捷按钮。",
                "Give editing, gaming or meetings their own temperature curve, and add it to the menu panel."
            )
        }
        return isWide
            ? fanBarText("从任意预设复制曲线后再调整", "Start from any preset's curve, then adjust it")
            : fanBarText("从任意预设复制曲线", "Copy any preset's curve")
    }
}

/// Lets the curve editor's menu start an inline rename on the matching tile.
@MainActor
final class PresetRenameCoordinator: ObservableObject {
    static let shared = PresetRenameCoordinator()
    @Published var renaming: CoolingPresetID?
}

/// Shared by a tile's context menu and the curve editor's ⋯ menu.
struct PresetActionsMenu: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    let preset: CoolingPresetID

    var body: some View {
        Group {
            switch preset {
            case .builtIn:
                Button(fanBarText("复制为自定义预设", "Duplicate as Custom Preset"), action: duplicate)
                    .disabled(!controller.canAddCustomPreset)
            case .custom(let id):
                Button(fanBarText("重命名…", "Rename…"), action: startRename)
                Menu(fanBarText("更换图标", "Change Icon")) {
                    let current = controller.customPresets.first { $0.id == id }?.symbol
                    ForEach(CustomPresetSymbol.allCases) { symbol in
                        Button {
                            controller.setCustomPresetSymbol(preset, symbol: symbol)
                        } label: {
                            Label(symbol.title, systemImage: symbol.systemImage)
                        }
                        .disabled(symbol == current)
                    }
                }
                Button(fanBarText("复制", "Duplicate"), action: duplicate)
                    .disabled(!controller.canAddCustomPreset)
                Divider()
                Button(fanBarText("删除…", "Delete…")) {
                    CustomPresetDeletion.confirm(controller: controller, preset: preset)
                }
            }
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    func duplicate() {
        controller.duplicatePreset(preset)
    }

    /// Selects the preset so its tile is on screen, then edits its name in place.
    func startRename() {
        controller.selectCoolingCurvePreset(preset)
        PresetRenameCoordinator.shared.renaming = preset
    }
}

/// Destructive confirmation with Cancel as the default button.
enum CustomPresetDeletion {
    @MainActor
    static func confirm(controller: FanController, preset: CoolingPresetID) {
        let name = controller.presetTitle(for: preset)
        let isRunning = controller.curveCoolingPreset == preset && controller.mode == .temperatureCurve
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = fanBarFormat("删除“%@”？", "Delete “%@”?", name)
        var detail = fanBarText(
            "这个预设的曲线会一起删除，删除后不能撤销。",
            "Its curve is deleted too. This can't be undone."
        )
        if isRunning {
            detail += "\n\n" + fanBarText(
                "当前正在使用这个预设，删除后会切换到“均衡”。",
                "This preset is in use. FanBar will switch to Balanced."
            )
        }
        alert.informativeText = detail
        alert.addButton(withTitle: fanBarText("取消", "Cancel"))
        let delete = alert.addButton(withTitle: fanBarText("删除", "Delete"))
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        controller.deleteCustomPreset(preset)
    }
}

/// Popover for a new custom preset: name, icon and the curve to start from.
struct NewCustomPresetForm: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var symbol = CustomPresetSymbol.defaultSymbol
    @State private var source = CoolingPresetID.fallback

    private var problem: CustomPresetRules.NameProblem? {
        controller.presetNameProblem(name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fanBarText("新建预设", "New Preset"))
                .font(.system(size: 13, weight: .semibold))

            row(fanBarText("名称", "Name")) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("", text: $name, onCommit: create)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(fanBarText("名称", "Name"))
                    Text(problem?.message ?? " ")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            row(fanBarText("图标", "Icon")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
                    ForEach(CustomPresetSymbol.allCases) { item in
                        Button {
                            symbol = item
                        } label: {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .foregroundColor(symbol == item ? .white : .secondary)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(symbol == item ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(symbol == item ? .isSelected : [])
                    }
                }
            }

            row(fanBarText("复制自", "Start from")) {
                Picker("", selection: $source) {
                    ForEach(controller.allPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .id(languageRawValue)
                .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                Button(fanBarText("取消", "Cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(fanBarText("创建", "Create"), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            name = CustomPresetRules.defaultName(takenNames: controller.takenPresetNames())
            source = controller.curveCoolingPreset
        }
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
            content()
        }
    }

    private func create() {
        guard problem == nil else { return }
        if controller.createCustomPreset(name: name, symbol: symbol, copying: source) != nil {
            isPresented = false
        }
    }
}

/// A tiny outline of a preset's curve across the full temperature range.
private struct PresetCurveThumbnail: Shape {
    let profile: FanCurveProfile

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        let lower = FanCurveProfile.minimumCelsius
        let span = FanCurveProfile.maximumCelsius - lower
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let fraction = Double(profile.fraction(at: lower + span * t))
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(t),
                y: rect.maxY - rect.height * CGFloat(fraction)
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct RunningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundColor(.green)
            configuration.title
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
