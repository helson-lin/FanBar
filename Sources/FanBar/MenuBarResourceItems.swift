import AppKit
import FanBarShared

/// Which resource items show, and in which style. Missing switches mean off.
struct MenuBarResourcePreferences {
    var defaults: UserDefaults = .standard

    func isEnabled(_ resource: MenuBarResource) -> Bool {
        defaults.bool(forKey: resource.preferenceKey)
    }

    func style(_ resource: MenuBarResource) -> MenuBarResourceStyle {
        MenuBarResourceStyle.resolve(defaults.string(forKey: resource.stylePreferenceKey))
    }
}

extension MenuBarResourceStyle {
    /// Unset reads as the default icon style. A value FanBar no longer offers,
    /// such as the earlier value-only style, reads as the label style.
    static func resolve(_ rawValue: String?) -> MenuBarResourceStyle {
        guard let rawValue else { return .icon }
        return MenuBarResourceStyle(rawValue: rawValue) ?? .label
    }
}

/// Everything one resource status item shows.
struct MenuBarResourceItemContent: Equatable {
    let title: String
    let showsIcon: Bool
    let toolTip: String
    let accessibilityTitle: String
    /// The widest title the item can show. Its width, and so the panel's
    /// anchor, stays put while the value changes.
    let widestTitle: String

    /// The button's own fit for the widest title: AppKit leaves about 2 pt
    /// between an icon and its title, and 5 pt of inset around the title text.
    /// Anything wider shows as a gap next to the neighboring items, which
    /// space themselves already.
    static func length(titleWidth: CGFloat, iconWidth: CGFloat?) -> CGFloat {
        let icon = iconWidth.map { $0 + 2 } ?? 0
        return ceil(titleWidth + icon + 5)
    }

    static func make(
        _ resource: MenuBarResource,
        usage: SystemUsage,
        style: MenuBarResourceStyle
    ) -> MenuBarResourceItemContent {
        let value = resource.valueText(for: usage)
        let showsLabel = style == .label
        return MenuBarResourceItemContent(
            title: showsLabel ? "\(resource.label) \(value)" : value,
            showsIcon: style == .icon,
            toolTip: resource.title,
            accessibilityTitle: "\(resource.title), \(value)",
            widestTitle: showsLabel ? "\(resource.label) 100%" : "100%"
        )
    }
}

/// What a click on one of FanBar's status items does to the panel.
enum MenuBarPanelClick: Equatable {
    case open
    case close
    /// The panel is open under another item and moves to this one.
    case move

    static func action(isShown: Bool, fromAnchorItem: Bool) -> MenuBarPanelClick {
        guard isShown else { return .open }
        return fromAnchorItem ? .close : .move
    }
}

extension NSPopover {
    /// An animated close still reports `isShown` until it finishes, so showing
    /// the popover again right away would be refused.
    func closeImmediately() {
        let animated = animates
        animates = false
        close()
        animates = animated
    }
}

/// Owns the optional resource status items. Every assignment to a status
/// button re-snapshots the menu bar, so only changed properties are written.
@MainActor
final class MenuBarResourceItems {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private let preferences: MenuBarResourcePreferences
    private weak var target: AnyObject?
    private let action: Selector
    private var items: [MenuBarResource: NSStatusItem] = [:]
    private var shown: [MenuBarResource: MenuBarResourceItemContent] = [:]
    private var icons: [MenuBarResource: NSImage] = [:]

    init(preferences: MenuBarResourcePreferences = MenuBarResourcePreferences(), target: AnyObject, action: Selector) {
        self.preferences = preferences
        self.target = target
        self.action = action
    }

    /// Stable per resource, so positions arranged with ⌘-drag stay with the
    /// same item whatever order the items are turned on in.
    nonisolated static func autosaveName(for resource: MenuBarResource) -> String {
        "FanBarResource-\(resource.rawValue)"
    }

    var windows: [NSWindow] {
        items.values.compactMap { $0.button?.window }
    }

    func resource(for button: NSStatusBarButton?) -> MenuBarResource? {
        guard let button else { return nil }
        return items.first { $0.value.button === button }?.key
    }

    /// `willRemove` runs before an item leaves the menu bar, so a panel
    /// anchored to it can close first.
    func update(usage: SystemUsage, willRemove: (NSStatusBarButton) -> Void) {
        for resource in MenuBarResource.allCases {
            guard preferences.isEnabled(resource) else {
                remove(resource, willRemove: willRemove)
                continue
            }
            let item = items[resource] ?? makeItem(for: resource)
            apply(.make(resource, usage: usage, style: preferences.style(resource)), to: item, resource: resource)
        }
    }

    private func makeItem(for resource: MenuBarResource) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName(for: resource)
        // Turning the switch on shows the item even if it was ⌘-dragged out before.
        item.isVisible = true
        item.button?.target = target
        item.button?.action = action
        item.button?.font = Self.font
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imageHugsTitle = true
        items[resource] = item
        return item
    }

    private func remove(_ resource: MenuBarResource, willRemove: (NSStatusBarButton) -> Void) {
        guard let item = items.removeValue(forKey: resource) else { return }
        shown[resource] = nil
        if let button = item.button { willRemove(button) }
        NSStatusBar.system.removeStatusItem(item)
    }

    private func apply(_ content: MenuBarResourceItemContent, to item: NSStatusItem, resource: MenuBarResource) {
        let old = shown[resource]
        guard old != content, let button = item.button else { return }
        if old?.title != content.title { button.title = content.title }
        if old?.showsIcon != content.showsIcon {
            button.image = content.showsIcon ? icon(for: resource) : nil
            button.imagePosition = content.showsIcon ? .imageLeading : .noImage
        }
        if old?.toolTip != content.toolTip { button.toolTip = content.toolTip }
        if old?.accessibilityTitle != content.accessibilityTitle {
            button.setAccessibilityTitle(content.accessibilityTitle)
        }
        if old?.widestTitle != content.widestTitle || old?.showsIcon != content.showsIcon {
            let titleWidth = (content.widestTitle as NSString).size(withAttributes: [.font: Self.font]).width
            let iconWidth = content.showsIcon ? button.image?.size.width ?? 14 : nil
            item.length = MenuBarResourceItemContent.length(titleWidth: titleWidth, iconWidth: iconWidth)
        }
        shown[resource] = content
    }

    private func icon(for resource: MenuBarResource) -> NSImage {
        if let icon = icons[resource] { return icon }
        let icon = resource.icon
        icons[resource] = icon
        return icon
    }
}
