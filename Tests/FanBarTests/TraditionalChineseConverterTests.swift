@testable import FanBarShared
import XCTest

final class TraditionalChineseConverterTests: XCTestCase {
    private let converter = TraditionalChineseConverter.shared

    func testUsesTaiwanTermsMacOSUses() {
        XCTAssertEqual(converter.convert("打开系统设置"), "打開系統設定")
        XCTAssertEqual(converter.convert("在“登录项与扩展”中允许 FanBar"), "在「登入項目與延伸功能」中允許 FanBar")
        XCTAssertEqual(converter.convert("恢复默认曲线"), "恢復預設曲線")
        XCTAssertEqual(converter.convert("选择状态在菜单栏里的样子。"), "選擇狀態在選單列裡的樣子。")
        XCTAssertEqual(converter.convert("登录时启动 FanBar"), "登入時啟動 FanBar")
        XCTAssertEqual(converter.convert("不会显示在程序坞中"), "不會顯示在 Dock 中")
        XCTAssertEqual(
            converter.convert("恢复当前预设的默认曲线"),
            "恢復目前預設的初始曲線"
        )
    }

    func testKeepsFormatSpecifiersIntact() {
        XCTAssertEqual(
            converter.convert("另外 %d 个风扇，平均 %d RPM（%.0f%%）"),
            "另外 %d 個風扇，平均 %d RPM（%.0f%%）"
        )
    }

    func testLocalizationIdentifiers() {
        XCTAssertEqual(FanBarLanguage.english.localizationIdentifier, "en")
        XCTAssertEqual(FanBarLanguage.chinese.localizationIdentifier, "zh-Hans")
        XCTAssertEqual(FanBarLanguage.traditionalChinese.localizationIdentifier, "zh-Hant")
    }
}
