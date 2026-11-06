import Darwin
import FanBarShared
import Foundation
import os

/// Accepts `fanbar` requests on a per-user Unix socket while the app runs.
///
/// Access control does not rely on the socket's file mode alone: every
/// connection's peer must be the same user as the app (`getpeereid`), so only
/// processes that could already drive the menu panel can drive the CLI.
@MainActor
final class CLIServer {
    static let shared = CLIServer()

    init() {}

    private nonisolated static let log = Logger(subsystem: "local.fanbar.app", category: "cli")
    private let queue = DispatchQueue(label: "local.fanbar.cli")
    private var listener: DispatchSourceRead?
    private var boundPath: String?

    func start(controller: FanController, socketURL: URL = FanBarCLIContract.socketURL()) {
        guard listener == nil else { return }
        let path = socketURL.path
        do {
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            Self.log.error("CLI socket directory unavailable: \(error.localizedDescription)")
            return
        }
        // Another FanBar (e.g. a development build) already answers here; leave it be.
        if Self.isServing(path) {
            Self.log.info("CLI socket already served by another FanBar instance")
            return
        }
        unlink(path)
        guard let descriptor = Self.bindListeningSocket(path) else { return }
        boundPath = path

        listener = Self.makeListener(descriptor, queue: queue, controller: controller)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let boundPath { unlink(boundPath) }
        boundPath = nil
    }

    /// Nonisolated so its handlers are not inferred to run on the main actor:
    /// they run on the CLI queue.
    private nonisolated static func makeListener(
        _ descriptor: Int32,
        queue: DispatchQueue,
        controller: FanController
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            // Reading blocks for up to the receive timeout; keep accepting meanwhile.
            DispatchQueue.global(qos: .userInitiated).async {
                serve(client, controller: controller)
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private static func bindListeningSocket(_ path: String) -> Int32? {
        guard var address = FanBarCLISocket.address(for: path) else {
            log.error("CLI socket path is too long")
            return nil
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 8) == 0 else {
            log.error("CLI socket unavailable (errno \(errno))")
            close(descriptor)
            unlink(path)
            return nil
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        return descriptor
    }

    private static func isServing(_ path: String) -> Bool {
        guard var address = FanBarCLISocket.address(for: path) else { return false }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    /// Reads one request off the CLI queue, runs it on the main actor, then
    /// writes the reply and closes the connection.
    private nonisolated static func serve(_ client: Int32, controller: FanController) {
        // Accepted sockets inherit the listener's O_NONBLOCK; reads here block.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var enabled: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        // A client that connects and never writes must not pin a connection.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var peerUser: uid_t = 0
        var peerGroup: gid_t = 0
        guard getpeereid(client, &peerUser, &peerGroup) == 0, peerUser == getuid() else {
            log.error("Rejected CLI client from another user")
            close(client)
            return
        }
        guard let data = FanBarCLISocket.readMessage(from: client),
              let request = try? FanBarCLIContract.makeDecoder().decode(FanBarCLIRequest.self, from: data) else {
            reply(FanBarCLIResponse(ok: false, message: "Malformed request."), to: client)
            return
        }
        Task { @MainActor in
            let response = await CLICommandHandler.handle(request, controller: controller)
            DispatchQueue.global(qos: .userInitiated).async {
                reply(response, to: client)
            }
        }
    }

    /// Resolved once: the bundle cannot move while the app runs.
    private nonisolated static let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path

    private nonisolated static func reply(_ response: FanBarCLIResponse, to client: Int32) {
        var response = response
        response.appPath = appPath
        if let data = try? FanBarCLIContract.makeEncoder().encode(response) {
            _ = FanBarCLISocket.writeMessage(data, to: client)
        }
        close(client)
    }
}
