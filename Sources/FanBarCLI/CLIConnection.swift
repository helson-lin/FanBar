import AppKit
import Darwin
import FanBarShared
import Foundation

enum CLIConnectionError: Error, Equatable {
    case notRunning
    case appNotFound
    case launchFailed
    /// The app runs but nothing answers: an older FanBar without CLI support.
    case notAccepting
    case transport

    var message: String {
        switch self {
        case .notRunning: "FanBar is not running. Start it, or run without --no-launch."
        case .appNotFound: "Could not find FanBar.app. Install it in /Applications and try again."
        case .launchFailed: "Could not start FanBar.app."
        case .notAccepting: "FanBar is running but does not accept fanbar commands. Update FanBar and try again."
        case .transport: "Lost the connection to FanBar."
        }
    }
}

/// What to do when the socket did not answer on the first try.
enum CLIConnectPlan: Equatable {
    /// The app runs; give its listener this long to come up.
    case wait(TimeInterval)
    case launch
    case fail(CLIConnectionError)
}

/// Finds or starts FanBar.app, then exchanges one request with it.
enum CLIConnection {
    /// A cold start includes the helper status check and first sensor read.
    static let launchConnectTimeout: TimeInterval = 20
    static let runningConnectTimeout: TimeInterval = 2

    static func send(
        _ request: FanBarCLIRequest,
        noLaunch: Bool,
        path: String = FanBarCLIContract.socketURL().path
    ) -> Result<FanBarCLIResponse, CLIConnectionError> {
        // The socket is the source of truth. Launch Services may not list the
        // app at all from an SSH, cron or background launchd session, so only
        // consult it once the socket has not answered.
        var descriptor = connect(path, timeout: 0)
        if descriptor == nil {
            let launchDate = runningAppLaunchDate()
            switch plan(runningSince: launchDate.map { $0 ?? .distantPast }, now: Date(), noLaunch: noLaunch) {
            case .wait(let timeout):
                descriptor = connect(path, timeout: timeout)
            case .launch:
                guard let app = locateApp() else { return .failure(.appNotFound) }
                guard launch(app) else { return .failure(.launchFailed) }
                descriptor = connect(path, timeout: launchConnectTimeout)
            case .fail(let error):
                return .failure(error)
            }
        }
        guard let descriptor else { return .failure(.notAccepting) }
        defer { close(descriptor) }
        guard let body = try? FanBarCLIContract.makeEncoder().encode(request),
              FanBarCLISocket.writeMessage(body, to: descriptor),
              let reply = FanBarCLISocket.readMessage(from: descriptor),
              let response = try? FanBarCLIContract.makeDecoder().decode(FanBarCLIResponse.self, from: reply) else {
            return .failure(.transport)
        }
        return .success(response)
    }

    /// `runningSince` is nil when FanBar is not running, `.distantPast` when
    /// its launch time is unknown. An app that started moments ago (a login
    /// item, another `fanbar`) gets the rest of the cold-start allowance
    /// instead of being reported as too old to accept commands.
    static func plan(runningSince: Date?, now: Date, noLaunch: Bool) -> CLIConnectPlan {
        guard let runningSince else { return noLaunch ? .fail(.notRunning) : .launch }
        let remaining = launchConnectTimeout - now.timeIntervalSince(runningSince)
        return .wait(max(runningConnectTimeout, remaining))
    }

    /// nil: not running. `.some(nil)`: running, launch time unknown.
    private static func runningAppLaunchDate() -> Date?? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: FanBarService.appBundleID)
        guard !apps.isEmpty else { return nil }
        return .some(apps.compactMap(\.launchDate).max())
    }

    /// Prefers the app this tool ships inside (`FanBar.app/Contents/Helpers/fanbar`,
    /// reached through a Homebrew symlink or not), then whatever Launch Services knows.
    static func locateApp() -> URL? {
        if let enclosing = enclosingApp(of: executableURL()) { return enclosing }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: FanBarService.appBundleID)
    }

    static func enclosingApp(of executable: URL?) -> URL? {
        guard let executable else { return nil }
        let app = executable.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Read the plist directly: `Bundle(url:)` caches whatever it first saw at a path.
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard app.pathExtension == "app",
              info?["CFBundleIdentifier"] as? String == FanBarService.appBundleID else { return nil }
        return app
    }

    /// A warning when the app that answered is not the copy this tool ships in,
    /// e.g. an old FanBar left in Downloads or a test build. Silent when either
    /// side is unknown: a `swift run` tool has no app, older apps send no path.
    static func copyMismatchWarning(answeredBy: String?, shippedIn: URL?) -> String? {
        guard let answeredBy, let shippedIn else { return nil }
        let answered = canonicalPath(answeredBy)
        let own = canonicalPath(shippedIn.path)
        guard answered != own else { return nil }
        return "warning: FanBar at \(answered) answered, but this fanbar belongs to \(own). " +
            "Quit the other copy, or run the fanbar inside it."
    }

    /// `realpath` also folds `/tmp` into `/private/tmp`, which
    /// `resolvingSymlinksInPath()` does not do consistently.
    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func executableURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// `open -g` starts the app without stealing focus from the terminal.
    private static func launch(_ app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", app.path]
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Retries until the app's listener is up or the timeout passes.
    private static func connect(_ path: String, timeout: TimeInterval) -> Int32? {
        guard var address = FanBarCLISocket.address(for: path) else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            if connected {
                var enabled: Int32 = 1
                setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
                var wait = timeval(tv_sec: Int(FanBarCLIContract.replyTimeout.rounded(.up)), tv_usec: 0)
                setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
                return descriptor
            }
            close(descriptor)
            // A zero timeout is a single probe: no sleep after it fails.
            guard Date() < deadline else { return nil }
            usleep(200_000)
        }
    }

    static var appVersion: String {
        locateApp().flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            ?? "unknown"
    }
}
