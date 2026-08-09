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
    private let iconAnimator = MenuBarIconAnimator()

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
        let hostingController = NSHostingController(
            rootView: FanMenu(controller: controller)
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
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
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
        let targetLength = statusItemLength(for: displayMode)
        if statusItem?.length != targetLength {
            statusItem?.length = targetLength
        }

        // Digits should not change their advance width as the reading changes.
        button.font = text == nil
            ? NSFont.systemFont(ofSize: 12, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    private func statusItemLength(for displayMode: MenuBarDisplayMode) -> CGFloat {
        switch displayMode {
        case .iconOnly:
            NSStatusItem.squareLength
        case .cpuTemperature:
            58
        case .fanSpeed:
            84
        case .temperatureAndFanSpeed:
            120
        }
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
