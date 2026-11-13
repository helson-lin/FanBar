import Foundation
import XCTest
@testable import FanBarShared

/// Keeps the Korean catalog in step with the `fanBarText` / `fanBarFormat`
/// call sites, which are the only source of UI copy.
final class KoreanCatalogTests: XCTestCase {
    func testKoreanPreferenceUpdatesTextAndFormats() {
        let saved = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: FanBarLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
            }
        }

        UserDefaults.standard.set(FanBarLanguage.korean.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(FanBarLanguage.current, .korean)
        XCTAssertEqual(FanBarLanguage.korean.title, "한국어")
        XCTAssertEqual(FanBarLanguage.korean.localizationIdentifier, "ko")
        XCTAssertEqual(FanBarLanguage.korean.locale.languageCode, "ko")
        XCTAssertEqual(fanBarText("设置", "Settings"), "설정")
        XCTAssertEqual(fanBarFormat("风扇 %d", "Fan %d", 2), "팬 2")

        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(fanBarText("设置", "Settings"), "Settings")
    }

    func testSystemLanguageRecognizesKorean() {
        XCTAssertEqual(FanBarLanguage.systemLanguage(
            languageCode: "ko", preferredLanguageCode: "en", prefersTraditionalScript: false
        ), .korean)
        // The app has no .lproj bundle, so the region-derived locale may be English.
        XCTAssertEqual(FanBarLanguage.systemLanguage(
            languageCode: "en", preferredLanguageCode: "ko", prefersTraditionalScript: false
        ), .korean)
        XCTAssertEqual(FanBarLanguage.systemLanguage(
            languageCode: "en", preferredLanguageCode: "de", prefersTraditionalScript: false
        ), .english)
    }

    func testKoreanWidgetStringsMatchEnglishKeysAndFormats() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = root.appendingPathComponent("WidgetExtension/Resources")
        func strings(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(language).lproj/Localizable.strings"))
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            )
        }
        let english = try strings("en")
        let korean = try strings("ko")
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        for (key, value) in english {
            let translated = try XCTUnwrap(korean[key])
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(
                try CatalogCallSites.specifiers(in: translated), try CatalogCallSites.specifiers(in: value), key
            )
        }
    }

    func testEveryCallSiteHasKorean() throws {
        let sites = try CatalogCallSites.scan()
        XCTAssertGreaterThan(sites.count, 200, "call-site scan found too little; check the pattern")
        for site in sites where KoreanCatalog.text(for: site.english) == nil {
            XCTFail("No Korean for \"\(site.english)\" (\(site.location))")
        }
    }

    func testCatalogHasNoStaleEntries() throws {
        let used = Set(try CatalogCallSites.scan().map(\.english))
        XCTAssertEqual(KoreanCatalog.strings.count, used.count)
        for key in KoreanCatalog.strings.keys where !used.contains(key) {
            XCTFail("Catalog entry no longer used: \"\(key)\"")
        }
    }

    func testFormatSpecifiersMatchEnglish() throws {
        for site in try CatalogCallSites.scan() where site.isFormat {
            guard let translated = KoreanCatalog.text(for: site.english) else { continue }
            XCTAssertEqual(
                try CatalogCallSites.specifiers(in: translated), try CatalogCallSites.specifiers(in: site.english),
                "Specifiers differ for \"\(site.english)\" (\(site.location))"
            )
        }
    }
}
