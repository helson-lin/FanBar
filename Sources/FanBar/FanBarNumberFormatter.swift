import Foundation

/// Locale-independent numeric formatting shared by the menu-bar item and its preview.
///
/// The app supports macOS 11, so this intentionally avoids newer Foundation
/// formatting APIs while still keeping RPM values readable at a glance.
enum FanBarNumberFormatter {
    static func grouped(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let digits = String(abs(value))
        guard digits.count > 3 else { return sign + digits }

        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex)
                ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return sign + groups.joined(separator: ",")
    }
}
