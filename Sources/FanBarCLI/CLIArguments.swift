import FanBarShared
import Foundation

/// What one `fanbar` invocation asks for, parsed without touching the system.
struct CLIInvocation: Equatable {
    enum Command: Equatable {
        case help
        case version
        case status
        case temps
        case request(FanBarCLIRequest)
    }

    var command: Command
    var json = false
    /// Fail instead of starting FanBar.app when it is not running.
    var noLaunch = false
}

struct CLIUsageError: Error, Equatable {
    let message: String
}

enum CLIArguments {
    static let usage = """
    Usage: fanbar <command> [options]

    Commands:
      status                    Mode, preset, fans and temperatures
      temps                     CPU, GPU and SSD temperatures
      preset list               Presets you can switch to
      preset set <name>         Run a preset's curve (silent, balanced,
                                performance, extreme, or a custom name)
      mode auto                 Hand the fans back to macOS
      mode curve                Run the selected preset's curve
      mode fixed <rpm>          Hold every fan at a fixed RPM
      help                      Show this help
      version                   Show the FanBar version

    Options:
      --hold                    Keep the new mode until you change it, instead of
                                returning to macOS control after the timer set
                                in FanBar Settings (preset set, mode curve/fixed)
      --json                    Print the app's JSON reply
      --no-launch               Do not start FanBar if it is not running

    FanBar.app must be running; fanbar starts it in the background when needed.
    """

    static func parse(_ arguments: [String]) -> Result<CLIInvocation, CLIUsageError> {
        var json = false
        var noLaunch = false
        var hold = false
        var words: [String] = []
        for argument in arguments {
            switch argument {
            case "--json": json = true
            case "--no-launch": noLaunch = true
            case "--hold": hold = true
            case "-h", "--help": words = ["help"]
            case "--version": words = ["version"]
            default:
                if argument.hasPrefix("--") {
                    return .failure(CLIUsageError(message: "Unknown option \(argument)."))
                }
                words.append(argument)
            }
            if words.first == "help" || words.first == "version" { break }
        }

        let command: CLIInvocation.Command
        switch parseCommand(words) {
        case .success(let parsed): command = parsed
        case .failure(let error): return .failure(error)
        }
        if hold {
            guard case .request(let request) = command,
                  [.setPreset, .curve, .fixed].contains(request.action) else {
                return .failure(CLIUsageError(message: "--hold only applies to preset set, mode curve and mode fixed."))
            }
        }
        return .success(CLIInvocation(command: command.holding(hold), json: json, noLaunch: noLaunch))
    }

    private static func parseCommand(_ words: [String]) -> Result<CLIInvocation.Command, CLIUsageError> {
        switch words.first {
        case nil, "help": return .success(.help)
        case "version": return .success(.version)
        case "status": return exactly(words, 1, .status)
        case "temps": return exactly(words, 1, .temps)
        case "preset": return parsePreset(words)
        case "mode": return parseMode(words)
        case let other?: return .failure(CLIUsageError(message: "Unknown command \"\(other)\"."))
        }
    }

    private static func parsePreset(_ words: [String]) -> Result<CLIInvocation.Command, CLIUsageError> {
        switch words.dropFirst().first {
        case "list":
            return exactly(words, 2, .request(FanBarCLIRequest(action: .listPresets)))
        case "set":
            // Custom names may contain spaces: `fanbar preset set Late Night`.
            let name = words.dropFirst(2).joined(separator: " ")
            guard !name.isEmpty else { return .failure(CLIUsageError(message: "preset set needs a preset name.")) }
            return .success(.request(FanBarCLIRequest(action: .setPreset, preset: name)))
        default:
            return .failure(CLIUsageError(message: "Use \"preset list\" or \"preset set <name>\"."))
        }
    }

    private static func parseMode(_ words: [String]) -> Result<CLIInvocation.Command, CLIUsageError> {
        switch words.dropFirst().first {
        case "auto":
            return exactly(words, 2, .request(FanBarCLIRequest(action: .automatic)))
        case "curve":
            return exactly(words, 2, .request(FanBarCLIRequest(action: .curve)))
        case "fixed":
            guard words.count == 3, let rpm = Int(words[2]), rpm > 0 else {
                return .failure(CLIUsageError(message: "mode fixed needs a positive RPM, e.g. mode fixed 3000."))
            }
            return .success(.request(FanBarCLIRequest(action: .fixed, rpm: rpm)))
        default:
            return .failure(CLIUsageError(message: "Use \"mode auto\", \"mode curve\" or \"mode fixed <rpm>\"."))
        }
    }

    private static func exactly(
        _ words: [String],
        _ count: Int,
        _ command: CLIInvocation.Command
    ) -> Result<CLIInvocation.Command, CLIUsageError> {
        guard words.count == count else {
            return .failure(CLIUsageError(message: "Unexpected argument \"\(words[count])\"."))
        }
        return .success(command)
    }
}

private extension CLIInvocation.Command {
    func holding(_ hold: Bool) -> Self {
        guard case .request(var request) = self else { return self }
        request.hold = hold
        return .request(request)
    }
}
