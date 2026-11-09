import FanBarShared
import XCTest
@testable import FanBar

final class LegacyHelperDaemonTests: XCTestCase {
    private func macOS(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    private let appPath = "/Applications/FanBar.app"
    private let installedHelper = "/Library/PrivilegedHelperTools/local.fanbar.helper/Contents/Library/LaunchServices/local.fanbar.helper"

    private func installCommand(appPath: String? = nil) throws -> String {
        try LegacyHelperDaemon.installCommand(
            appBundlePath: appPath ?? self.appPath,
            teamID: "64S5F787T9",
            jobPlist: LegacyHelperDaemon.jobPlistText()
        )
    }

    func testBigSurAndMontereyRegisterTheHelperThroughLaunchd() {
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11)))
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11, 7)))
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(12, 7)))
        XCTAssertFalse(LegacyHelperDaemon.isUsed(on: macOS(13)))
        XCTAssertFalse(LegacyHelperDaemon.isUsed(on: macOS(15)))
    }

    /// launchd refuses to bootstrap a user-owned plist into the system domain,
    /// so approving the administrator prompt used to leave the helper off.
    func testMacOS11InstallLoadsARootOwnedPlistFromLaunchDaemons() throws {
        XCTAssertTrue(LegacyHelperDaemon.isUsed(on: macOS(11)))
        let command = try installCommand()
        let plist = "'/Library/LaunchDaemons/local.fanbar.helper.plist'"

        XCTAssertTrue(command.contains("/usr/sbin/chown root:wheel \(plist)"))
        XCTAssertTrue(command.contains("/bin/chmod 644 \(plist)"))
        XCTAssertTrue(command.hasSuffix("/bin/launchctl bootstrap system \(plist)"))
    }

    /// The root script writes the plist itself; nothing it loads comes from a
    /// user-writable file that could be swapped during the password prompt.
    func testMacOS11JobPlistIsWrittenByRootNotCopiedFromTheUser() throws {
        let command = try installCommand()
        XCTAssertTrue(command.contains("/usr/bin/printf '%s' '<?xml"))
        XCTAssertFalse(command.contains("/var/folders"))
        XCTAssertFalse(command.contains("TMPDIR"))

        let text = try LegacyHelperDaemon.jobPlistText()
        XCTAssertFalse(text.contains("\n"))
        let parsed = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any]
        )
        XCTAssertEqual(parsed["Label"] as? String, FanBarService.helperBundleID)
        XCTAssertEqual(parsed["ProgramArguments"] as? [String], [installedHelper])
        XCTAssertEqual(parsed["MachServices"] as? [String: Bool], [FanBarService.helperBundleID: true])
    }

    /// Legacy launchd checks no signature, so root must never run the helper
    /// from the user-writable app bundle.
    func testMacOS11RootRunsAVerifiedRootOwnedCopyOfTheHelper() throws {
        let job = LegacyHelperDaemon.jobDefinition()
        XCTAssertEqual(job["ProgramArguments"] as? [String], [installedHelper])

        let command = try installCommand()
        let bundledHelper = "\(appPath)/Contents/Library/LaunchServices/local.fanbar.helper"
        let copy = try XCTUnwrap(command.range(of: "/usr/bin/ditto '\(bundledHelper)' '\(installedHelper)'"))
        let chown = try XCTUnwrap(command.range(of: "/usr/sbin/chown -R root:wheel '/Library/PrivilegedHelperTools/local.fanbar.helper'"))
        let verify = try XCTUnwrap(command.range(of:
            "/usr/bin/codesign --verify --strict -R '=anchor apple generic and identifier \"local.fanbar.helper\" "
                + "and certificate leaf[subject.OU] = \"64S5F787T9\"' '\(installedHelper)'"))
        let bootstrap = try XCTUnwrap(command.range(of: "/bin/launchctl bootstrap system"))
        XCTAssertLessThan(copy.lowerBound, chown.lowerBound)
        XCTAssertLessThan(chown.lowerBound, verify.lowerBound)
        XCTAssertLessThan(verify.lowerBound, bootstrap.lowerBound)
    }

    func testUnsignedBuildsInstallNothing() {
        XCTAssertNil(LegacyHelperDaemon.installableTeam(nil))
        XCTAssertNil(LegacyHelperDaemon.installableTeam(""))
        XCTAssertEqual(LegacyHelperDaemon.installableTeam("64S5F787T9"), "64S5F787T9")
    }

    func testMacOS11InstallReplacesALoadedJobAndClearsADisabledFlag() throws {
        let command = try installCommand()
        let bootout = try XCTUnwrap(command.range(of: "/bin/launchctl bootout system/local.fanbar.helper 2>/dev/null"))
        let enable = try XCTUnwrap(command.range(of: "/bin/launchctl enable system/local.fanbar.helper &&"))
        let bootstrap = try XCTUnwrap(command.range(of: "/bin/launchctl bootstrap system"))
        XCTAssertLessThan(bootout.lowerBound, enable.lowerBound)
        XCTAssertLessThan(enable.lowerBound, bootstrap.lowerBound)
        XCTAssertTrue(command.contains("/bin/launchctl bootout system/local.fanbar.helper.plist 2>/dev/null"))
    }

    /// After upgrading to macOS 13, the legacy job still loads at boot under
    /// the label SMAppService registers.
    func testMacOS13RemovesALeftoverLegacyInstallBeforeRegistering() {
        XCTAssertTrue(LegacyHelperDaemon.needsRemovalBeforeServiceManagement(on: macOS(13), legacyPlistExists: true))
        XCTAssertTrue(LegacyHelperDaemon.needsRemovalBeforeServiceManagement(on: macOS(15), legacyPlistExists: true))
        XCTAssertFalse(LegacyHelperDaemon.needsRemovalBeforeServiceManagement(on: macOS(13), legacyPlistExists: false))
        XCTAssertFalse(LegacyHelperDaemon.needsRemovalBeforeServiceManagement(on: macOS(12, 7), legacyPlistExists: true))
        XCTAssertFalse(LegacyHelperDaemon.needsRemovalBeforeServiceManagement(on: macOS(11), legacyPlistExists: true))
    }

    func testMacOS11StatusFollowsWhetherTheJobIsLoaded() {
        XCTAssertEqual(LegacyHelperDaemon.label, FanBarService.helperBundleID)
        XCTAssertEqual(LegacyHelperDaemon.status(jobIsLoaded: true), .enabled)
        XCTAssertEqual(LegacyHelperDaemon.status(jobIsLoaded: false), .notRegistered)
    }

    func testMacOS11RemoveToleratesAMissingJobAndDeletesThePlistAndHelperCopy() {
        let command = LegacyHelperDaemon.removeCommand()
        XCTAssertTrue(command.contains("/bin/launchctl bootout system/local.fanbar.helper 2>/dev/null"))
        XCTAssertTrue(command.contains("/bin/rm -f '/Library/LaunchDaemons/local.fanbar.helper.plist'"))
        XCTAssertTrue(command.hasSuffix("/bin/rm -rf '/Library/PrivilegedHelperTools/local.fanbar.helper'"))
    }

    func testShellQuotingSurvivesAnApostropheInThePath() {
        XCTAssertEqual(LegacyHelperDaemon.shellQuote("/tmp/it's"), "'/tmp/it'\\''s'")
    }

    // MARK: - Running the script

    /// Runs the generated script against a fake app in a temporary folder.
    /// Only chown, codesign and launchctl are stand-ins; the copies are real.
    func testInstallScriptCopiesTheHelperLayoutAndWritesAValidPlist() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        XCTAssertEqual(try run(installCommand(appPath: sandbox.app.path), in: sandbox.root), 0)

        let installed = sandbox.root.appendingPathComponent("Library/PrivilegedHelperTools/local.fanbar.helper/Contents")
        for relative in ["Info.plist", "Library/LaunchServices/local.fanbar.helper", "Frameworks/libswift_Concurrency.dylib"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent(relative).path), relative)
        }
        let plistURL = sandbox.root.appendingPathComponent("Library/LaunchDaemons/local.fanbar.helper.plist")
        let job = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any]
        )
        XCTAssertEqual(job["ProgramArguments"] as? [String], [installedHelper])
    }

    func testInstallScriptStopsBeforeLoadingWhenTheSignatureCheckFails() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        XCTAssertNotEqual(try run(installCommand(appPath: sandbox.app.path), in: sandbox.root, codesignStatus: 1), 0)
        let plistURL = sandbox.root.appendingPathComponent("Library/LaunchDaemons/local.fanbar.helper.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testInstallScriptFailsWhenBootstrapFailsAndRemoveSucceedsWithoutAJob() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        XCTAssertNotEqual(try run(installCommand(appPath: sandbox.app.path), in: sandbox.root, bootstrapStatus: 5), 0)
        XCTAssertEqual(try run(LegacyHelperDaemon.removeCommand(), in: sandbox.root), 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.root.appendingPathComponent("Library/PrivilegedHelperTools/local.fanbar.helper").path
        ))
    }

    private func makeSandbox() throws -> (root: URL, app: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyHelperDaemonTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Applications/FanBar.app")
        let files = ["Contents/Info.plist", LegacyHelperDaemon.helperRelativePath, LegacyHelperDaemon.concurrencyRuntimeRelativePath]
        for relative in files {
            let url = app.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("stub".utf8).write(to: url)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/LaunchDaemons"), withIntermediateDirectories: true
        )
        return (root, app)
    }

    private func run(_ command: String, in root: URL, codesignStatus: Int32 = 0, bootstrapStatus: Int32 = 0) throws -> Int32 {
        let rewritten = command
            .replacingOccurrences(of: "'/Library/", with: "'\(root.path)/Library/")
            .replacingOccurrences(of: "/usr/sbin/chown", with: "true")
            .replacingOccurrences(of: "/usr/bin/codesign", with: "exit_with \(codesignStatus)")
            .replacingOccurrences(of: "/bin/launchctl bootstrap", with: "exit_with \(bootstrapStatus)")
            .replacingOccurrences(of: "/bin/launchctl enable", with: "true")
            // A job that is not loaded makes bootout fail; that must not matter.
            .replacingOccurrences(of: "/bin/launchctl bootout", with: "false")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit_with() { return $1; }; " + rewritten]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
