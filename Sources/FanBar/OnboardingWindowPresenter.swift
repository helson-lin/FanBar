import AppKit
import FanBarShared
import SwiftUI

/// Owns the one-time welcome window independently from the settings window and
/// the transient status-item popover.
@MainActor
final class OnboardingWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowPresenter()

    private var windowController: NSWindowController?
    private var isCompleting = false

    func show() {
        if let window = windowController?.window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = OnboardingCard(
            onOpenMenu: { [weak self] in self?.complete(openMenu: true) },
            onDismiss: { [weak self] in self?.complete(openMenu: false) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = fanBarText("欢迎使用 FanBar", "Welcome to FanBar")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = hostingController
        window.delegate = self
        window.center()
        windowController = NSWindowController(window: window)

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard !isCompleting else { return }
        OnboardingPreferences.complete()
        windowController = nil
    }

    private func complete(openMenu: Bool) {
        guard !isCompleting else { return }
        isCompleting = true
        OnboardingPreferences.complete()
        windowController?.close()
        windowController = nil
        isCompleting = false

        if openMenu {
            DispatchQueue.main.async {
                LegacyStatusItemController.shared.showPopover()
            }
        }
    }
}
