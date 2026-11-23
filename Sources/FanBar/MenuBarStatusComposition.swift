import Foundation

/// What the main status item shows for one icon choice and one display mode.
///
/// None drops the glyph whenever a reading is available. Icon-only plus None
/// would otherwise leave this menu-bar-only app with nothing to click, so the
/// item keeps a short visible title.
struct MenuBarStatusComposition: Equatable {
    /// Product name used when hiding the glyph would leave the status item blank.
    static let fallbackTitle = "FanBar"

    let showsGlyph: Bool
    let text: String?

    static func make(
        style: MenuBarIconStyle,
        displayMode: MenuBarDisplayMode,
        reading: String?
    ) -> MenuBarStatusComposition {
        guard style.showsGlyph else {
            let text = displayMode == .iconOnly ? fallbackTitle : (reading ?? fallbackTitle)
            return MenuBarStatusComposition(showsGlyph: false, text: text)
        }
        let text = displayMode == .iconOnly ? nil : reading
        return MenuBarStatusComposition(showsGlyph: true, text: text)
    }
}
