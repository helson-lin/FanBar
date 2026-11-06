import Darwin
import Foundation

/// The `PATH` the user's terminal sees, which a GUI app does not inherit:
/// launchd starts FanBar with only `/usr/bin:/bin:/usr/sbin:/sbin`, while
/// Terminal adds whatever `.zprofile` / `.zshrc` (or bash, fish) set.
enum LoginShellPath {
    /// Where `fanbar` resolves for the user's shell, relative to the tool
    /// FanBar installed.
    enum Resolution: Equatable {
        /// The first `fanbar` on PATH is this app's tool (directly or by link).
        case resolvesToTool
        /// Another `fanbar` earlier on PATH wins.
        case shadowed(by: String)
        /// No `fanbar` on PATH at all, e.g. `/usr/local/bin` is missing from it.
        case notOnPath
    }

    /// Runs an interactive login shell once to print its environment. Blocks
    /// for up to `timeout`; call it off the main thread.
    static func read(timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell())
        // Separate flags: fish does not accept a combined `-ilc`.
        process.arguments = ["-i", "-l", "-c", "/usr/bin/env"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        // A background job the rc files started may still hold the pipe open,
        // so read what is buffered without waiting for end-of-file.
        let data = drain(output.fileHandleForReading.fileDescriptor)
        guard let text = String(bytes: data, encoding: .utf8) else { return nil }
        return path(fromEnvironmentOutput: text)
    }

    /// The last `PATH=` line: rc files may print banners before `env` runs.
    static func path(fromEnvironmentOutput output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("PATH=") }
            .map { String($0.dropFirst("PATH=".count)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The first executable `name` along `searchPath`, as the shell finds it.
    static func firstExecutable(
        named name: String,
        in searchPath: String,
        fileManager: FileManager = .default
    ) -> URL? {
        for directory in searchPath.split(separator: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func resolution(
        of name: String,
        in searchPath: String,
        toolURL: URL,
        fileManager: FileManager = .default
    ) -> Resolution {
        guard let found = firstExecutable(named: name, in: searchPath, fileManager: fileManager) else {
            return .notOnPath
        }
        let resolved = found.resolvingSymlinksInPath().standardizedFileURL.path
        let tool = toolURL.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == tool ? .resolvesToTool : .shadowed(by: found.path)
    }

    private static func userShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    private static func drain(_ descriptor: Int32) -> Data {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}
