import Foundation
import Testing
@testable import FanBar

struct LoginShellPathTests {
    @Test func takesTheLastPathLineAfterRcNoise() {
        let output = """
        Welcome back!
        PATH=/from/a/banner
        HOME=/Users/someone
        PATH=/Users/someone/.local/bin:/usr/local/bin:/usr/bin
        SHELL=/bin/zsh
        """
        #expect(LoginShellPath.path(fromEnvironmentOutput: output) == "/Users/someone/.local/bin:/usr/local/bin:/usr/bin")
        #expect(LoginShellPath.path(fromEnvironmentOutput: "HOME=/x\nPATH=\n") == nil)
    }

    @Test func resolvesLikeTheShell() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("FanBar.app/Contents/Helpers/fanbar")
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let empty = root.appendingPathComponent("empty")
        for directory in [tool.deletingLastPathComponent(), first, second, empty] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        // A non-executable file and a directory named fanbar are skipped, as the shell does.
        try Data().write(to: first.appendingPathComponent("fanbar"))
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("fanbar"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent("fanbar"), withDestinationURL: tool)

        let searchPath = "\(empty.path)::\(first.path):\(second.path)"
        #expect(LoginShellPath.firstExecutable(named: "fanbar", in: searchPath)?.path == second.appendingPathComponent("fanbar").path)
        #expect(LoginShellPath.resolution(of: "fanbar", in: searchPath, toolURL: tool) == .resolvesToTool)
        #expect(LoginShellPath.resolution(of: "fanbar", in: "/usr/bin", toolURL: tool) == .notOnPath)

        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: other.appendingPathComponent("fanbar"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        #expect(LoginShellPath.resolution(of: "fanbar", in: "\(other.path):\(second.path)", toolURL: tool)
            == .shadowed(by: other.appendingPathComponent("fanbar").path))
    }

    @Test func keepsTheLoginShellOutputReadableOnlyByItsOwner() throws {
        let created = try #require(LoginShellPath.createOutputFile())
        defer {
            try? created.handle.close()
            try? FileManager.default.removeItem(at: created.url)
        }
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: created.url.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.intValue & 0o777 == 0o600)
    }

    @Test func readsAnInteractiveLoginShell() throws {
        let path = try #require(
            LoginShellPath.run(shell: URL(fileURLWithPath: "/bin/sh"), timeout: 10)
        )
        #expect(path.split(separator: ":").contains("/usr/bin"))
    }

    @Test func readsOutputLargerThanAPipeBuffer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let shell = root.appendingPathComponent("shell")
        try """
        #!/bin/sh
        /usr/bin/awk 'BEGIN { for (i = 0; i < 100000; i++) printf "x" }'
        printf '\\nPATH=/usr/bin:/bin\\n'
        """.write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let path = try #require(LoginShellPath.run(shell: shell, timeout: 5))

        #expect(path == "/usr/bin:/bin")
    }
}
