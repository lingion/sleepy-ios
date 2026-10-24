// JwQzIeasParserTests.swift — ← JwQzIeasParserTest.kt (v1.0.61)
//
// 3 个用例逐一对应 Android 侧 JwQzIeasParserTest：
//   1. parses iEAS structured rows and expands weeks   5 课 / 高等数学 day=1 1-2 节 1-16 周 张老师 主楼101
//   2. preserves parity and discrete week semantics    大学英语 type=1 3-15; 程序设计 startWeeks [2,4,6]
//   3. confidence and feature identify iEAS table      confidence ≥ 80 且特征含 "table#queryGrkb"
//
// fixture: resources/qz_ieas/query-grkb.sample.html — 与 Android
// app/src/test/resources/jw/fixtures/qz_ieas/query-grkb.sample.html 同内容
// (合成 iEAS 行契约, BUAA 上游端点形态)。

import XCTest
@testable import Sleepy

final class JwQzIeasParserTests: XCTestCase {

    // MARK: - Fixture loading

    private func fixture() throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "query-grkb.sample", withExtension: "html", subdirectory: "resources/qz_ieas")
            ?? bundle.url(forResource: "query-grkb.sample", withExtension: "html", subdirectory: "qz_ieas")
            ?? bundle.url(forResource: "query-grkb.sample", withExtension: "html") else {
            XCTFail("fixture qz_ieas/query-grkb.sample.html 应打进测试 bundle")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Android case 1: parses iEAS structured rows and expands weeks

    func testParsesStructuredRowsAndExpandsWeeks() throws {
        let courses = try JwQzIeasParser(try fixture()).generateCourseList()
        XCTAssertEqual(courses.count, 5, "3 行 data-* 结构化课程 → 周次展开 5 门")
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" }, "fixture 应有 高等数学")
        XCTAssertEqual(math.day, 1)
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 16)
        XCTAssertEqual(math.teacher, "张老师")
        XCTAssertEqual(math.room, "主楼101")
    }

    // MARK: - Android case 2: preserves parity and discrete week semantics

    func testPreservesParityAndDiscreteWeekSemantics() throws {
        let courses = try JwQzIeasParser(try fixture()).generateCourseList()
        let english = try XCTUnwrap(courses.first { $0.name == "大学英语" }, "fixture 应有 大学英语")
        XCTAssertEqual(english.type, 1, "2-15(单) → 单周 type=1")
        XCTAssertEqual(english.startWeek, 3, "单周起始从 2 抬到 3")
        XCTAssertEqual(english.endWeek, 15)
        let programming = courses.filter { $0.name == "程序设计" }
        XCTAssertEqual(programming.map { $0.startWeek }, [2, 4, 6], "2,4,6周 → 离散三段升序")
    }

    // MARK: - Android case 3: confidence and feature identify iEAS table

    func testConfidenceAndFeatureIdentifyIeasTable() throws {
        let parser = JwQzIeasParser(try fixture())
        XCTAssertGreaterThanOrEqual(parser.confidenceValue, 80)
        XCTAssertTrue(parser.matchedFeatureList.contains("table#queryGrkb"))
    }

    // MARK: - Kotlin toIntOrNull 严格性回退 (v1.0.61 drift 锁定)

    /// data-day=" 3" 带空白 → Kotlin toIntOrNull 判 null 落回文本兜底;
    /// iOS 已对齐为不预 trim 的 Int()。无文本兜底时整行跳过, 不产出 day=3 课。
    func testWhitespacePaddedDayAttrFallsBackToTextParsing() throws {
        let padded = """
        <html><body><table id="queryGrkb">
          <tr data-course-name="空白日" data-day=" 3" data-weeks="1-2">
            <td>空白日</td><td></td><td></td><td>1-2周</td><td></td>
          </tr>
        </table></body></html>
        """
        XCTAssertEqual(try JwQzIeasParser(padded).generateCourseList().count, 0,
                       "带空白 data-day 无文本兜底 → 整行跳过 (Kotlin 语义)")

        let paddedWithText = """
        <html><body><table id="queryGrkb">
          <tr data-course-name="空白日" data-day=" 3" data-weeks="1-2">
            <td>空白日</td><td></td><td></td><td>1-2周</td><td>周三 第1,2节</td>
          </tr>
        </table></body></html>
        """
        let courses = try JwQzIeasParser(paddedWithText).generateCourseList()
        XCTAssertEqual(courses.count, 1, "文本兜底命中 周三 → 1-2 周合并为 1 段")
        XCTAssertTrue(courses.allSatisfy { $0.day == 3 })
    }

    /// data-start-node=" 1" 带空白 → 落回 第N,M节 文本解析 (第1,2节 → start=1/end=2,
    /// parseNodes 的 [-~,，、] 连接类含半角逗号)。
    func testWhitespacePaddedNodeAttrsFallBackToText() throws {
        let padded = """
        <html><body><table id="queryGrkb">
          <tr data-course-name="节点空白" data-day="2" data-start-node=" 1" data-end-node=" 2" data-weeks="1-3">
            <td>节点空白</td><td></td><td></td><td>1-3周</td><td>周二 第1,2节</td>
          </tr>
        </table></body></html>
        """
        let courses = try JwQzIeasParser(padded).generateCourseList()
        XCTAssertEqual(courses.count, 1, "1-3 周合并为 1 段")
        XCTAssertTrue(courses.allSatisfy { $0.startNode == 1 && $0.endNode == 2 },
                      "空白节点属性被拒 → 文本兜底 第1,2节")
    }

    func testEmptyAndAdversarialSourceGraceful() throws {
        XCTAssertEqual(try JwQzIeasParser("").generateCourseList().count, 0)
        XCTAssertEqual(try JwQzIeasParser("not html at all").generateCourseList().count, 0)
        // 有表无 id=queryGrkb → 仍走通用 table, 但行无课程名 → 0 课, 不抛
        XCTAssertEqual(try JwQzIeasParser("<table><tr><td></td></tr></table>").generateCourseList().count, 0)
        // confidence: 无 queryGrkb 锚点 → 0
        XCTAssertEqual(JwQzIeasParser("<table><tr><td>x</td></tr></table>").confidenceValue, 0)
    }
}
