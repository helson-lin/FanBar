import AppKit

/// Builds the status-item reading independently of live controller state.
enum MenuBarStatusReadout {
    static func make(displayMode: MenuBarDisplayMode, temperature: String, fanSpeed: String) -> String? {
        switch displayMode {
        case .iconOnly:
            nil
        case .cpuTemperature:
            temperature
        case .fanSpeed:
            fanSpeed
        case .temperatureAndFanSpeed:
            "\(temperature) · \(fanSpeed)"
        case .temperatureOverFanSpeed:
            "\(temperature)\n\(fanSpeed)"
        }
    }
}

/// Aligns the stacked-text overlay with the title slot after AppKit has laid
/// out the resized status item.
@MainActor
enum StackedStatusLabelLayout {
    @discardableResult
    static func align(in button: NSButton, leadingConstraint: NSLayoutConstraint?) -> CGFloat? {
        button.layoutSubtreeIfNeeded()
        guard let cell = button.cell else { return nil }
        let leading = ceil(cell.titleRect(forBounds: button.bounds).minX)
        guard leadingConstraint?.constant != leading else { return leading }
        leadingConstraint?.constant = leading
        button.layoutSubtreeIfNeeded()
        return leading
    }
}

/// Applies the icon choice and live animation state to the main status button.
@MainActor
enum MenuBarIconUpdate {
    struct Presentation {
        let style: MenuBarIconStyle
        let showsGlyph: Bool
        let switchFeedbackEnabled: Bool
        let rpm: Double
        let isManual: Bool
    }

    static func apply(
        _ presentation: Presentation,
        animator: MenuBarIconAnimator,
        on button: NSButton,
        stillIcon: () -> NSImage
    ) {
        guard presentation.showsGlyph else {
            animator.stop()
            if button.image != nil { button.image = nil }
            return
        }

        if presentation.switchFeedbackEnabled {
            animator.update(
                rpm: presentation.rpm,
                on: button,
                style: presentation.style,
                isManual: presentation.isManual
            )
        } else {
            animator.stop()
        }
        guard !animator.isAnimating else { return }

        let still = stillIcon()
        // Assigning even an equal new image re-snapshots every menu bar.
        if button.image !== still { button.image = still }
    }
}
