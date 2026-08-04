import Foundation

/// User-selectable language for the menu-bar app and its helper messages.
public enum FanBarLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case chinese

    public static let preferenceKey = "fanbar.language"
    public static let defaultValue = FanBarLanguage.system.rawValue

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .chinese: "简体中文"
        }
    }

    /// Resolve the system option at lookup time so a preference change is
    /// reflected without rebuilding or replacing the app bundle.
    public static var current: FanBarLanguage {
        if let rawValue = UserDefaults.standard.string(forKey: preferenceKey),
           let stored = FanBarLanguage(rawValue: rawValue),
           stored != .system {
            return stored
        }

        let languageCode = Locale.current.languageCode?.lowercased() ?? "en"
        return languageCode.hasPrefix("zh") ? .chinese : .english
    }

    public var isEnglish: Bool { self == .english }
}

@inline(__always)
public func fanBarText(_ chinese: String, _ english: String) -> String {
    FanBarLanguage.current.isEnglish ? english : chinese
}

@inline(__always)
public func fanBarFormat(
    _ chinese: String,
    _ english: String,
    _ arguments: CVarArg...
) -> String {
    let template = FanBarLanguage.current.isEnglish ? english : chinese
    return String(format: template, arguments: arguments)
}
