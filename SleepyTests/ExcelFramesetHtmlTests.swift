// ExcelFramesetHtmlTests.swift — ← ExcelFramesetHtmlTest.kt (逐用例, v1.0.61)
// Excel "另存为网页" 导出的 Frameset HTML 识别 (issue #6)。
// 顶层文件不含真课表 <table>(只有 JS 生成标签栏的装饰 table),
// 课程在 <link id="shLink" href="xxx.files/sheet001.html"> 引用的附属文件里。
// iOS 导入走 OpenDocument 单 URI, 读不到同目录附属文件 →
// 必须识别这个结构并抛出带指引的错误, 而不是模糊的"HTML 中未找到表格"。

import XCTest
@testable import Sleepy

final class ExcelFramesetHtmlTests: XCTestCase {

    /// issue #6 真实结构的精简样本: Excel 15 frameset + GBK 声明 + shLink 引用
    private let framesetHtml = #"""
    <html xmlns:x="urn:schemas-microsoft-com:office:excel"
          xmlns="http://www.w3.org/TR/REC-html40">
    <head>
    <meta name="Excel Workbook Frameset">
    <meta http-equiv=Content-Type content="text/html; charset=gb2312">
    <meta name=ProgId content="Excel.Sheet">
    <meta name=Generator content="Microsoft Excel 15">
    <link id="shLink" href="大二课表学期1.files/sheet001.html">
    </head>
    <frameset rows="*,18">
    <frame src="大二课表学期1.files/sheet001.html" name="frSheet">
    </frameset>
    </html>
    """#

    private func failureMessage(_ r: Result<ScheduleParser.ParseResult, Error>) -> String {
        guard case .failure(let e) = r else { return "" }
        return e.localizedDescription
    }

    func testDetectsExcelFrameset() {
        XCTAssertTrue(ScheduleParser.isExcelFrameset(framesetHtml))
    }

    func testExtractsSheetFileReference() {
        let ref = ScheduleParser.excelSheetRef(framesetHtml)
        XCTAssertEqual("大二课表学期1.files/sheet001.html", ref)
    }

    func testNormalHtmlIsNotFrameset() {
        let normal = "<html><body><table><tr><td>高数 1 1-2 1-16</td></tr></table></body></html>"
        XCTAssertFalse(ScheduleParser.isExcelFrameset(normal))
    }

    func testFramesetParseFailsWithGuidance() {
        let result = ScheduleParser.parse(framesetHtml, defaultTableId: 0)
        guard case .failure = result else { return XCTFail("expected parse failure") }  // Swift 5 Result 无 isSuccess/isFailure
        let msg = failureMessage(result)
        // 报错必须点名 Excel 结构和可行出路, 不能用泛泛的"未找到表格"
        XCTAssertTrue(msg.contains("Excel"), "msg=\(msg)")
        XCTAssertTrue(msg.contains("CSV") || msg.contains("csv"), "msg=\(msg)")
    }

    func testPlainHtmlWithoutTableStillErrorsAsBefore() {
        // 非 frameset 的普通 HTML 无表格 → 保持原有报错语义
        let result = ScheduleParser.parse("<html><body><p>hello</p></body></html>", defaultTableId: 0)
        guard case .failure = result else { return XCTFail("expected parse failure") }  // Swift 5 Result 无 isSuccess/isFailure
        XCTAssertFalse(failureMessage(result).contains("Excel"))
    }
}
