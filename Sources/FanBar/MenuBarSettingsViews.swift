import FanBarShared
import SwiftUI

enum MenuBarResourcePreviewLayout {
    static let horizontalInset: CGFloat = 8
    static let iconWidth: CGFloat = 14
    static let contentSpacing: CGFloat = 3
}

/// A stylized menu bar with FanBar's live status label between the system
/// items, so the display choice is judged in context.
struct MenuBarPreviewStrip: View {
    @ObservedObject var controller: FanController
    let displayMode: MenuBarDisplayMode
    @Environment(\.colorScheme) private var colorScheme

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
            ForEach(MenuBarResource.allCases, id: \.rawValue) { resource in
                MenuBarResourcePreviewItem(resource: resource, usage: controller.usage)
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

/// The icon row of the Menu Bar card. A pop-up menu scales to any number of
/// glyphs; each item shows its glyph beside the name.
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
                    "由 FanBar 控制风扇时，图标中心变为实心。选择「无」则隐藏图标。",
                    "The hub turns solid while FanBar controls the fans. None hides the icon."
                )
            )
            Picker(fanBarText("菜单栏图标", "Menu bar icon"), selection: Binding(
                get: { MenuBarIconStyle.stored(selectedRawValue).rawValue },
                set: { selectedRawValue = $0 }
            )) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    HStack {
                        if style.showsGlyph {
                            Image(nsImage: style.image(isManual: controller.isManualStatus))
                                .renderingMode(.template)
                        }
                        Text(style.title)
                    }
                    .tag(style.rawValue)
                }
            }
            .labelsHidden()
            .id(languageRawValue)
            .fixedSize()
        }
        .settingsRow()
        .environment(\.locale, (FanBarLanguage(rawValue: languageRawValue) ?? .system).locale)
    }
}

/// Independent resource items are opt-in and do not change the main fan item.
struct MenuBarResourceSettings: View {
    @ObservedObject var controller: FanController
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue

    @AppStorage(MenuBarResource.cpu.stylePreferenceKey) private var cpuStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage(MenuBarResource.memory.stylePreferenceKey) private var memoryStyle = MenuBarResourceStyle.icon.rawValue
    @AppStorage(MenuBarResource.gpu.stylePreferenceKey) private var gpuStyle = MenuBarResourceStyle.icon.rawValue

    private var previewStyles: [MenuBarResourceStyle] {
        [cpuStyle, memoryStyle, gpuStyle].map(MenuBarResourceStyle.resolve)
    }

    var body: some View {
        SettingsSection(
            title: fanBarText("系统资源", "System resources"),
            footer: fanBarText(
                "每项独立显示在菜单栏中。点击可打开面板并突出对应资源。",
                "Each item appears separately in the menu bar. Click one to open the panel and highlight that resource."
            )
        ) {
            ForEach(Array(MenuBarResource.allCases.enumerated()), id: \.element.rawValue) { index, resource in
                if index > 0 { SettingsChrome.rowDivider }
                MenuBarResourceSettingsRow(resource: resource, usage: controller.usage, previewStyles: previewStyles)
            }
        }
        // The section owns translated header and footer text as well as rows.
        .id(languageRawValue)
    }
}

/// One resource's switch, style and live sample, bound to that resource's own keys.
private struct MenuBarResourceSettingsRow: View {
    let resource: MenuBarResource
    let usage: SystemUsage
    let previewStyles: [MenuBarResourceStyle]
    /// Read so the row repaints when the interface language changes, even when
    /// the reading it shows has not.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @AppStorage private var isOn: Bool
    @AppStorage private var styleRawValue: String

    init(resource: MenuBarResource, usage: SystemUsage, previewStyles: [MenuBarResourceStyle]) {
        self.resource = resource
        self.usage = usage
        self.previewStyles = previewStyles
        _isOn = AppStorage(wrappedValue: false, resource.preferenceKey)
        _styleRawValue = AppStorage(wrappedValue: MenuBarResourceStyle.icon.rawValue, resource.stylePreferenceKey)
    }

    private var style: MenuBarResourceStyle { MenuBarResourceStyle.resolve(styleRawValue) }

    var body: some View {
        HStack(spacing: 10) {
            Text(resource.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(resource.title, selection: $styleRawValue) {
                ForEach(MenuBarResourceStyle.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .labelsHidden()
            // The pop-up button caches its item titles; rebuild it per language,
            // as the icon style picker does.
            .id(languageRawValue)
            .fixedSize()
            .disabled(!isOn)
            MenuBarResourcePreviewPill(resource: resource, style: style, usage: usage, previewStyles: previewStyles)
            Toggle(resource.title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .settingsRow()
        .onAppear {
            // A style FanBar no longer offers is shown as the label style; save
            // that, so the picker has a selection.
            if MenuBarResourceStyle(rawValue: styleRawValue) == nil { styleRawValue = style.rawValue }
        }
    }
}

/// Reserve the width of 100% without making short icon previews unnecessarily wide.
struct MenuBarResourcePreviewPill: View {
    let resource: MenuBarResource
    let style: MenuBarResourceStyle
    let usage: SystemUsage
    let previewStyles: [MenuBarResourceStyle]

    var body: some View {
        ZStack(alignment: .leading) {
            resourcePreview(resource, style: style, usage: usage)
            ForEach(Array(MenuBarResource.allCases.enumerated()), id: \.element.rawValue) { index, candidate in
                let candidateStyle = previewStyles[index]
                HStack(spacing: MenuBarResourcePreviewLayout.contentSpacing) {
                    if candidateStyle == .icon {
                        Color.clear.frame(width: MenuBarResourcePreviewLayout.iconWidth, height: 14)
                    }
                    Text(MenuBarResourceItemContent.make(candidate, usage: usage, style: candidateStyle).widestTitle)
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .hidden()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, MenuBarResourcePreviewLayout.horizontalInset)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityHidden(true)
    }
}

/// A resource item in the preview strip, shown only while its switch is on.
private struct MenuBarResourcePreviewItem: View {
    let resource: MenuBarResource
    let usage: SystemUsage
    /// Read so the translated memory label follows a language change.
    @AppStorage(FanBarLanguage.preferenceKey)
    private var languageRawValue = FanBarLanguage.defaultValue
    @AppStorage private var isOn: Bool
    @AppStorage private var styleRawValue: String

    init(resource: MenuBarResource, usage: SystemUsage) {
        self.resource = resource
        self.usage = usage
        _isOn = AppStorage(wrappedValue: false, resource.preferenceKey)
        _styleRawValue = AppStorage(wrappedValue: MenuBarResourceStyle.icon.rawValue, resource.stylePreferenceKey)
    }

    var body: some View {
        if isOn {
            resourcePreview(resource, style: MenuBarResourceStyle.resolve(styleRawValue), usage: usage)
        }
    }
}

private func resourcePreview(_ resource: MenuBarResource, style: MenuBarResourceStyle, usage: SystemUsage) -> some View {
    HStack(spacing: MenuBarResourcePreviewLayout.contentSpacing) {
        if style == .icon {
            Image(nsImage: resource.icon)
                .renderingMode(.template)
                .frame(width: MenuBarResourcePreviewLayout.iconWidth, height: 14)
        }
        Text(resource.text(for: usage, style: style))
    }
    .font(.system(size: 12, weight: .medium).monospacedDigit())
}
