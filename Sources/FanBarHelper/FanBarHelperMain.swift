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
            source.setEventHandler {
                service.restoreForShutdown()
                exit(EXIT_SUCCESS)
            }
            source.resume()
        }
        service.run()
    }
}
