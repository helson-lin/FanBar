import FanBarShared
import XCTest
@testable import FanBar

final class LegacyHelperDaemonTests: XCTestCase {
    private func macOS(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    private let stagedPath = "/var/folders/ab/T/local.fanbar.helper.42.plist"

    func testBigSurAndMontereyRegisterTheHelperThroughLaunchd() {
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11)))
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11, 7)))
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(12, 7)))
        XCTAssertFalse(LegacyHelperDaemon.isUsed(on: macOS(13)))
        XCTAssertFalse(LegacyHelperDaemon.isUsed(on: macOS(15)))
    }

    /// launchd refuses to bootstrap a user-owned plist into the system domain,
    /// so approving the administrator prompt used to leave the helper off.
    func testMacOS11InstallLoadsARootOwnedPlistFromLaunchDaemons() {
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11)))
        let command = LegacyHelperDaemon.installCommand(stagedPlistPath: stagedPath)

        XCTAssertEqual(LegacyHelperDaemon.installedPlistPath, "/Library/LaunchDaemons/local.fanbar.helper.plist")
        XCTAssertTrue(command.contains(
            "/usr/bin/install -m 644 -o root -g wheel '\(stagedPath)' '/Library/LaunchDaemons/local.fanbar.helper.plist'"
        ))
        XCTAssertTrue(command.hasSuffix("/bin/launchctl bootstrap system '/Library/LaunchDaemons/local.fanbar.helper.plist'"))
        XCTAssertFalse(command.contains("bootstrap system '\(stagedPath)'"))
    }

    func testMacOS11InstallReplacesALoadedJobAndClearsADisabledFlag() throws {
        let command = LegacyHelperDaemon.installCommand(stagedPlistPath: stagedPath)
        let bootout = try XCTUnwrap(command.range(of: "/bin/launchctl bootout system/local.fanbar.helper 2>/dev/null"))
        let enable = try XCTUnwrap(command.range(of: "/bin/launchctl enable system/local.fanbar.helper &&"))
        let bootstrap = try XCTUnwrap(command.range(of: "/bin/launchctl bootstrap system"))
        XCTAssertLessThan(bootout.lowerBound, enable.lowerBound)
        XCTAssertLessThan(enable.lowerBound, bootstrap.lowerBound)
        XCTAssertTrue(command.contains("/bin/launchctl bootout system/local.fanbar.helper.plist 2>/dev/null"))
    }

    func testMacOS11StatusChecksTheLabelTheJobIsLoadedUnder() throws {
        let job = LegacyHelperDaemon.jobDefinition(helperExecutablePath: "/Applications/FanBar.app/helper")
        XCTAssertEqual(job["Label"] as? String, LegacyHelperDaemon.label)
        XCTAssertEqual(LegacyHelperDaemon.label, FanBarService.helperBundleID)
        let machServices = try XCTUnwrap(job["MachServices"] as? [String: Bool])
        XCTAssertEqual(machServices, [FanBarService.helperBundleID: true])
        XCTAssertEqual(job["ProgramArguments"] as? [String], ["/Applications/FanBar.app/helper"])

        XCTAssertEqual(LegacyHelperDaemon.status(jobIsLoaded: true), .enabled)
        XCTAssertEqual(LegacyHelperDaemon.status(jobIsLoaded: false), .notRegistered)
    }

    func testHelperExecutableLivesInsideTheAppBundle() {
        XCTAssertEqual(
            LegacyHelperDaemon.helperExecutablePath(inAppAt: URL(fileURLWithPath: "/Applications/FanBar.app")),
            "/Applications/FanBar.app/Contents/Library/LaunchServices/local.fanbar.helper"
        )
    }

    func testMacOS11RemoveToleratesAMissingJobAndDeletesThePlist() {
        let command = LegacyHelperDaemon.removeCommand()
        XCTAssertTrue(command.contains("/bin/launchctl bootout system/local.fanbar.helper 2>/dev/null"))
        XCTAssertTrue(command.hasSuffix("/bin/rm -f '/Library/LaunchDaemons/local.fanbar.helper.plist'"))
    }

    func testShellQuotingSurvivesAnApostropheInTheTemporaryPath() {
        XCTAssertEqual(LegacyHelperDaemon.shellQuote("/tmp/it's"), "'/tmp/it'\\''s'")
    }

    /// Runs the generated script in a sandbox directory with stand-ins for
    /// the system tools, so the shell syntax and exit status are exercised.
    func testInstallScriptFailsWhenBootstrapFailsAndSucceedsOtherwise() throws {
        let command = LegacyHelperDaemon.installCommand(stagedPlistPath: stagedPath)
        XCTAssertEqual(try runWithStubs(command, bootstrapStatus: 0), 0)
        XCTAssertNotEqual(try runWithStubs(command, bootstrapStatus: 5), 0)
        XCTAssertEqual(try runWithStubs(LegacyHelperDaemon.removeCommand(), bootstrapStatus: 5), 0)
    }

    private func runWithStubs(_ command: String, bootstrapStatus: Int32) throws -> Int32 {
        let rewritten = command
            .replacingOccurrences(of: "/usr/bin/install", with: "true")
            .replacingOccurrences(of: "/bin/rm", with: "true")
            .replacingOccurrences(of: "/bin/launchctl bootstrap", with: "exit_with \(bootstrapStatus)")
            .replacingOccurrences(of: "/bin/launchctl enable", with: "true")
            // A job that is not loaded makes bootout fail; that must not matter.
            .replacingOccurrences(of: "/bin/launchctl bootout", with: "false")
        let script = "exit_with() { return $1; }; " + rewritten
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
