import Darwin
import Foundation

@main
enum FanBarHelperMain {
    static func main() {
        let service = FanBarHelperService()

        // launchd sends SIGTERM during upgrades and shutdown; restore system policy first.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT)
        for source in [term, interrupt] {
            // Explicitly @Sendable keeps this closure nonisolated. Without it,
            // Swift concurrency infers an isolated closure whose executor
            // assertion traps (SIGTRAP) when libdispatch runs the handler on
            // the global concurrent queue, skipping restoreForShutdown().
            source.setEventHandler { @Sendable in
                service.restoreForShutdown()
                exit(EXIT_SUCCESS)
            }
            source.resume()
        }
        service.run()
    }
}
