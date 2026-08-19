import Foundation
import XCTest

final class SoftwareUpdateConfigurationTests: XCTestCase {
    /// Sparkle fails closed when its feed or public key is missing. Keep the
    /// release endpoint and long-lived verification key under test.
    func testSparkleReleaseConfiguration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repositoryRoot.appendingPathComponent("App/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            plist["SUFeedURL"] as? String,
            "https://github.com/helson-lin/FanBar/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            plist["SUPublicEDKey"] as? String,
            "G4oJz01PVyR/W8H0r5mZ6AV6wlAr/ARx3YCYMwfgq60="
        )
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, false)
    }

    func testSparkleLicenseIsIncludedInPackagedResources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let licenseURL = repositoryRoot.appendingPathComponent(
            "ThirdParty/Sparkle-LICENSE.txt"
        )
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        let packagingScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/package-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(license.contains("Copyright (c) 2006-2013 Andy Matuschak"))
        XCTAssertTrue(license.contains("EXTERNAL LICENSES"))
        XCTAssertTrue(packagingScript.contains("Sparkle-LICENSE.txt"))
    }
}
