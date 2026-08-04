import AppKit
import SwiftUI

/// Owns the settings window independently from the transient MenuBarExtra popover.
@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?

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
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "FanBar 设置"
            window.contentViewController = hostingController
            // Keep added settings sections visible without coupling the window to a fixed height.
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            window.setContentSize(
                NSSize(width: max(420, fittingSize.width), height: max(330, fittingSize.height))
            )
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            windowController = NSWindowController(window: window)
            shouldCenter = true
        }

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
