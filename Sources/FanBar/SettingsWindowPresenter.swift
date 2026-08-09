import AppKit
import FanBarShared
import SwiftUI

/// Owns the settings window independently from the transient MenuBarExtra popover.
@MainActor
final class SettingsWindowPresenter: NSObject {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?
    private let tabsItemIdentifier = NSToolbarItem.Identifier("fanbar.settings.tabs")
    private weak var tabSegmentedControl: NSSegmentedControl?
    private var lastSelectedTabRawValue = SettingsTab.cooling.rawValue
    private var defaultsObservation: NSObjectProtocol?

    @discardableResult
    func show(controller: FanController) -> NSWindow {
        let window: NSWindow
        let shouldCenter: Bool
        if let existing = windowController?.window {
            window = existing
            shouldCenter = false
        } else {
            let hostingController = NSHostingController(
                rootView: FanBarSettingsView(controller: controller)
            )
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            installToolbar(on: window)
            // Keep added settings sections visible without coupling the window to a fixed height.
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            window.setContentSize(
                NSSize(width: max(460, fittingSize.width), height: max(240, fittingSize.height))
            )
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
            // AppKit may apply its initial cascade after the first order-front call.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.centerOnActiveScreen(window)
            }
        }
        return window
    }

    func close() {
        windowController?.close()
    }

    func updateTitle() {
        guard let window = windowController?.window else { return }
        window.title = fanBarText("FanBar 设置", "FanBar Settings")
        if let control = tabSegmentedControl {
            for (index, tab) in SettingsTab.allCases.enumerated() where index < control.segmentCount {
                control.setToolTip(tab.title, forSegment: index)
            }
        }
    }

    // MARK: - Toolbar

    /// A native NSSegmentedControl floats in the toolbar area with no chrome
    /// around it — no preference-style pill, just the control itself. Selection
    /// writes to UserDefaults so SwiftUI swaps the visible content.
    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "fanbar.settings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        // Leave toolbarStyle at default — .preference would add a competing
        // background tint and pull focus away from the segmented control.
        lastSelectedTabRawValue = UserDefaults.standard.string(forKey: SettingsTab.preferenceKey)
            ?? SettingsTab.cooling.rawValue
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Covers external/preference-key writes that don't go through the toolbar.
                self?.applySelectedTabChange()
            }
        }
    }

    /// Single path for tab changes: update the segmented control once, then resize
    /// after SwiftUI has applied the new `@AppStorage` body on the next main turn.
    /// Previously `syncTabSelection` and `resizeForCurrentTab` both gated on and
    /// wrote `lastSelectedTabRawValue`, so resize always no-oped after sync.
    private func applySelectedTabChange() {
        let rawValue = UserDefaults.standard.string(forKey: SettingsTab.preferenceKey)
            ?? SettingsTab.cooling.rawValue
        guard rawValue != lastSelectedTabRawValue else { return }
        lastSelectedTabRawValue = rawValue

        if let control = tabSegmentedControl,
           let tab = SettingsTab(rawValue: rawValue),
           let index = SettingsTab.allCases.firstIndex(of: tab),
           control.selectedSegment != index {
            control.selectedSegment = index
        }

        // Fitting size is only reliable after SwiftUI swaps tab content.
        resizeToFitContentSoon()
    }

    @objc private func selectTabSegment(_ sender: NSSegmentedControl) {
        guard SettingsTab.allCases.indices.contains(sender.selectedSegment) else { return }
        let tab = SettingsTab.allCases[sender.selectedSegment]
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.preferenceKey)
        applySelectedTabChange()
    }

    /// Public entry for SwiftUI panes that change height (e.g. Advanced disclosure).
    func resizeToFitContentSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.resizeWindowToFitContent(animated: true)
        }
    }

    private func resizeWindowToFitContent(animated: Bool = true) {
        guard let window = windowController?.window,
              let contentView = window.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        var newFrame = window.frameRect(
            forContentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: max(460, fittingSize.width),
                    height: max(240, fittingSize.height)
                )
            )
        )
        guard abs(newFrame.height - window.frame.height) > 1
            || abs(newFrame.width - window.frame.width) > 1 else { return }
        newFrame.origin.x = window.frame.minX
        newFrame.origin.y = window.frame.maxY - newFrame.height
        window.setFrame(newFrame, display: true, animate: animated)
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
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
}

extension SettingsWindowPresenter: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, tabsItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == tabsItemIdentifier else { return nil }
        let control = NSSegmentedControl()
        control.segmentCount = SettingsTab.allCases.count
        control.trackingMode = .selectOne
        // .automatic adopts the current macOS segmented-control style,
        // which is intentionally quiet: only the selected segment gets
        // a subtle highlight, the rest float against the toolbar.
        control.segmentStyle = .automatic
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        for (index, tab) in SettingsTab.allCases.enumerated() {
            let image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)?
                .withSymbolConfiguration(imageConfig) ?? NSImage()
            control.setImage(image, forSegment: index)
            control.setToolTip(tab.title, forSegment: index)
            control.setWidth(36, forSegment: index)
        }
        let savedTab = UserDefaults.standard.string(forKey: SettingsTab.preferenceKey)
            .flatMap(SettingsTab.init(rawValue:)) ?? .menuBar
        control.selectedSegment = SettingsTab.allCases.firstIndex(of: savedTab) ?? 0
        control.target = self
        control.action = #selector(selectTabSegment(_:))
        control.sizeToFit()
        tabSegmentedControl = control

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = control
        item.minSize = control.frame.size
        item.maxSize = control.frame.size
        return item
    }
}
