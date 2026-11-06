import FanBarShared
import SwiftUI

/// A stylized menu bar with FanBar's live status label between the system
/// items, so the display choice is judged in context.
struct MenuBarPreviewStrip: View {
    @ObservedObject var controller: FanController
    let displayMode: MenuBarDisplayMode
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("fanbar.menuBarResource.cpu") private var showCPU = false
    @AppStorage("fanbar.menuBarResource.memory") private var showMemory = false
    @AppStorage("fanbar.menuBarResource.gpu") private var showGPU = false
    @AppStorage("fanbar.menuBarResource.cpu.style") private var cpuStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage("fanbar.menuBarResource.memory.style") private var memoryStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage("fanbar.menuBarResource.gpu.style") private var gpuStyle = MenuBarResourceStyle.icon.rawValue

    private func style(_ resource: MenuBarResource) -> MenuBarResourceStyle {
        let raw: String
        switch resource {
        case .cpu: raw = cpuStyle
        case .memory: raw = memoryStyle
        case .gpu: raw = gpuStyle
        }
        return MenuBarResourceStyle(rawValue: raw) ?? .label
    }

    private func isEnabled(_ resource: MenuBarResource) -> Bool {
        switch resource {
        case .cpu: showCPU
        case .memory: showMemory
        case .gpu: showGPU
        }
    }

    private var wallpaper: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.23, green: 0.30, blue: 0.42), Color(red: 0.34, green: 0.25, blue: 0.43)]
            : [Color(red: 0.62, green: 0.71, blue: 0.84), Color(red: 0.79, green: 0.72, blue: 0.85)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            MenuBarStatusLabel(controller: controller, displayMode: displayMode)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.14)))
            ForEach(MenuBarResource.allCases.filter(isEnabled), id: \.rawValue) { resource in
                resourcePreview(resource, style: style(resource), usage: controller.usage)
            }
            Text(Date(), style: .time)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(wallpaper)
        // Purely illustrative; each option row below carries the same sample,
        // so VoiceOver users lose nothing by skipping it.
        .accessibilityHidden(true)
    }
}

/// One selectable menu bar display style, with its own rendered sample.
struct MenuBarDisplayOptionRow: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    let mode: MenuBarDisplayMode
    let isSelected: Bool
    /// 1-based place in the option list, read out by VoiceOver because
    /// these rows are custom buttons rather than a native radio group.
    let position: Int
    let count: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                // Weight joins the filled radio, so selection never rests on tint alone.
                SettingsRowText(
                    title: mode.title,
                    detail: mode.detail,
                    titleWeight: isSelected ? .medium : .regular
                )
                .foregroundColor(.primary)

                MenuBarStatusLabel(controller: controller, displayMode: mode)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            // With the group's inset, the radio lines up with other rows' text.
            .padding(.horizontal, SettingsChrome.rowHorizontalPadding - SettingsChrome.choiceInset)
            .padding(.vertical, SettingsChrome.rowVerticalPadding)
            .background(SettingsChrome.choiceHighlight(isSelected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected
            ? fanBarFormat("已选择，第 %d 项，共 %d 项", "Selected, %d of %d", position, count)
            : fanBarFormat("第 %d 项，共 %d 项", "%d of %d", position, count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}

/// The icon row of the Menu Bar card. A pop-up menu scales to any number of
/// glyphs; each item shows its glyph beside the name, and the display rows
/// below preview the chosen one at real size.
struct MenuBarIconStylePicker: View {
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @ObservedObject var controller: FanController
    @AppStorage(MenuBarIconStyle.preferenceKey)
    private var selectedRawValue = MenuBarIconStyle.defaultStyle.rawValue

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowText(
                title: fanBarText("图标", "Icon"),
                detail: fanBarText(
                    "由 FanBar 控制风扇时，图标中心变为实心。",
                    "The hub turns solid while FanBar controls the fans."
                )
            )
            Picker(fanBarText("菜单栏图标", "Menu bar icon"), selection: $selectedRawValue) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    HStack {
                        Image(nsImage: style.image(isManual: controller.isManualStatus))
                            .renderingMode(.template)
                        Text(style.title)
                    }
                    .tag(style.rawValue)
                }
            }
            .labelsHidden()
            .id(languageRawValue)
            .frame(minWidth: SettingsChrome.trailingControlMinWidth)
            .fixedSize()
        }
        .settingsRow()
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}

/// Independent resource items are opt-in and do not change the main fan item.
struct MenuBarResourceSettings: View {
    @ObservedObject var controller: FanController
    @AppStorage("fanbar.menuBarResource.cpu") private var showCPU = false
    @AppStorage("fanbar.menuBarResource.memory") private var showMemory = false
    @AppStorage("fanbar.menuBarResource.gpu") private var showGPU = false
    @AppStorage("fanbar.menuBarResource.cpu.style") private var cpuStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage("fanbar.menuBarResource.memory.style") private var memoryStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage("fanbar.menuBarResource.gpu.style") private var gpuStyle = MenuBarResourceStyle.icon.rawValue

    var body: some View {
        SettingsSection(
            title: fanBarText("系统资源", "System resources"),
            footer: fanBarText(
                "每项独立显示在菜单栏中。点击可打开面板并突出对应资源。",
                "Each item appears separately in the menu bar. Click one to open the panel and highlight that resource."
            )
        ) {
            row(.cpu, isOn: $showCPU, style: $cpuStyle)
            SettingsChrome.rowDivider
            row(.memory, isOn: $showMemory, style: $memoryStyle)
            SettingsChrome.rowDivider
            row(.gpu, isOn: $showGPU, style: $gpuStyle)
        }
        .onAppear {
            // Migrate the earlier ambiguous value-only style and invalid values.
            if MenuBarResourceStyle(rawValue: cpuStyle) == nil { cpuStyle = MenuBarResourceStyle.label.rawValue }
            if MenuBarResourceStyle(rawValue: memoryStyle) == nil { memoryStyle = MenuBarResourceStyle.label.rawValue }
            if MenuBarResourceStyle(rawValue: gpuStyle) == nil { gpuStyle = MenuBarResourceStyle.label.rawValue }
        }
    }

    private func row(_ resource: MenuBarResource, isOn: Binding<Bool>, style: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(resource.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(resource.title, selection: style) {
                ForEach(MenuBarResourceStyle.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!isOn.wrappedValue)
            resourcePreview(resource, style: MenuBarResourceStyle(rawValue: style.wrappedValue) ?? .label, usage: controller.usage)
                .frame(width: 65, alignment: .center)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .accessibilityHidden(true)
            Toggle(resource.title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .settingsRow()
    }
}

private func resourcePreview(_ resource: MenuBarResource, style: MenuBarResourceStyle, usage: SystemUsage) -> some View {
    HStack(spacing: 3) {
        if style == .icon {
            Image(nsImage: resource.icon)
                .renderingMode(.template)
                .frame(width: 14, height: 14)
        }
        Text(resource.text(for: usage, style: style))
    }
    .font(.system(size: 12, weight: .medium).monospacedDigit())
}
