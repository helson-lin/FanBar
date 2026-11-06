import AppKit
import FanBarShared
import XCTest
@testable import FanBar

/// The panel has a fixed width, so its one-line labels must fit it in every language
/// rather than truncate (a Mac mini M4 showed "CPU ave…" and "Performanc…" in English).
final class PanelLabelFitTests: XCTestCase {
    private let languages: [FanBarLanguage] = [.english, .chinese, .traditionalChinese, .japanese, .russian, .french]
    override func invokeTest() {
        let savedLanguage = UserDefaults.standard.object(forKey: FanBarLanguage.preferenceKey)
        defer {
            if let savedLanguage {
                UserDefaults.standard.set(savedLanguage, forKey: FanBarLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FanBarLanguage.preferenceKey)
            }
        }
        super.invokeTest()
    }

    @MainActor
    private func use(_ language: FanBarLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: FanBarLanguage.preferenceKey)
    }

    @MainActor
    func testCalmStatusFitsOneLineInEnglishAndChinese() {
        let focus = ThermalFocus(part: .cpu, celsius: 64)
        let width = PanelHeaderStatus.textWidth(indicatorWidth: 6)
        for language in [FanBarLanguage.english, .chinese, .traditionalChinese, .japanese] {
            use(language)
            let parts = FanMenu.calmStatusParts(isManual: false, focus: focus)
            let lines = PanelHeaderStatus.lines(parts, weight: .regular, trailingWidth: 0, fitting: width)
            XCTAssertEqual(lines.count, 1, "\(language): \(lines)")
        }
        use(.english)
        XCTAssertEqual(FanMenu.calmStatusParts(isManual: false, focus: focus).last, "CPU 64°")
    }

    @MainActor
    func testCalmAndManualStatusFitBesideTheSettingsButton() {
        let width = PanelHeaderStatus.textWidth(indicatorWidth: 6)
        for language in languages {
            use(language)
            var cases = ThermalPart.allCases.map {
                (parts: FanMenu.calmStatusParts(isManual: false, focus: ThermalFocus(part: $0, celsius: 105)),
                 trailing: CGFloat(0))
            }
            // In manual mode the restore countdown follows the last line.
            cases.append((FanMenu.calmStatusParts(isManual: true, focus: nil), FanMenu.restoreMenuWidth))
            for item in cases {
                let lines = PanelHeaderStatus.lines(item.parts, weight: .regular,
                                                    trailingWidth: item.trailing, fitting: width)
                for (index, line) in lines.enumerated() {
                    let trailing = index == lines.count - 1 && item.trailing > 0 ? item.trailing + 6 : 0
                    XCTAssertLessThanOrEqual(PanelHeaderStatus.measure(line) + trailing, width,
                                             "\(language) truncates \"\(line)\"")
                }
            }
        }
    }

    /// Every warm and hot title, for every part, in Automatic and in manual mode where the restore
    /// countdown follows it: at most two lines, none wider than the room beside the settings button.
    @MainActor
    func testAlertStatusFitsTwoLinesInEveryLanguageAndMode() {
        let modes: [FanController.Mode] = [.automatic, .fixed(3_000)]
        for language in languages {
            use(language)
            for part in ThermalPart.allCases {
                for celsius in [part.warmThreshold, part.hotThreshold + 30] {
                    let focus = ThermalFocus(part: part, celsius: celsius)
                    XCTAssertTrue(focus.isAlert)
                    let width = PanelHeaderStatus.textWidth(indicatorWidth: focus.level == .hot ? 12 : 6)
                    for mode in modes {
                        let trailing = mode == .automatic ? 0 : FanMenu.restoreMenuWidth
                        let parts = FanMenu.alertStatusParts(focus, mode: mode)
                        let lines = PanelHeaderStatus.lines(parts, weight: .semibold, trailingWidth: trailing,
                                                            fitting: width)
                        let inline = PanelHeaderStatus.trailingFits(after: lines, weight: .semibold,
                                                                    trailingWidth: trailing, fitting: width)
                        let context = "\(language) \(part) \(focus.level) \(mode): \(lines)"
                        XCTAssertLessThanOrEqual(lines.count + (inline ? 0 : 1), 2, context)
                        for (index, line) in lines.enumerated() {
                            let after = inline && trailing > 0 && index == lines.count - 1 ? trailing + 6 : 0
                            XCTAssertLessThanOrEqual(PanelHeaderStatus.measure(line, weight: .semibold) + after,
                                                     width, "\(context) truncates \"\(line)\"")
                        }
                        XCTAssertLessThanOrEqual(trailing, width, context)
                    }
                }
            }
        }
    }

    @MainActor
    func testRestoreCountdownTakesItsOwnLineOnlyAfterAnUnbreakableAlert() {
        use(.english)
        let width = PanelHeaderStatus.textWidth(indicatorWidth: 6)
        let trailing = FanMenu.restoreMenuWidth
        let alert = PanelHeaderStatus.lines(FanMenu.alertStatusParts(ThermalFocus(part: .cpu, celsius: ThermalPart.cpu.warmThreshold),
                                                                     mode: .fixed(3_000)),
                                            weight: .semibold, trailingWidth: trailing, fitting: width)
        XCTAssertEqual(alert, ["CPU average is running warm"])
        XCTAssertFalse(PanelHeaderStatus.trailingFits(after: alert, weight: .semibold,
                                                      trailingWidth: trailing, fitting: width))
        let calm = PanelHeaderStatus.lines(FanMenu.calmStatusParts(isManual: true, focus: nil),
                                           weight: .regular, trailingWidth: trailing, fitting: width)
        XCTAssertTrue(PanelHeaderStatus.trailingFits(after: calm, weight: .regular,
                                                     trailingWidth: trailing, fitting: width))
        XCTAssertTrue(PanelHeaderStatus.trailingFits(after: alert, weight: .semibold, trailingWidth: 0, fitting: 1))
    }

    @MainActor
    func testHotChipAlertPutsMacOSResponseOnItsOwnPart() {
        use(.english)
        let hot = ThermalFocus(part: .cpu, celsius: 110)
        XCTAssertEqual(FanMenu.alertStatusParts(hot, mode: .automatic),
                       ["CPU average is very hot", "macOS has sped up the fans"])
        XCTAssertEqual(FanMenu.alertStatusParts(hot, mode: .fixed(3_000)), ["CPU average is very hot"])
        XCTAssertEqual(FanMenu.alertStatusParts(ThermalFocus(part: .ssd, celsius: 80), mode: .automatic),
                       ["SSD is very hot"])
        XCTAssertEqual(FanMenu.alertStatusParts(ThermalFocus(part: .ssd, celsius: 70), mode: .automatic),
                       ["SSD is running warm"])
    }

    @MainActor
    func testLinesBreakBeforeTheLastPartOnlyWhenNeeded() {
        let parts = ["Fans normal", "macOS in control", "CPU 64°"]
        XCTAssertEqual(PanelHeaderStatus.lines(parts, weight: .regular, trailingWidth: 0, fitting: 1_000),
                       ["Fans normal · macOS in control · CPU 64°"])
        XCTAssertEqual(PanelHeaderStatus.lines(parts, weight: .regular, trailingWidth: 0, fitting: 100),
                       ["Fans normal · macOS in control", "CPU 64°"])
        XCTAssertEqual(PanelHeaderStatus.lines(["Cooling normally"], weight: .regular, trailingWidth: 0, fitting: 10),
                       ["Cooling normally"])
    }

    @MainActor
    func testCoreLabelsShareTheCPUCellInEveryLanguage() {
        // Half the content width, less half of the grid's 24pt gutter.
        let cellWidth = (FanMenu.panelWidth - FanMenu.padding * 2 - 24) / 2
        let layouts: [(performance: Int, efficiency: Int)] = [(4, 6), (4, 4), (8, 2), (8, 4), (12, 4), (16, 8), (24, 8)]
        for language in languages {
            use(language)
            for layout in layouts {
                let kinds = Array(repeating: CPUCoreKind.performance, count: layout.performance)
                    + Array(repeating: .efficiency, count: layout.efficiency)
                let groups = CoreGroups(fractions: kinds.map { _ in 0.5 }, kinds: kinds, coreCount: kinds.count,
                                        color: .green, barHeight: 28, palette: PanelPalette(colorScheme: .light)).groups
                XCTAssertEqual(groups.count, 2)
                let labels = groups.map { PanelHeaderStatus.measure($0.title) }.reduce(0, +)
                XCTAssertLessThanOrEqual(labels + 6, cellWidth,
                                         "\(language) \(layout): \(groups.map(\.title))")
            }
        }
        use(.english)
        let kinds = Array(repeating: CPUCoreKind.performance, count: 4) + Array(repeating: .efficiency, count: 6)
        let titles = CoreGroups(fractions: [], kinds: kinds, coreCount: 10, color: .green, barHeight: 28,
                                palette: PanelPalette(colorScheme: .light)).groups.map(\.title)
        XCTAssertEqual(titles, ["P-cores ×4", "E-cores ×6"])
    }
}
