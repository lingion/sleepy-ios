// ExportImportRoundTripTests.swift — ← ExportImportRoundTripTest.kt (逐用例)
// 端到端验证:导出-导入闭环
// 1. 构造真实 HEU 课表
// 2. 用 ScheduleExporter 导出
// 3. 用 ScheduleParser 解析导出的内容
// 4. 验证 courses 数和字段一致

import XCTest
@testable import Sleepy

final class ExportImportRoundTripTests: XCTestCase {

    private func heuTable() -> TimeTableEntity {
        TimeTableEntity(
            name: "2026 春学期",
            startDate: "2026-02-23",
            maxWeek: 18,
            nodesPerDay: 13,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"08:50","end":"09:35"}]"#,
            color: "#FF6750A4",
            isDefault: true,
            id: 1
        )
    }

    private func heuCourses() -> [CourseEntity] {
        [
            CourseEntity(
                groupId: "",
                tableId: 1,
                courseName: "工科数学分析(二)",
                teacher: "王立刚",
                room: "21B2086中(西)",
                day: 2, startNode: 3, step: 3,
                startWeek: 2, endWeek: 8, type: 0,
                color: "#FF6750A4",
                id: 0
            ),
            CourseEntity(
                groupId: "",
                tableId: 1,
                courseName: "军事理论",
                teacher: "刁莹",
                room: "21B0117中(东)",
                day: 2, startNode: 6, step: 2,
                startWeek: 2, endWeek: 18, type: 0,
                color: "#FF6750A4",
                id: 0
            )
        ]
    }

    func testWakeUpShareTextRoundTrip() {  // ← wakeUpShareText_roundTrip
        let exported = ScheduleExporter.exportWakeUpShareText(heuTable(), heuCourses())
        let result = ScheduleParser.parse(exported, defaultTableId: 999)
        switch result {
        case .success(let parsed):
            XCTAssertEqual(2, parsed.courses.count, "Course count mismatch")
            XCTAssertEqual("工科数学分析(二)", parsed.courses[0].courseName)
            XCTAssertEqual("王立刚", parsed.courses[0].teacher)
            XCTAssertEqual(2, parsed.courses[0].day)
            XCTAssertEqual(3, parsed.courses[0].startNode)
            XCTAssertEqual(3, parsed.courses[0].step)
            XCTAssertEqual(2, parsed.courses[0].startWeek)
            XCTAssertEqual(8, parsed.courses[0].endWeek)
        case .failure(let e):
            XCTFail("Parse should succeed, got: \(e)")
        }
    }

    func testWakeUpJsonRoundTrip() {  // ← wakeUpJson_roundTrip
        let exported = ScheduleExporter.exportWakeUpJson(heuTable(), heuCourses())
        let result = ScheduleParser.parse(exported, defaultTableId: 999)
        switch result {
        case .success(let parsed):
            XCTAssertEqual(2, parsed.courses.count, "Course count mismatch")
        case .failure(let e):
            XCTFail("Parse should succeed, got: \(e)")
        }
    }

    func testIcsRoundTrip() {  // ← ics_roundTrip
        let exported = ScheduleExporter.exportIcs(heuTable(), heuCourses())
        let result = ScheduleParser.parse(exported, defaultTableId: 999)
        switch result {
        case .success(let parsed):
            XCTAssertEqual(2, parsed.courses.count, "ICS should round-trip 2 courses, got \(parsed.courses.count)")
        case .failure(let e):
            XCTFail("Parse should succeed, got: \(e)")
        }
    }
}

// MARK: - iOS 补充:其余 4 种解析格式覆盖(Android 无独立测试,靠 round-trip 之外的真实格式守卫)

final class ScheduleParserFormatTests: XCTestCase {

    func testSimpleTextParsing() {
        // ← parseSimpleText 文档示例
        let text = "高等数学\t张三\tA101\t1\t1-2\t1-16\t0\n大学英语 李四 B202 2 3-4 1-16 0\n# 注释行\n"
        let r = ScheduleParser.parse(text, defaultTableId: 1)
        guard case .success(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(2, p.courses.count)
        let c0 = p.courses[0]
        XCTAssertEqual("高等数学", c0.courseName)
        XCTAssertEqual("张三", c0.teacher)
        XCTAssertEqual("A101", c0.room)
        XCTAssertEqual(1, c0.day)
        XCTAssertEqual(1, c0.startNode)
        XCTAssertEqual(2, c0.step)
        XCTAssertEqual(1, c0.startWeek)
        XCTAssertEqual(16, c0.endWeek)
    }

    func testCsvParsingMultiRangeWeeks() {
        // 多区间周次展开: "2-5,7-9" → 2 条
        let csv = "课程名,教师,教室,星期,节次,周次,类型\n高数,张,A101,周一,3-4,2-5,7-9,每周\n"
        // 上面列数错位 — 用正确 7 列:
        let csv2 = "课程名,教师,教室,星期,节次,周次,类型\n高数,张,A101,周一,3-4,\"2-5,7-9\",每周\n"
        _ = csv
        let r = ScheduleParser.parse(csv2, defaultTableId: 1)
        guard case .success(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(2, p.courses.count, "多区间周次应展开 2 条")
        XCTAssertEqual(2, p.courses[0].startWeek)
        XCTAssertEqual(5, p.courses[0].endWeek)
        XCTAssertEqual(7, p.courses[1].startWeek)
        XCTAssertEqual(9, p.courses[1].endWeek)
    }

    func testCsvQuotedFieldEscape() {
        // Kotlin 逐字符语义: 不在引号内的 " → 开引号(字符本身丢弃);引号内 "" → 字面 "
        // 所以 含""引号""课 → 含"引号"课(外层引号成对开闭,内层 "" 保留一个)
        // 而 含"引号"课(单引号) → 含引号课(引号剥离)
        let csv = "课程名,教师,教室,星期,节次,周次\n含\"引号\"课,张,A101,2,1-2,1-16\n"
        let r = ScheduleParser.parse(csv, defaultTableId: 1)
        guard case .success(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(1, p.courses.count)
        XCTAssertEqual("含引号课", p.courses[0].courseName, "单引号剥离(Kotlin 语义)")
    }

    func testCsvStartEndNodeColumns() {
        // 教务处两列式: 开始节数+结束节数
        let csv = "课程,老师,地点,周几,开始节数,结束节数,周数\n英语,Li,R2,3,5,8,2-16\n"
        let r = ScheduleParser.parse(csv, defaultTableId: 1)
        guard case .success(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(1, p.courses.count)
        XCTAssertEqual(5, p.courses[0].startNode)
        XCTAssertEqual(4, p.courses[0].step)  // 8-5+1
    }

    func testHtmlTableParsing() {
        let html = """
        <html><body><table>
        <tr><th>课程</th><th>教师</th><th>教室</th><th>星期</th><th>节次</th><th>周次</th></tr>
        <tr><td>高数</td><td>张三</td><td>A101</td><td>周一</td><td>1-2</td><td>1-16</td></tr>
        </table></body></html>
        """
        let r = ScheduleParser.parse(html, defaultTableId: 1)
        guard case .success(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(1, p.courses.count)
        XCTAssertEqual("高数", p.courses[0].courseName)
        XCTAssertEqual(1, p.courses[0].day)
        XCTAssertEqual(1, p.courses[0].startNode)
    }

    func testEmptyAndGarbage() {
        // 空内容 → failure
        if case .success = ScheduleParser.parse("   \n  ", defaultTableId: 1) {
            XCTFail("空内容应失败")
        }
        // 无法解析的纯文本(<6 字段) → failure
        if case .success = ScheduleParser.parse("hello world", defaultTableId: 1) {
            XCTFail("垃圾文本应失败")
        }
    }

    func testIcsOddEvenWeekFirstWeekSelection() {
        // ICS 导出:单周课 startWeek 偶数 → 首发生周 +1
        let table = TimeTableEntity(name: "t", startDate: "2026-02-23", id: 1)
        let oddCourse = CourseEntity(
            groupId: "", tableId: 1, courseName: "单周课", teacher: "", room: "",
            day: 1, startNode: 1, step: 2,
            startWeek: 2, endWeek: 10, type: 1,   // type=1 单周,2 是偶 → 首周=3
            color: "#FF000000", id: 5
        )
        let ics = ScheduleExporter.exportIcs(table, [oddCourse])
        // 2026-02-23 是周一。周3(第3周) = 02-23 + 14天 = 03-09
        XCTAssertTrue(ics.contains("DTSTART:20260309"), "单周课首发生周应为第 3 周(03-09), got: \n\(ics.prefix(500))")
        XCTAssertTrue(ics.contains("INTERVAL=2"))
    }
}
