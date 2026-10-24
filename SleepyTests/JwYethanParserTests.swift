// JwYethanParserTests.swift — regression contracts for JwYethanParser drift fixes (F038)
//
// 锁定两处与 Android JwYethanParser.kt 的行为对齐:
//   1. 多连字符只按「首个 '-'」切分(substringBefore/After 语义):
//      nodeStr "5-6-7" → start=5, end 回落 5; weekRun "7-8-9" → 整项丢弃。
//   2. trim 语义对齐 Kotlin .trim(): 首尾 \n/\r 一并去除。
// 全部用内联 JSON 字符串,不依赖测试资源。

import XCTest
@testable import Sleepy

final class JwYethanParserTests: XCTestCase {

    private func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func scheduleJSON(classTime: String, classPlace: String = "X100") -> String {
        return "{\"code\":\"00000\",\"data\":[{\"courseName\":\"课程A\",\"staffName\":\"教师甲\",\"classTime1\":\"\(jsonEscape(classTime))\",\"classPlace1\":\"\(jsonEscape(classPlace))\"}]}"
    }

    // MARK: - 多连字符节次: "5-6-7" → start=5,end=5(Android substringAfter("6-7").toIntOrNull()=null → ?: startNode)

    func test_multiHyphenNodeRange_fallsBackToStartNode() throws {
        let courses = try JwYethanParser(scheduleJSON(classTime: "1-8周 星期三 5-6-7节")).generateCourseList()
        XCTAssertEqual(courses.count, 1) // 周次段 (1,8) 共 1 门课
        XCTAssertEqual(courses.first?.startNode, 5)
        XCTAssertEqual(courses.first?.endNode, 5,
                       "多连字符节次必须回落 startNode(Android substringAfter 语义), 得 got \(String(describing: courses.first?.endNode))")
    }

    func test_multiHyphenWeekRun_isDropped() {
        // weekRuns("7-8-9") → e = "8-9".toIntOrNull() = null → continue → 空
        XCTAssertTrue(JwYethanParser("{}").weekRuns("7-8-9").isEmpty)
        XCTAssertEqual(JwYethanParser("{}").weekRuns("7、8-9-10、12").map { "\($0.0)-\($0.1)" }, ["7-7", "12-12"])
        XCTAssertEqual(JwYethanParser("{}").weekRuns("10-12").map { "\($0.0)-\($0.1)" }, ["10-12"])
    }

    func test_multiHyphenNodeSlot_wholeCourseEmittedWithFallbackRange() throws {
        // "7-8-9周 星期三 5节": 周次项 7-8-9 丢弃 → 0 门课
        let dropped = try JwYethanParser(scheduleJSON(classTime: "7-8-9周 星期三 5节")).generateCourseList()
        XCTAssertEqual(dropped.count, 0)
    }

    // MARK: - trim 语义: Kotlin .trim() 去首尾 \n/\r

    func test_leadingNewline_classTimeStillParses() throws {
        let courses = try JwYethanParser(scheduleJSON(classTime: "\n7、10-12周 星期三 5节\r")).generateCourseList()
        XCTAssertEqual(courses.map { "\($0.startWeek)-\($0.endWeek)" }.sorted(), ["10-12", "7-7"])
    }

    func test_newlineOnlyCourseName_isSkipped() throws {
        // "\ncourseName":"\n"" → trim 后空 → continue(Android 行为)
        let json = "{\"code\":\"00000\",\"data\":[{\"courseName\":\"\\n\",\"classTime1\":\"1周 星期一 1节\"}]}"
        XCTAssertEqual(try JwYethanParser(json).generateCourseList().count, 0)
    }

    func test_newlinePaddedPlace_trimmedByRoomOf() {
        XCTAssertEqual(JwYethanParser("{}").roomOf("\nX30547(犀浦)(教师甲)\r"), "X30547(犀浦)")
    }

    // MARK: - 原有正常路径不被破坏(红绿基线)

    func test_normalRanges_unaffected() throws {
        let courses = try JwYethanParser(scheduleJSON(classTime: "7、10-12、14-15周 星期三 5-6节")).generateCourseList()
        XCTAssertEqual(courses.count, 3)
        XCTAssertTrue(courses.allSatisfy { $0.startNode == 5 && $0.endNode == 6 && $0.day == 3 })
        XCTAssertEqual(courses.map { "\($0.startWeek)-\($0.endWeek)" }, ["7-7", "10-12", "14-15"])
    }
}
