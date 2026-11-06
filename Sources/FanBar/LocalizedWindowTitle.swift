import AppKit
import Combine
import FanBarShared

/// AppKit titles do not participate in SwiftUI's preference observation.
@MainActor
final class LocalizedWindowTitle {
    private var observation: AnyCancellable?

    init(window: NSWindow, chinese: String, english: String) {
        window.title = fanBarText(chinese, english)
        observation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak window] _ in
                Task { @MainActor in
                    window?.title = fanBarText(chinese, english)
                }
            }
    }
}
