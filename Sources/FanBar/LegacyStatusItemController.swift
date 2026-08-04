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
    private var defaultsObservation: NSObjectProtocol?

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
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
        updateButton()
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

        button.image = NSImage(
            systemSymbolName: controller.statusIcon,
            accessibilityDescription: "FanBar"
        ) ?? NSApplication.shared.applicationIconImage
        button.title = text ?? ""
        button.imagePosition = text == nil ? .imageOnly : .imageLeading
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        // Keep icon-only mode compact while allowing AppKit to measure a label
        // when the user enables temperature or RPM in the menu bar.
        statusItem?.length = text == nil
            ? NSStatusItem.squareLength
            : NSStatusItem.variableLength
    }

    private func averageFanSpeed(for controller: FanController) -> String {
        guard !controller.fans.isEmpty else { return "— RPM" }
        let total = controller.fans.map(\.currentRPM).reduce(0, +)
        let average = Int((Double(total) / Double(controller.fans.count)).rounded())
        return FanBarNumberFormatter.grouped(average)
    }
}
