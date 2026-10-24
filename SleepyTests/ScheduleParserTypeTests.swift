// ScheduleParserTypeTests.swift — ← ScheduleParserTypeTest.kt (逐用例)
// ScheduleParser.parseType 语义: 类型列缺失/未知 → 3=按周次, 而不是 0=每周。
// 修复"用户截图实验课 type=0 误标每周都上"的关键契约。

import XCTest
@testable import Sleepy

final class ScheduleParserTypeTests: XCTestCase {

    private func parseType(_ s: String) -> Int { ScheduleParser.parseType(s) }

    func testEmpty_returnsType3_byWeek() {
        XCTAssertEqual(3, parseType(""))
        XCTAssertEqual(3, parseType("   "))
    }

    func testExplicit0_returns0_weekly() {
        XCTAssertEqual(0, parseType("0"))
        XCTAssertEqual(0, parseType(" 每周 "))
    }

    func testExplicit1_returns1_oddWeek() {
        XCTAssertEqual(1, parseType("1"))
        XCTAssertEqual(1, parseType("单周"))
    }

    func testExplicit2_returns2_evenWeek() {
        XCTAssertEqual(2, parseType("2"))
        XCTAssertEqual(2, parseType("双周"))
    }

    func testExplicit3_returns3_byWeek() {
        XCTAssertEqual(3, parseType("3"))
        XCTAssertEqual(3, parseType("按周次"))
        XCTAssertEqual(3, parseType("自定义"))
    }

    func testUnknownGarbage_returns3_notZero() {
        // 关键: 未知值不再回退到 0=每周, 否则"周次=6 单次实验"会被错误标成每周
        XCTAssertEqual(3, parseType("每周都上但我不确定"))
        XCTAssertEqual(3, parseType("??"))
        XCTAssertEqual(3, parseType("99"))
    }

    private func parseOrThrow(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 0) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    /// 端到端验证: 解析真实粘贴数据时, 类型列缺失应得到 type=3
    func testEndToEnd_missingTypeColumn_resultsInType3() throws {
        let text = """
            <<<SLEEPY-BEGIN>>>
            <<<SLEEPY-TIME-BEGIN>>>
            第1节 08:00-08:45
            <<<SLEEPY-TIME-END>>>
            迈克尔逊-11#2003-3\t李平\t-\t4\t11-13\t6
            <<<SLEEPY-END>>>
            """
        let result = try parseOrThrow(text)
        XCTAssertEqual(1, result.courses.count)
        let c = result.courses[0]
        XCTAssertEqual(3, c.type, "类型缺失应得 type=3")
        XCTAssertEqual(6, c.startWeek, "第 6 周一次实验")
        XCTAssertEqual(6, c.endWeek)
        // 关键: inWeek 第 6 周 true, 第 5/7 周 false
        XCTAssertTrue(c.inWeek(6))
        XCTAssertFalse(c.inWeek(5))
        XCTAssertFalse(c.inWeek(7))
    }

    /// 端到端: 类型列显式写 0 应保留 0=每周 (兼容旧数据)
    func testEndToEnd_explicitType0_remains0() throws {
        let text = "高数\t张老师\tA101\t1\t1-2\t1-16\t0"
        let result = try parseOrThrow(text)
        XCTAssertEqual(0, result.courses[0].type)
    }

    /// 文本通路 type 语义防漂移 (audit issue: iOS 旧版 Int(parts[6]) ?? 0):
    /// "单/双/每周" 等非数字类型列必须走 parseType, 不得塌成 0=每周
    func testSimpleText_typeColumnText_usesParseType() throws {
        let odd = try parseOrThrow("体育\t李四\t操场\t2\t3-4\t1-16\t单")
        XCTAssertEqual(1, odd.courses[0].type)
        let even = try parseOrThrow("体育\t李四\t操场\t2\t3-4\t1-16\t双")
        XCTAssertEqual(2, even.courses[0].type)
        let weekly = try parseOrThrow("高数\t张三\tA101\t1\t1-2\t1-16\t每周")
        XCTAssertEqual(0, weekly.courses[0].type)
    }
}
