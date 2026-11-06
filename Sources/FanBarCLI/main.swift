import FanBarShared
import Foundation

// `fanbar`: drives the running FanBar.app from a terminal or script.
// Exit codes: 0 success, 1 the app refused or failed the command,
// 2 usage error, 3 FanBar.app could not be reached.

let invocation: CLIInvocation
switch CLIArguments.parse(Array(CommandLine.arguments.dropFirst())) {
case .success(let parsed):
    invocation = parsed
case .failure(let error):
    fputs("fanbar: \(error.message)\n\n\(CLIArguments.usage)\n", stderr)
    exit(2)
}

let request: FanBarCLIRequest
switch invocation.command {
case .help:
    print(CLIArguments.usage)
    exit(0)
case .version:
    print("fanbar \(CLIConnection.appVersion)")
    exit(0)
case .status, .temps:
    request = FanBarCLIRequest(action: .status)
case .request(let explicit):
    request = explicit
}

let response: FanBarCLIResponse
switch CLIConnection.send(request, noLaunch: invocation.noLaunch) {
case .success(let reply):
    response = reply
case .failure(let error):
    fputs("fanbar: \(error.message)\n", stderr)
    exit(3)
}

if let warning = CLIConnection.copyMismatchWarning(
    answeredBy: response.appPath,
    shippedIn: CLIConnection.enclosingApp(of: CLIConnection.executableURL())
) {
    // stderr, so --json output on stdout stays parseable.
    fputs("fanbar: \(warning)\n", stderr)
}

if invocation.json {
    print(CLIOutput.json(response))
} else if !response.ok {
    fputs("fanbar: \(response.message)\n", stderr)
} else {
    switch (invocation.command, request.action) {
    case (.temps, _): print(CLIOutput.temps(response))
    case (_, .status): print(CLIOutput.status(response))
    case (_, .listPresets): print(CLIOutput.presets(response))
    default: print(response.message)
    }
}

exit(response.ok ? 0 : 1)
