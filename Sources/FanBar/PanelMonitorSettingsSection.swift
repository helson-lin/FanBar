import AppKit
import FanBarShared
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Appearance › Menu Bar Panel: which monitoring modules the panel shows, and in
/// what order. A skeleton preview mirrors the panel's two-column layout; modules are dragged
/// in the preview or the list, added and removed with the list's + / − buttons.
struct PanelMonitorSettingsSection: View {
    /// nil until customized, which means the default set.
    @AppStorage(PanelMonitorPreferences.preferenceKey)
    private var rawValue: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: PanelMonitorModule?
    @State private var hoveredRow: PanelMonitorModule?
    @State private var hoveredTile: PanelMonitorModule?
    @State private var dragging: PanelMonitorModule?

    private var modules: [PanelMonitorModule] {
        PanelMonitorPreferences.modules(from: rawValue)
    }

    private var footer: String? {
        guard !modules.isEmpty else { return nil }
        var text = fanBarText("未添加模块时，面板不显示监控区域。", "With no modules, the panel hides the monitoring area.")
        if !modules.contains(.disk) {
            text += fanBarText(
                "隐藏「启动盘」后，空间不足时不会在面板中提示。",
                " With Startup Disk hidden, the panel won't warn when space runs low."
            )
        }
        return text
    }

    var body: some View {
        SettingsSection(title: fanBarText("菜单栏面板", "Menu Bar Panel"), footer: footer) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRowText(
                    title: fanBarText("监控模块", "Monitoring Modules"),
                    detail: fanBarText(
                        "按顺序从左到右、从上到下显示在面板中部。直接拖动预览或列表里的模块即可调整位置。",
                        "Shown mid-panel, left to right, top to bottom. Drag a module in the preview or list to move it."
                    )
                )
                if !modules.isEmpty {
                    preview
                }
            }
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, modules.isEmpty ? 12 : 14)

            SettingsChrome.rowDivider

            if modules.isEmpty {
                Text(fanBarText("未添加模块，面板中不显示监控区域。", "No modules. The panel hides the monitoring area."))
                    .foregroundColor(.secondary)
                    .settingsRow()
            } else {
                moduleList
            }

            SettingsChrome.rowDivider

            listFooter
        }
        .onChange(of: modules.count) { _ in SettingsChrome.requestWindowRefit() }
    }

    // MARK: Preview

    /// Pointer-only shortcut for the list below, so VoiceOver skips it.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fanBarText("预览 · 可拖动", "Preview · drag to reorder"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.leading, 6)
            ForEach(PanelMonitorPreferences.rows(modules), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row) { module in
                        tile(module)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 4, trailing: 8))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private func tile(_ module: PanelMonitorModule) -> some View {
        let isSlot = dragging == module
        let isLinked = dragging == nil && (hoveredRow ?? selection) == module
        let isHovered = dragging == nil && hoveredTile == module
        return PanelMonitorSkeletonTile(module: module, showsGrip: !isSlot && (isLinked || isHovered))
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSlot || isLinked ? Color.accentColor.opacity(0.1)
                        : isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSlot || isLinked ? Color.accentColor : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: isSlot ? [4, 3] : [])
                    )
            )
            .opacity(isSlot ? 0.45 : 1)
            .contentShape(Rectangle())
            .onHover { hoveredTile = $0 ? module : (hoveredTile == module ? nil : hoveredTile) }
            .onTapGesture { selection = module }
            .onDrag { beginDrag(module) }
            .onDrop(of: [UTType.plainText], delegate: dropDelegate(for: module))
    }

    // MARK: List

    private var moduleList: some View {
        VStack(spacing: 2) {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                row(module, index: index)
            }
        }
        .padding(SettingsChrome.choiceInset)
    }

    private func row(_ module: PanelMonitorModule, index: Int) -> some View {
        let isSelected = selection == module && dragging == nil
        let isMoving = dragging == module
        return HStack(spacing: 8) {
            Image(systemName: "line.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Color.white.opacity(0.75)
                    : isMoving ? .accentColor : Color(NSColor.tertiaryLabelColor))
            Text(module.title)
                .foregroundColor(isSelected ? .white : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius - SettingsChrome.choiceInset,
                             style: .continuous)
                .fill(isSelected ? Color.accentColor
                    : isMoving ? Color.accentColor.opacity(0.1)
                    : hoveredRow == module ? Color.primary.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.cardCornerRadius - SettingsChrome.choiceInset,
                             style: .continuous)
                .strokeBorder(isMoving ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hoveredRow = $0 ? module : (hoveredRow == module ? nil : hoveredRow) }
        .onTapGesture { selection = module }
        .onDrag { beginDrag(module) }
        .onDrop(of: [UTType.plainText], delegate: dropDelegate(for: module))
        .contextMenu {
            Button(fanBarText("上移", "Move Up")) { move(module, by: -1) }
                .disabled(index == 0)
            Button(fanBarText("下移", "Move Down")) { move(module, by: 1) }
                .disabled(index == modules.count - 1)
            Divider()
            Button(removeTitle(module)) { remove(module) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityValue(fanBarFormat("第 %d 项，共 %d 项", "%d of %d", index + 1, modules.count))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = module }
        .accessibilityAction(named: Text(fanBarText("上移", "Move Up"))) { move(module, by: -1) }
        .accessibilityAction(named: Text(fanBarText("下移", "Move Down"))) { move(module, by: 1) }
        .accessibilityAction(named: Text(removeTitle(module))) { remove(module) }
    }

    // MARK: + / −

    private var listFooter: some View {
        let missing = PanelMonitorPreferences.missing(from: modules)
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(missing) { module in
                        Button(module.title) { add(module) }
                    }
                    if missing.isEmpty {
                        Button(fanBarText("已添加全部模块", "All modules added")) {}
                            .disabled(true)
                    }
                    Divider()
                    Button(fanBarText("恢复默认", "Restore Defaults")) { restoreDefaults() }
                        .disabled(modules == PanelMonitorPreferences.defaultModules)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                .padding(.horizontal, 7)
                .frame(height: 22)
                .accessibilityLabel(fanBarText("添加模块", "Add Module"))

                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 0.5, height: 14)

                Button {
                    if let selection { remove(selection) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(selection == nil)
                .keyboardShortcut(.delete, modifiers: [])
                .accessibilityLabel(selection.map(removeTitle)
                    ?? fanBarText("移除所选模块", "Remove selected module"))
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )

            keyboardMoveShortcuts

            Spacer(minLength: 8)

            if !modules.isEmpty {
                Text(fanBarFormat("已显示 %d 个，共 %d 个", "%d of %d shown",
                                  modules.count, PanelMonitorModule.allCases.count))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// ⌥⌘↑ / ⌥⌘↓ move the selected module, matching the context menu.
    private var keyboardMoveShortcuts: some View {
        ZStack {
            Button("") { if let selection { move(selection, by: -1) } }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            Button("") { if let selection { move(selection, by: 1) } }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
        }
        .buttonStyle(BorderlessButtonStyle())
        .frame(width: 0, height: 0)
        .opacity(0)
        .disabled(selection == nil)
        .accessibilityHidden(true)
    }

    // MARK: Changes

    private func save(_ next: [PanelMonitorModule]) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1)) {
            rawValue = PanelMonitorPreferences.rawValue(for: next)
        }
    }

    private func add(_ module: PanelMonitorModule) {
        save(modules + [module])
        selection = module
    }

    /// Selects the next module so several can be removed in a row.
    private func remove(_ module: PanelMonitorModule) {
        guard let index = modules.firstIndex(of: module) else { return }
        let next = modules.filter { $0 != module }
        save(next)
        selection = next.isEmpty ? nil : next[min(index, next.count - 1)]
    }

    private func move(_ module: PanelMonitorModule, by offset: Int) {
        guard let next = PanelMonitorPreferences.moving(module, by: offset, in: modules),
              let position = next.firstIndex(of: module) else { return }
        save(next)
        selection = module
        announce(fanBarFormat("%@ 已移到第 %d 项", "%@ moved to position %d", module.title, position + 1))
    }

    private func restoreDefaults() {
        save(PanelMonitorPreferences.defaultModules)
        selection = nil
    }

    private func removeTitle(_ module: PanelMonitorModule) -> String {
        fanBarFormat("移除「%@」", "Remove “%@”", module.title)
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp.keyWindow as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    // MARK: Drag

    private func beginDrag(_ module: PanelMonitorModule) -> NSItemProvider {
        dragging = module
        selection = module
        // A drop outside any module never reaches performDrop; clear the drag once the
        // mouse is up so the placeholder styling doesn't linger.
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            if NSEvent.pressedMouseButtons == 0 {
                timer.invalidate()
                dragging = nil
            }
        }
        return NSItemProvider(object: module.rawValue as NSString)
    }

    private func dropDelegate(for target: PanelMonitorModule) -> PanelMonitorDropDelegate {
        PanelMonitorDropDelegate(target: target, dragging: $dragging) { module, target in
            save(PanelMonitorPreferences.moving(module, to: target, in: modules))
        }
    }
}

/// Entering another module's place moves the dragged one there at once, so the rest reflow
/// live; releasing just ends the drag. Only drags started in this card are accepted.
private struct PanelMonitorDropDelegate: DropDelegate {
    let target: PanelMonitorModule
    @Binding var dragging: PanelMonitorModule?
    let move: (PanelMonitorModule, PanelMonitorModule) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        dragging != nil
    }

    func dropEntered(info _: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Skeleton tile

/// A module's cell drawn as gray blocks: its real structure, no live numbers, and no
/// status colors, so it can't be read as an actual "high" reading.
private struct PanelMonitorSkeletonTile: View {
    let module: PanelMonitorModule
    let showsGrip: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var faint: Color { Color.primary.opacity(isDark ? 0.18 : 0.12) }
    private var mid: Color { Color.primary.opacity(isDark ? 0.28 : 0.20) }
    private var strong: Color { Color.primary.opacity(isDark ? 0.40 : 0.30) }
    private var track: Color { Color.primary.opacity(isDark ? 0.09 : 0.06) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if showsGrip {
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 6))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                Text(module.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                block(width: metaWidth, height: 5, color: faint)
            }
            .frame(height: 12)
            HStack(alignment: .bottom, spacing: 4) {
                block(width: module == .disk ? 48 : 34, height: 12, color: strong)
                if module == .disk {
                    block(width: 16, height: 5, color: faint)
                }
            }
            .frame(height: 14, alignment: .bottom)
            visualization
                .frame(height: 30, alignment: .bottom)
        }
    }

    private var metaWidth: CGFloat {
        switch module {
        case .cpu: 0
        case .memory: 40
        case .gpu: 24
        case .disk: 44
        }
    }

    @ViewBuilder
    private var visualization: some View {
        switch module {
        case .cpu:
            VStack(spacing: 5) {
                // Two core groups sized 8 : 4, like the panel's performance and efficiency cores.
                GeometryReader { proxy in
                    let groupWidth = max(0, proxy.size.width - 6) / 12
                    HStack(spacing: 6) {
                        bars([0.55, 0.45, 0.40, 0.32, 0.26, 0.22, 0.18, 0.15])
                            .frame(width: groupWidth * 8)
                        bars([0.70, 0.78, 0.66, 0.72])
                            .frame(width: groupWidth * 4)
                    }
                }
                .frame(height: 16)
                HStack {
                    block(width: 38, height: 5, color: faint)
                    Spacer(minLength: 0)
                    block(width: 30, height: 5, color: faint)
                }
            }
        case .memory:
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        strong.frame(width: proxy.size.width * 0.56)
                        mid.frame(width: proxy.size.width * 0.16)
                        faint.frame(width: proxy.size.width * 0.22)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 5)
                .background(track)
                .clipShape(Capsule())
                HStack(spacing: 8) {
                    ForEach([strong, mid, faint].indices, id: \.self) { index in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1).fill([strong, mid, faint][index])
                                .frame(width: 5, height: 5)
                            block(width: 16, height: 5, color: faint)
                        }
                    }
                }
            }
        case .gpu, .disk:
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { proxy in
                    strong.frame(width: proxy.size.width * (module == .disk ? 0.9 : 0.28))
                }
                .frame(height: 5)
                .background(track)
                .clipShape(Capsule())
                block(width: module == .disk ? 70 : 48, height: 5, color: faint)
            }
        }
    }

    private func bars(_ fractions: [Double]) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(fractions.indices, id: \.self) { index in
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        strong.frame(height: proxy.size.height * fractions[index])
                    }
                }
                .background(track)
                .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            }
        }
    }

    private func block(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }
}
