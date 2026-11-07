import FanBarShared
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

    func testUsageStatisticsPrivacyLinkOpensTheDocumentedFieldsInTheReadersLanguage() {
        let base = "https://github.com/helson-lin/FanBar/blob/main/services/update/"
        for language in [FanBarLanguage.chinese, .traditionalChinese] {
            XCTAssertEqual(FanBarLinks.usageStatisticsPrivacy(for: language).absoluteString, base + "PRIVACY.zh-CN.md")
        }
        for language in [FanBarLanguage.english, .japanese, .russian, .french] {
            XCTAssertEqual(FanBarLinks.usageStatisticsPrivacy(for: language).absoluteString, base + "PRIVACY.md")
        }
    }
}
