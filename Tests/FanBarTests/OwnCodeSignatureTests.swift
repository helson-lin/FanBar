import FanBarShared
import XCTest

final class OwnCodeSignatureTests: XCTestCase {
    /// The legacy installer trusts this team for the root helper, so it must be
    /// exactly what the system reports for the running process, and nil when
    /// there is none (ad-hoc and Apple platform binaries).
    func testOwnTeamMatchesWhatCodesignReportsForThisProcess() throws {
        let executable = try XCTUnwrap(Bundle.main.executableURL ?? URL(string: CommandLine.arguments[0]))
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", executable.path]
        process.standardError = output
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let reported = text
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
        let expected = reported == "not set" ? nil : reported

        XCTAssertEqual(OwnCodeSignature.teamIdentifier(), expected)
    }
}
