import XCTest
@testable import FanBar

/// Links FanBar opens: the repository and the donation checkout.
final class FanBarLinksTests: XCTestCase {
    func testRepositoryLinkOpensGitHub() {
        XCTAssertEqual(FanBarLinks.repository.absoluteString, "https://github.com/helson-lin/FanBar")
    }

    func testDonationLinkOpensDodoCheckoutOverHTTPS() {
        let url = FanBarLinks.donation
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "checkout.dodopayments.com")
        XCTAssertTrue(url.path.hasPrefix("/buy/pdt_"))
    }

    func testUsageStatisticsPrivacyLinkOpensTheDocumentedFields() {
        XCTAssertEqual(
            FanBarLinks.usageStatisticsPrivacy.absoluteString,
            "https://github.com/helson-lin/FanBar/blob/main/services/update/PRIVACY.md"
        )
    }
}
