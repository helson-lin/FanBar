import Foundation

/// Retains an operation's values while resolving its copy in the current
/// language. Resolvers must capture controller references weakly.
struct LocalizedControlText: Equatable {
    private let resolve: () -> String

    init(_ resolve: @escaping () -> String) {
        self.resolve = resolve
    }

    var text: String { resolve() }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }
}
