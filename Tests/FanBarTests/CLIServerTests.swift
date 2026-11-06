import Darwin
import FanBarShared
import XCTest
@testable import FanBar

/// Drives a real `CLIServer` over its socket, the way the `fanbar` tool does.
@MainActor
final class CLIServerTests: XCTestCase {
    private var server: CLIServer?
    private var socketURL = URL(fileURLWithPath: "/tmp")

    override func setUp() async throws {
        // sockaddr_un holds ~104 bytes, too few for some temporary directories.
        socketURL = URL(fileURLWithPath: "/tmp/fanbar-test-\(UUID().uuidString.prefix(8))/cli.sock")
        let source = FakeFanReadingSource()
        let controller = FanController(
            notificationCenter: nil,
            widgetSnapshotDestination: .disabled,
            makeReadingSource: { source }
        )
        controller.refresh()
        let server = CLIServer()
        server.start(controller: controller, socketURL: socketURL)
        self.server = server
    }

    override func tearDown() async throws {
        server?.stop()
        try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
    }

    private func send(_ request: FanBarCLIRequest) async throws -> FanBarCLIResponse {
        let path = socketURL.path
        // Blocking socket calls stay off the main actor, which serves the request.
        let reply = await Task.detached { () -> Data? in
            guard var address = FanBarCLISocket.address(for: path) else { return nil }
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(descriptor) }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            guard connected,
                  let body = try? FanBarCLIContract.makeEncoder().encode(request),
                  FanBarCLISocket.writeMessage(body, to: descriptor) else { return nil }
            return FanBarCLISocket.readMessage(from: descriptor)
        }.value
        let data = try XCTUnwrap(reply)
        return try FanBarCLIContract.makeDecoder().decode(FanBarCLIResponse.self, from: data)
    }

    func testSocketIsPrivateToTheUser() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testStatusReportsLiveReadings() async throws {
        let response = try await send(FanBarCLIRequest(action: .status))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.status?.mode, .automatic)
        XCTAssertEqual(response.status?.fans.map(\.currentRPM), [1_850, 1_900])
        XCTAssertEqual(response.status?.cpuCelsius, 52)
        XCTAssertEqual(response.appPath, Bundle.main.bundleURL.resolvingSymlinksInPath().path)
    }

    func testPresetListMarksTheSelectedPreset() async throws {
        let response = try await send(FanBarCLIRequest(action: .listPresets))
        let presets = try XCTUnwrap(response.presets)
        XCTAssertEqual(presets.prefix(4).map(\.key), ["silent", "balanced", "performance", "extreme"])
        XCTAssertEqual(presets.filter(\.selected).count, 1)
    }

    func testUnknownPresetIsRefusedWithTheChoices() async throws {
        let response = try await send(FanBarCLIRequest(action: .setPreset, preset: "turbo"))
        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.message.contains("performance"))
    }

    func testModeChangeWithoutTheHelperFailsAndChangesNothing() async throws {
        let response = try await send(FanBarCLIRequest(action: .fixed, rpm: 3_000, hold: true))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.status?.mode, .automatic)
    }

    func testMismatchedVersionIsRefused() async throws {
        var request = FanBarCLIRequest(action: .status)
        request.version = FanBarCLIContract.version + 1
        let response = try await send(request)
        XCTAssertFalse(response.ok)
    }
}
