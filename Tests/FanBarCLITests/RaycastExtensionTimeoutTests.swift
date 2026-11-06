import FanBarShared
import Foundation
import Testing
@testable import FanBarCLI

/// The Raycast extension kills `fanbar` after its own timeout, so that timeout
/// must outlast the CLI's worst case: the launch wait plus the reply timeout.
struct RaycastExtensionTimeoutTests {
    private static let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integrations/raycast-extension/src/lib/fanbar.ts", isDirectory: false)

    /// Room for process start-up and JSON parsing on a slow, busy Mac.
    private static let marginMilliseconds = 5_000

    /// The `const TIMEOUT_MS = 150_000;` literal, `_` separators allowed.
    private static func extensionTimeoutMilliseconds() throws -> Int {
        let text = try String(contentsOf: source, encoding: .utf8)
        let pattern = try Regex(#"const\s+TIMEOUT_MS\s*=\s*([0-9_]+)\s*;"#)
        let match = try #require(text.firstMatch(of: pattern), "TIMEOUT_MS not found in \(source.path)")
        let literal = try #require(match.output[1].substring).replacingOccurrences(of: "_", with: "")
        return try #require(Int(literal))
    }

    @Test func extensionTimeoutOutlastsTheCLIsWorstCase() throws {
        let worstCase = CLIConnection.launchConnectTimeout + FanBarCLIContract.replyTimeout
        let required = Int((worstCase * 1_000).rounded(.up)) + Self.marginMilliseconds
        let timeout = try Self.extensionTimeoutMilliseconds()
        #expect(
            timeout >= required,
            "TIMEOUT_MS is \(timeout) ms; fanbar may take \(Int(worstCase)) s, so it needs at least \(required) ms."
        )
    }
}
