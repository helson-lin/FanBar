import AppKit
import FanBarShared
import SwiftUI

/// Keeps the fitted settings content inside the active screen while preserving
/// the compact natural height of shorter tabs.
enum SettingsWindowSizing {
    static let contentWidth: CGFloat = 560
    static let minimumContentSize = NSSize(width: contentWidth, height: 240)
    /// Tall panes scroll instead of growing the window past this height.
    static let preferredMaximumHeight: CGFloat = 600
    private static let verticalChromeAllowance: CGFloat = 80

    static func contentSize(
        fittingSize: NSSize,
        visibleScreenSize: NSSize
    ) -> NSSize {
        let maximumHeight = max(
            minimumContentSize.height,
            min(
                preferredMaximumHeight,
                visibleScreenSize.height - verticalChromeAllowance
            )
        )
        return NSSize(
            width: max(minimumContentSize.width, fittingSize.width),
            height: min(
                max(minimumContentSize.height, fittingSize.height),
                maximumHeight
            )
        )
    }
}

/// Owns the settings window independently from the transient MenuBarExtra popover.
@MainActor
final class SettingsWindowPresenter: NSObject {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?
    private var settingsHostingController: NSHostingController<FanBarSettingsView>?
    private var lastSelectedTabRawValue = SettingsTab.cooling.rawValue
    private var defaultsObservation: NSObjectProtocol?

    @discardableResult
    func show(controller: FanController) -> NSWindow {
        let rootView = FanBarSettingsView(controller: controller)
        let window: NSWindow
        let shouldCenter: Bool
        if let existing = windowController?.window,
           let hosting = settingsHostingController {
            // Always refresh rootView so settings observe the live controller state.
            hosting.rootView = rootView
            window = existing
            shouldCenter = false
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            settingsHostingController = hostingController
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsWindowSizing.contentWidth, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            installToolbar(on: window)
            // Keep added settings sections visible without coupling the window to a fixed height.
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            window.setContentSize(SettingsWindowSizing.contentSize(
                fittingSize: fittingSize,
                visibleScreenSize: activeScreen()?.visibleFrame.size
                    ?? NSScreen.main?.visibleFrame.size
                    ?? fittingSize
            ))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            windowController = NSWindowController(window: window)
            shouldCenter = true
        }

        // Keep the AppKit title bar in sync with the SwiftUI language picker.
        updateTitle()

        // LSUIElement apps do not activate automatically when their menu closes.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if shouldCenter {
            window.contentView?.layoutSubtreeIfNeeded()
            centerOnActiveScreen(window)
            // Start on the window itself: AppKit otherwise hands initial focus
            // to the first control, which draws a focus ring around it before
            // the user has touched the keyboard. Tab still reaches every control.
            window.makeFirstResponder(nil)
            // AppKit may apply its initial cascade after the first order-front call.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.centerOnActiveScreen(window)
                window.makeFirstResponder(nil)
            }
        }
        resizeToFitContentSoon()
        return window
    }

    func close() {
        windowController?.close()
    }

    func updateTitle() {
        guard let window = windowController?.window else { return }
        window.title = fanBarText("FanBar 设置", "FanBar Settings")
        for item in window.toolbar?.items ?? [] {
            guard let tab = tab(for: item.itemIdentifier) else { continue }
            item.label = tab.title
            item.paletteLabel = tab.title
            item.toolTip = tab.title
        }
    }

    // MARK: - Toolbar

    /// Preference-style toolbar: each pane is a labeled icon, so where a tab
    /// leads is readable without hovering. AppKit owns the selected state.
    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "fanbar.settings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        lastSelectedTabRawValue = UserDefaults.standard.string(
            forKey: SettingsTab.preferenceKey
        ) ?? SettingsTab.cooling.rawValue
        toolbar.selectedItemIdentifier = tabItemIdentifier(
            SettingsTab(rawValue: lastSelectedTabRawValue) ?? .cooling
        )
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySelectedTabChange()
            }
        }
    }

    private func tabItemIdentifier(_ tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("fanbar.settings.tab.\(tab.rawValue)")
    }

    private func tab(for identifier: NSToolbarItem.Identifier) -> SettingsTab? {
        SettingsTab.allCases.first { tabItemIdentifier($0) == identifier }
    }

    /// Synchronizes AppStorage/keyboard changes back to the toolbar's selected
    /// item. Content resizing is requested by the SwiftUI view itself.
    private func applySelectedTabChange() {
        let rawValue = UserDefaults.standard.string(forKey: SettingsTab.preferenceKey)
            ?? SettingsTab.cooling.rawValue
        guard rawValue != lastSelectedTabRawValue else { return }
        lastSelectedTabRawValue = rawValue

        if let tab = SettingsTab(rawValue: rawValue) {
            windowController?.window?.toolbar?.selectedItemIdentifier = tabItemIdentifier(tab)
        }
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = tab(for: sender.itemIdentifier) else { return }
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.preferenceKey)
        applySelectedTabChange()
    }

    /// Public entry for SwiftUI panes that change height (e.g. Advanced disclosure).
    func resizeToFitContentSoon(animated: Bool = true) {
        // Large window-size changes are static when the system Reduce Motion
        // preference is enabled; state and focus feedback remain intact.
        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.async { [weak self] in
            self?.resizeWindowToFitContent(animated: shouldAnimate)
        }
    }

    private func resizeWindowToFitContent(animated: Bool = true) {
        guard let window = windowController?.window,
              let contentView = window.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        let visibleScreenSize = window.screen?.visibleFrame.size
            ?? activeScreen()?.visibleFrame.size
            ?? NSScreen.main?.visibleFrame.size
            ?? fittingSize
        let contentSize = SettingsWindowSizing.contentSize(
            fittingSize: fittingSize,
            visibleScreenSize: visibleScreenSize
        )
        var newFrame = window.frameRect(
            forContentRect: NSRect(
                origin: .zero,
                size: contentSize
            )
        )
        guard abs(newFrame.height - window.frame.height) > 1
            || abs(newFrame.width - window.frame.width) > 1 else { return }
        newFrame.origin.x = window.frame.minX
        newFrame.origin.y = window.frame.maxY - newFrame.height
        window.setFrame(newFrame, display: true, animate: animated)
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let screen = activeScreen() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

extension SettingsWindowPresenter: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(tabItemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = tab(for: itemIdentifier) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(
            systemSymbolName: tab.symbol,
            accessibilityDescription: tab.title
        )
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }
}
