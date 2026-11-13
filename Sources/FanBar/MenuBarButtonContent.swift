import AppKit

/// Everything the main status item shows, apart from its icon.
struct MenuBarButtonContent: Equatable {
    let toolTip: String
    /// The readout on one line, or the two-line readout drawn beside the icon.
    let text: String?
    let isStacked: Bool
    let accessibilityTitle: String?
    /// Sized to the widest reading the mode can show, so the panel anchor
    /// does not move as a value gains or loses a digit.
    let length: CGFloat

    var imagePosition: NSControl.ImagePosition {
        text == nil ? .imageOnly : .imageLeading
    }

    /// Digits should not change their advance width as the reading changes.
    var usesDigitFont: Bool {
        text != nil
    }

    @MainActor static func make(
        displayMode: MenuBarDisplayMode,
        text: String?,
        toolTip: String,
        iconWidth: CGFloat
    ) -> MenuBarButtonContent {
        let isStacked = displayMode == .temperatureOverFanSpeed && text != nil
        return MenuBarButtonContent(
            toolTip: toolTip,
            text: text,
            isStacked: isStacked,
            accessibilityTitle: isStacked ? text?.replacingOccurrences(of: "\n", with: ", ") : nil,
            length: length(for: displayMode, iconWidth: iconWidth)
        )
    }

    @MainActor static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    @MainActor static let iconOnlyFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    @MainActor static let stackedFont = NSFont.monospacedDigitSystemFont(
        ofSize: MenuBarDisplayMode.stackedFontSize,
        weight: .medium
    )

    /// An invisible title as wide as the widest stacked line keeps AppKit's own
    /// icon + title layout, so the icon sits where it does in the other modes.
    @MainActor static let stackedPlaceholder = NSAttributedString(string: "8,888", attributes: [
        .font: stackedFont,
        .foregroundColor: NSColor.clear
    ])

    /// Width sized to the widest reading each mode can show (not the current
    /// one), so the popover anchor stays put without leaving wide side gaps.
    @MainActor static func length(for displayMode: MenuBarDisplayMode, iconWidth: CGFloat) -> CGFloat {
        let textWidth: CGFloat
        switch displayMode {
        case .iconOnly:
            return NSStatusItem.squareLength
        case .cpuTemperature:
            textWidth = width(of: "100°")
        case .fanSpeed:
            textWidth = width(of: "8,888")
        case .temperatureAndFanSpeed:
            textWidth = width(of: "100° · 8,888")
        case .temperatureOverFanSpeed:
            // Only the wider of the two lines counts.
            textWidth = stackedPlaceholder.size().width
        }
        // icon + image/title gap + text + button's horizontal inset.
        return ceil(iconWidth + 3 + textWidth + 3)
    }

    @MainActor private static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: digitFont]).width
    }
}

/// Writes `MenuBarButtonContent` to a status button, touching only what
/// changed. Every assignment to a status button, even of an equal value, makes
/// AppKit re-snapshot the item for each display's menu bar, and the content is
/// recomputed on every controller change, usually with nothing new to show.
@MainActor
final class MenuBarButtonWriter {
    private(set) var shown: MenuBarButtonContent?

    /// Returns true when the title layout changed, so a view placed over the
    /// title slot has to be moved.
    @discardableResult
    func apply(_ content: MenuBarButtonContent, to button: NSButton, statusItem: NSStatusItem? = nil) -> Bool {
        let old = shown
        guard old != content else { return false }
        shown = content
        if old?.toolTip != content.toolTip { button.toolTip = content.toolTip }
        if old?.usesDigitFont != content.usesDigitFont {
            button.font = content.usesDigitFont ? MenuBarButtonContent.digitFont : MenuBarButtonContent.iconOnlyFont
        }
        let titleChanged = old?.isStacked != content.isStacked || (!content.isStacked && old?.text != content.text)
        if titleChanged {
            if content.isStacked {
                button.attributedTitle = MenuBarButtonContent.stackedPlaceholder
            } else {
                button.title = content.text ?? ""
            }
        }
        if old?.imagePosition != content.imagePosition { button.imagePosition = content.imagePosition }
        if old?.accessibilityTitle != content.accessibilityTitle {
            button.setAccessibilityTitle(content.accessibilityTitle)
        }
        if let statusItem, statusItem.length != content.length { statusItem.length = content.length }
        return titleChanged || old?.imagePosition != content.imagePosition || old?.length != content.length
    }
}
