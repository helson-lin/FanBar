@testable import FanBarShared
import Foundation
import XCTest

/// Keeps the Japanese catalog in step with the `fanBarText` / `fanBarFormat`
/// call sites, which are the only source of UI copy.
final class JapaneseCatalogTests: XCTestCase {
    private struct CallSite {
        let english: String
        let isFormat: Bool
        let location: String
    }

    func testEveryCallSiteHasJapanese() throws {
        let sites = try callSites()
        XCTAssertGreaterThan(sites.count, 200, "call-site scan found too little; check the pattern")
        for site in sites where JapaneseCatalog.text(for: site.english) == nil {
            XCTFail("No Japanese for \"\(site.english)\" (\(site.location))")
        }
    }

    func testCatalogHasNoStaleEntries() throws {
        let used = Set(try callSites().map(\.english))
        for key in JapaneseCatalog.strings.keys where !used.contains(key) {
            XCTFail("Catalog entry no longer used: \"\(key)\"")
        }
    }

    /// `String(format:)` pairs arguments by position, so a Japanese template
    /// must carry the same specifiers in the same order as the English one.
    func testFormatSpecifiersMatchEnglish() throws {
        for site in try callSites() where site.isFormat {
            guard let japanese = JapaneseCatalog.text(for: site.english) else { continue }
            XCTAssertEqual(
                specifiers(in: japanese), specifiers(in: site.english),
                "Specifiers differ for \"\(site.english)\" (\(site.location))"
            )
        }
    }

    private func specifiers(in template: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXoOfFeEgGcCsSaAp%]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range).compactMap {
            Range($0.range, in: template).map { String(template[$0]) }
        }
    }

    private func callSites() throws -> [CallSite] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let literal = #""((?:[^"\\]|\\.)*)""#
        let regex = try NSRegularExpression(
            pattern: #"fanBar(Text|Format)\(\s*"# + literal + #"\s*,\s*"# + literal
        )
        var sites: [CallSite] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let kind = Range(match.range(at: 1), in: text),
                      let english = Range(match.range(at: 3), in: text) else { continue }
                sites.append(CallSite(
                    english: unescape(String(text[english])),
                    isFormat: text[kind] == "Format",
                    location: file.lastPathComponent
                ))
            }
        }
        return sites
    }

    /// Source literals are escaped; the runtime key is the unescaped string.
    private func unescape(_ literal: String) -> String {
        literal
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\"#, with: "\\")
    }
}
