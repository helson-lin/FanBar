import Darwin
import FanBarShared
import Foundation
import Testing
@testable import FanBarCLI

struct CLIArgumentsTests {
    private func parse(_ line: String) -> Result<CLIInvocation, CLIUsageError> {
        CLIArguments.parse(line.split(separator: " ").map(String.init))
    }

    private func request(_ line: String) -> FanBarCLIRequest? {
        guard case .success(let invocation) = parse(line),
              case .request(let request) = invocation.command else { return nil }
        return request
    }

    @Test func noArgumentsShowsHelp() {
        #expect(CLIArguments.parse([]) == .success(CLIInvocation(command: .help)))
        #expect(parse("--help") == .success(CLIInvocation(command: .help)))
    }

    @Test func readCommands() {
        #expect(parse("status") == .success(CLIInvocation(command: .status)))
        #expect(parse("temps --json") == .success(CLIInvocation(command: .temps, json: true)))
        #expect(request("preset list")?.action == .listPresets)
    }

    @Test func holdIsCarriedOnlyWhenAsked() {
        #expect(request("preset set performance")?.hold == false)
        #expect(request("preset set performance --hold")?.hold == true)
        #expect(request("--hold mode fixed 3200") == FanBarCLIRequest(action: .fixed, rpm: 3_200, hold: true))
        #expect(request("mode curve --hold")?.hold == true)
    }

    @Test func holdIsRejectedWhereItMeansNothing() {
        #expect(throws: CLIUsageError.self) { try parse("mode auto --hold").get() }
        #expect(throws: CLIUsageError.self) { try parse("status --hold").get() }
    }

    @Test func customPresetNamesMayContainSpaces() {
        #expect(request("preset set Late Night")?.preset == "Late Night")
    }

    @Test func invalidInputIsAUsageError() {
        for line in ["preset", "preset set", "mode", "mode fixed", "mode fixed -5", "mode fixed fast",
                     "status extra", "launch", "status --force"] {
            #expect(throws: CLIUsageError.self, "\(line)") { try parse(line).get() }
        }
    }

    @Test func noLaunchIsAGlobalOption() throws {
        let invocation = try parse("mode auto --no-launch").get()
        #expect(invocation.noLaunch)
        #expect(invocation.command == .request(FanBarCLIRequest(action: .automatic)))
    }

    @Test func enclosingAppRequiresTheFanBarBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("FanBar.app/Contents")
        let helpers = contents.appendingPathComponent("Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let tool = helpers.appendingPathComponent("fanbar")
        try Data().write(to: tool)
        #expect(CLIConnection.enclosingApp(of: tool) == nil)

        let info: NSDictionary = ["CFBundleIdentifier": FanBarService.appBundleID, "CFBundlePackageType": "APPL"]
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        let link = root.appendingPathComponent("fanbar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        #expect(CLIConnection.enclosingApp(of: link)?.lastPathComponent == "FanBar.app")
    }
}

struct CLIContractTests {
    @Test func requestRoundTrips() throws {
        let request = FanBarCLIRequest(action: .setPreset, preset: "balanced", hold: true)
        let data = try FanBarCLIContract.makeEncoder().encode(request)
        #expect(try FanBarCLIContract.makeDecoder().decode(FanBarCLIRequest.self, from: data) == request)
    }

    @Test func messagesCrossASocket() throws {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        let response = FanBarCLIResponse(ok: true, message: "Fixed 3000 RPM, held until changed")
        let data = try FanBarCLIContract.makeEncoder().encode(response)
        #expect(FanBarCLISocket.writeMessage(data, to: pair[0]))
        let received = try #require(FanBarCLISocket.readMessage(from: pair[1]))
        #expect(try FanBarCLIContract.makeDecoder().decode(FanBarCLIResponse.self, from: received) == response)
    }

    @Test func oversizedMessagesAreRefused() {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[1]) }
        let blob = Data(repeating: UInt8(ascii: "a"), count: FanBarCLIContract.maximumMessageBytes + 10)
        DispatchQueue.global().async {
            _ = FanBarCLISocket.writeMessage(blob, to: pair[0])
            close(pair[0])
        }
        #expect(FanBarCLISocket.readMessage(from: pair[1]) == nil)
    }

    @Test func socketLivesInTheUsersApplicationSupport() {
        let url = FanBarCLIContract.socketURL(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(url.path == "/Users/someone/Library/Application Support/FanBar/cli.sock")
        #expect(FanBarCLISocket.address(for: url.path) != nil)
        #expect(FanBarCLISocket.address(for: String(repeating: "x", count: 200)) == nil)
    }
}

struct CLIOutputTests {
    @Test func presetListAlignsBuiltInsWithoutTrailingSpaces() {
        let response = FanBarCLIResponse(ok: true, message: "", presets: [
            FanBarCLIPreset(id: "builtin:0", key: "silent", name: "静音", builtIn: true, selected: false),
            FanBarCLIPreset(id: "builtin:2", key: "performance", name: "性能", builtIn: true, selected: true),
            FanBarCLIPreset(id: "custom:x", key: "游戏", name: "游戏", builtIn: false, selected: false),
        ])
        #expect(CLIOutput.presets(response) == """
          silent       静音
        * performance  性能
          游戏
        """)
    }
}

struct CLIConnectionPlanTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func notRunningLaunchesUnlessToldNotTo() {
        #expect(CLIConnection.plan(runningSince: nil, now: now, noLaunch: false) == .launch)
        #expect(CLIConnection.plan(runningSince: nil, now: now, noLaunch: true) == .fail(.notRunning))
    }

    @Test func aLongRunningAppGetsAShortGrace() {
        let started = now.addingTimeInterval(-3_600)
        #expect(CLIConnection.plan(runningSince: started, now: now, noLaunch: false) == .wait(2))
        #expect(CLIConnection.plan(runningSince: .distantPast, now: now, noLaunch: true) == .wait(2))
    }

    @Test func aJustLaunchedAppGetsTheRestOfTheColdStart() {
        let started = now.addingTimeInterval(-5)
        #expect(CLIConnection.plan(runningSince: started, now: now, noLaunch: true) == .wait(15))
    }

    /// A background session (SSH, cron) may not see the app through Launch
    /// Services; an answering socket must win even with --no-launch.
    @Test func anAnsweringSocketIsUsedBeforeAskingLaunchServices() throws {
        let directory = URL(fileURLWithPath: "/tmp/fanbar-cli-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("cli.sock").path
        var address = try #require(FanBarCLISocket.address(for: path))
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(listener) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        #expect(listen(listener, 1) == 0)
        let expected = FanBarCLIResponse(ok: true, message: "macOS automatic control")
        let reply = try FanBarCLIContract.makeEncoder().encode(expected)
        DispatchQueue.global().async {
            let client = accept(listener, nil, nil)
            _ = FanBarCLISocket.readMessage(from: client)
            _ = FanBarCLISocket.writeMessage(reply, to: client)
            close(client)
        }
        let result = CLIConnection.send(FanBarCLIRequest(action: .status), noLaunch: true, path: path)
        #expect(result == .success(expected))
    }
}

struct CLITimeoutAndPathTests {
    @Test func theCLIOutwaitsTheAppsWholeBudget() {
        #expect(FanBarCLIContract.replyTimeout > FanBarCLIContract.commandTimeout)
        #expect(FanBarCLIContract.commandTimeout >= FanControlTiming.writeReplyTimeout(
            fanCount: FanControlTiming.maximumFanCount,
            base: 10
        ))
    }

    @Test func aNormalHomeKeepsTheApplicationSupportSocket() {
        let url = FanBarCLIContract.socketURL(
            home: URL(fileURLWithPath: "/Users/someone"),
            userTemporaryDirectory: URL(fileURLWithPath: "/var/folders/ab/xyz/T")
        )
        #expect(url.path == "/Users/someone/Library/Application Support/FanBar/cli.sock")
    }

    @Test func aHomeTooLongForSockaddrFallsBackToTheUserTemporaryDirectory() {
        let home = URL(fileURLWithPath: "/Volumes/Macintosh HD 2/Users/" + String(repeating: "n", count: 60))
        let url = FanBarCLIContract.socketURL(
            home: home,
            userTemporaryDirectory: URL(fileURLWithPath: "/var/folders/ab/xyz/T")
        )
        #expect(url.path == "/var/folders/ab/xyz/T/local.fanbar.cli.sock")
        #expect(FanBarCLISocket.address(for: url.path) != nil)
    }

    @Test func theUserTemporaryDirectoryIsPrivate() throws {
        let directory = try #require(FanBarCLIContract.userTemporaryDirectory())
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
        #expect(attributes[.ownerAccountID] as? UInt32 == getuid())
    }
}

struct CLICopyMismatchTests {
    private let own = URL(fileURLWithPath: "/Applications/FanBar.app")

    @Test func sameCopyIsSilentEvenThroughSymlinks() throws {
        #expect(CLIConnection.copyMismatchWarning(answeredBy: "/Applications/FanBar.app", shippedIn: own) == nil)
        // /tmp is a link to /private/tmp: both spellings are one copy.
        let name = "fanbar-copy-\(UUID().uuidString.prefix(8)).app"
        try FileManager.default.createDirectory(atPath: "/tmp/\(name)", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: "/tmp/\(name)") }
        #expect(CLIConnection.copyMismatchWarning(
            answeredBy: "/private/tmp/\(name)",
            shippedIn: URL(fileURLWithPath: "/tmp/\(name)")
        ) == nil)
    }

    @Test func anotherCopyIsNamed() throws {
        let warning = try #require(CLIConnection.copyMismatchWarning(
            answeredBy: "/Users/someone/Downloads/FanBar.app",
            shippedIn: own
        ))
        #expect(warning.contains("/Users/someone/Downloads/FanBar.app"))
        #expect(warning.contains("/Applications/FanBar.app"))
    }

    @Test func unknownSidesStaySilent() {
        #expect(CLIConnection.copyMismatchWarning(answeredBy: nil, shippedIn: own) == nil)
        #expect(CLIConnection.copyMismatchWarning(answeredBy: "/Applications/FanBar.app", shippedIn: nil) == nil)
    }

    @Test func olderAppsWithoutAPathStillDecode() throws {
        let data = Data(#"{"ok":true,"message":"macOS automatic control"}"#.utf8)
        let response = try FanBarCLIContract.makeDecoder().decode(FanBarCLIResponse.self, from: data)
        #expect(response.appPath == nil)
    }
}
