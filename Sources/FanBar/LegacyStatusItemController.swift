import AppKit
import Combine
import SwiftUI

/// AppKit status-item fallback used by macOS 11, before SwiftUI's MenuBarExtra.
@MainActor
final class LegacyStatusItemController: NSObject {
    static let shared = LegacyStatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var controller: FanController?
    private var observation: AnyCancellable?
    private var feedbackObservation: AnyCancellable?
    private var defaultsObservation: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private let iconAnimator = MenuBarIconAnimator()
    /// NSPopover keeps its content view alive after closing, so continuous
    /// animations inside it must be told when nobody can see them.
    private let panelVisibility = PanelVisibility()

    func install(controller: FanController) {
        guard statusItem == nil else { return }

        self.controller = controller

        // A square item accommodates only the icon; text modes need their intrinsic width.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "FanBar"
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: PanelRoot(controller: controller, visibility: panelVisibility)
        )
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        popover.contentSize = NSSize(
            width: max(384, fittingSize.width),
            height: max(560, fittingSize.height)
        )

        statusItem = item
        self.popover = popover
        observation = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
        iconAnimator.onFinish = { [weak self] in self?.updateButton() }
        feedbackObservation = controller.$switchFeedback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                self?.handleSwitchFeedback(signal)
            }
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Disabling the preference mid-animation restores the still icon.
                if !SwitchFeedbackPreferences.isEnabled {
                    self?.iconAnimator.stop()
                }
                self?.updateButton()
            }
        }
        updateButton()
    }

    private func handleSwitchFeedback(_ signal: FanController.SwitchFeedbackSignal?) {
        guard let signal, statusItem?.button != nil else { return }
        guard SwitchFeedbackPreferences.isEnabled else { return }
        // The icon already follows the live RPM, so only a failed switch
        // needs an extra cue.
        if case .ended(successfully: false) = signal {
            iconAnimator.flashFailure()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    /// Presents the panel. Also used by onboarding so the first successful
    /// action is performed in FanBar itself instead of a disconnected tutorial.
    func showPopover() {
        guard let button = statusItem?.button, let popover, !popover.isShown else { return }
        // A status-item action does not reliably activate an LSUIElement app.
        // Activate before presentation so dynamic AppKit/SwiftUI colors do not
        // change the first time the user clicks inside the popover.
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.appearance = NSApplication.shared.effectiveAppearance
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
        clearInitialFocus(in: popover)
        startOutsideClickMonitoring()
    }

    /// AppKit hands initial focus to the first control, which draws a focus
    /// ring before the user has touched the keyboard. Start on the panel
    /// itself instead; Tab still reaches every control. SwiftUI may assign
    /// focus once more after the first layout, so clear it again then.
    private func clearInitialFocus(in popover: NSPopover) {
        let window = popover.contentViewController?.view.window
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mouseDownEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        // Local monitoring handles clicks in FanBar's own windows. Preserve
        // clicks inside the popover and on its status button for normal actions.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mouseDownEvents
        ) { [weak self] event in
            guard let self, self.shouldClosePopover(for: event) else { return event }
            self.closePopover(event)
            return event
        }

        // Global monitoring covers the desktop, menu bar, and other apps. This
        // explicitly closes the panel on systems where .transient misses them.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mouseDownEvents
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover(nil)
            }
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover?.isShown == true else { return false }
        let clickedWindow = event.window
        let popoverWindow = popover?.contentViewController?.view.window
        let statusItemWindow = statusItem?.button?.window
        return clickedWindow !== popoverWindow && clickedWindow !== statusItemWindow
    }

    private func closePopover(_ sender: Any?) {
        popover?.performClose(sender)
        stopOutsideClickMonitoring()
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button, let controller else { return }
        let modeRawValue = UserDefaults.standard.string(forKey: MenuBarDisplayMode.preferenceKey)
        let displayMode = MenuBarDisplayMode(rawValue: modeRawValue ?? "") ?? .defaultMode
        let text: String?
        switch displayMode {
        case .iconOnly:
            text = nil
        case .cpuTemperature:
            if let temperature = controller.temperatureHistory.last?.cpuCelsius {
                text = "\(Int(temperature.rounded()))°"
            } else {
                text = "—°"
            }
        case .fanSpeed:
            text = averageFanSpeed(for: controller)
        case .temperatureAndFanSpeed:
            let temperature = controller.temperatureHistory.last?.cpuCelsius
                .map { "\(Int($0.rounded()))°" } ?? "—°"
            text = "\(temperature) · \(averageFanSpeed(for: controller))"
        }

        // Drive the icon with the live fan reading: it spins while the fans
        // run and coasts to a stop when they halt. While any animation is
        // active the animator owns button.image, so the two-second refresh
        // must not clobber the rotating frames.
        if SwitchFeedbackPreferences.isEnabled {
            iconAnimator.update(
                rpm: averageFanRPM(for: controller),
                on: button,
                symbolName: controller.statusIcon
            )
        } else {
            iconAnimator.stop()
        }
        if !iconAnimator.isAnimating {
            button.image = MenuBarIconAnimator.staticIcon(symbol: controller.statusIcon)
        }
        button.title = text ?? ""
        button.imagePosition = text == nil ? .imageOnly : .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        if #available(macOS 11.0, *) {
            button.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 11,
                weight: .medium
            )
        }
        // Keep a stable width once text is enabled. A variable-length status
        // item moves its popover anchor whenever a changing value gains or
        // loses a digit, which makes the menu appear to jump while refreshing.
        let targetLength = statusItemLength(for: displayMode, iconWidth: button.image?.size.width ?? 16)
        if statusItem?.length != targetLength {
            statusItem?.length = targetLength
        }

        // Digits should not change their advance width as the reading changes.
        button.font = text == nil
            ? NSFont.systemFont(ofSize: 12, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    /// Width sized to the widest reading each mode can show (not the current
    /// one), so the popover anchor stays put without leaving wide side gaps.
    private func statusItemLength(for displayMode: MenuBarDisplayMode, iconWidth: CGFloat) -> CGFloat {
        let widestText: String
        switch displayMode {
        case .iconOnly:
            return NSStatusItem.squareLength
        case .cpuTemperature:
            widestText = "100°"
        case .fanSpeed:
            widestText = "8,888"
        case .temperatureAndFanSpeed:
            widestText = "100° · 8,888"
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textWidth = (widestText as NSString).size(withAttributes: [.font: font]).width
        // icon + image/title gap + text + button's horizontal inset on both sides.
        return ceil(iconWidth + 3 + textWidth + 3)
    }

    private func averageFanRPM(for controller: FanController) -> Double {
        guard !controller.fans.isEmpty else { return 0 }
        let total = controller.fans.map(\.currentRPM).reduce(0, +)
        return Double(total) / Double(controller.fans.count)
    }

    private func averageFanSpeed(for controller: FanController) -> String {
        guard !controller.fans.isEmpty else { return "— RPM" }
        let total = controller.fans.map(\.currentRPM).reduce(0, +)
        let average = Int((Double(total) / Double(controller.fans.count)).rounded())
        return FanBarNumberFormatter.grouped(average)
    }
}

extension LegacyStatusItemController: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        panelVisibility.isVisible = true
        controller?.refreshServiceStatus()
    }

    func popoverDidClose(_ notification: Notification) {
        // Also clean up when AppKit closes the transient popover itself.
        stopOutsideClickMonitoring()
        panelVisibility.isVisible = false
    }
}

/// Whether the popover is on screen.
@MainActor
final class PanelVisibility: ObservableObject {
    @Published var isVisible = false
}

/// Passes the popover's visibility into the panel's environment.
private struct PanelRoot: View {
    let controller: FanController
    @ObservedObject var visibility: PanelVisibility

    var body: some View {
        FanMenu(controller: controller)
            .environment(\.isPanelVisible, visibility.isVisible)
    }
}
