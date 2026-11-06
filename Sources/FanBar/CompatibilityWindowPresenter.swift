import AppKit
import FanBarShared
import SwiftUI

/// A single resizable diagnostic window shared by settings and onboarding.
@MainActor
final class CompatibilityWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = CompatibilityWindowPresenter()
    private var windowController: NSWindowController?
    private var localizedTitle: LocalizedWindowTitle?
    private var hostingView: NSHostingView<DeviceCompatibilityView>?
    private weak var controller: FanController?

    @discardableResult
    func show(controller: FanController) -> NSWindow {
        let window: NSWindow
        if let existing = windowController?.window {
            if self.controller !== controller {
                self.controller = controller
                hostingView?.rootView = content(controller)
            }
            window = existing
        } else {
            self.controller = controller
            let visible = (NSApplication.shared.keyWindow?.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            let hosting = CompatibilityHostingView(rootView: content(controller))
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            hostingView = hosting
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: min(740, visible.width - 60), height: min(780, visible.height - 100)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            let container = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            window.contentView = container
            window.contentMinSize = NSSize(width: SettingsChrome.contentWidth, height: 420)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            windowController = NSWindowController(window: window)
            localizedTitle = LocalizedWindowTitle(window: window, chinese: "设备兼容性", english: "Device Compatibility")
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        }
        window.title = fanBarText("设备兼容性", "Device Compatibility")
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func close() {
        windowController?.close()
    }

    func windowWillClose(_ notification: Notification) {
        controller?.cancelCompatibilityControlTest()
        hostingView = nil
        windowController = nil
        localizedTitle = nil
        controller = nil
    }

    private func content(_ controller: FanController) -> DeviceCompatibilityView {
        DeviceCompatibilityView(controller: controller, onClose: { [weak self] in self?.close() })
    }
}

/// The window owns its size; SwiftUI's natural document height must not resize it.
private final class CompatibilityHostingView: NSHostingView<DeviceCompatibilityView> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
