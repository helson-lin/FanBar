import Foundation

/// Preference storage for the menu-bar fan activity animation (the icon
/// spins while the fans run; a failed switch flashes it).
enum SwitchFeedbackPreferences {
    static let preferenceKey = "fanbar.switchFeedbackAnimationEnabled"

    /// Enabled by default; only an explicit `false` turns the animation off.
    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: preferenceKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: preferenceKey)
    }
}
