// Issue55OwnTimeTests.swift — ← Issue55OwnTimeRoundTripTest.kt + Issue55IcsOwnTimeRoundTripTest.kt
// issue#55: 非标准时间课程(ownTime 20:50-22:00)导出→导入往返必须保真;
// 缺字段的原生 WakeUp 分享/ICS 保持 ownTime=false 兼容, 不得瞎填。

import XCTest
@testable import Sleepy

final class Issue55OwnTimeTests: XCTestCase {

    private func table() -> TimeTableEntity {
        var t = TimeTableEntity(name: "Test55", startDate: "2026-09-07")
        t.id = 1
        t.maxWeek = 20
        t.nodesPerDay = 12
        t.timeJson = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},{\"node\":11,\"start\":\"20:50\",\"end\":\"21:35\"},{\"node\":12,\"start\":\"21:45\",\"end\":\"22:30\"}]"
        t.color = "#FF6750A4"
        t.isDefault = true
        return t
    }

    private func ownTimeCourse() -> CourseEntity {
        CourseEntity(
            groupId: "", tableId: 1,
            courseName: "OwnTimeCourse", teacher: "Prof X", room: "B201",
            day: 2, startNode: 11, step: 2,
            startWeek: 1, endWeek: 16, type: 0,
            color: "#FF6750A4",
            ownTime: true, startTime: "20:50", endTime: "22:00",
            id: 0
        )
    }

    private func parseOrThrow(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 999) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // ---- JSON 两路 (← Issue55OwnTimeRoundTripTest) ----

    func testWakeUpJsonExport_ContainsStartEndTime() throws {
        let exported = ScheduleExporter.exportWakeUpJson(table(), [ownTimeCourse()])
        XCTAssertTrue(exported.contains("\"startTime\""), "WakeUp JSON 导出必须含 startTime; got: \(exported)")
        XCTAssertTrue(exported.contains("\"endTime\""))
        XCTAssertTrue(exported.contains("20:50"))
        XCTAssertTrue(exported.contains("22:00"))
    }

    func testShareTextRoundTrip_PreservesOwnTime() throws {
        let exported = ScheduleExporter.exportWakeUpShareText(table(), [ownTimeCourse()])
        let parsed = try parseOrThrow(exported)
        XCTAssertEqual(1, parsed.courses.count)
        let c = parsed.courses[0]
        XCTAssertTrue(c.ownTime, "ownTime 必须恢复; got startTime=\(c.startTime) endTime=\(c.endTime)")
        XCTAssertEqual("20:50", c.startTime)
        XCTAssertEqual("22:00", c.endTime)
    }

    func testWakeUpJsonRoundTrip_PreservesOwnTime() throws {
        let exported = ScheduleExporter.exportWakeUpJson(table(), [ownTimeCourse()])
        let parsed = try parseOrThrow(exported)
        XCTAssertEqual(1, parsed.courses.count)
        let c = parsed.courses[0]
        XCTAssertTrue(c.ownTime, "ownTime 必须恢复")
        XCTAssertEqual("20:50", c.startTime)
        XCTAssertEqual("22:00", c.endTime)
    }

    func testBackCompat_NoOwnTimeFields_StaysFalse() throws {
        // 原生 WakeUp 分享不带 startTime/endTime — 不得崩, 维持 ownTime=false 兼容
        let raw = """
            【来自Sleepy】课程分享：
            {"name":"T","startDate":"2026-09-07","courseDetailJson":"%5B%7B%22name%22%3A%22X%22%2C%22day%22%3A1%2C%22startNode%22%3A1%2C%22step%22%3A1%2C%22startWeek%22%3A1%2C%22endWeek%22%3A16%2C%22type%22%3A0%2C%22color%22%3A%22%23FF6750A4%22%2C%22teacher%22%3A%22%22%2C%22position%22%3A%22%22%7D%5D"}
            """
        let parsed = try parseOrThrow(raw)
        let c = parsed.courses[0]
        XCTAssertFalse(c.ownTime, "缺字段时 ownTime 必须保持 false, 不得瞎填")
        XCTAssertEqual("", c.startTime)
        XCTAssertEqual("", c.endTime)
    }

    // ---- ICS 路 (← Issue55IcsOwnTimeRoundTripTest) ----

    func testIcsRoundTrip_PreservesOwnTime() throws {
        let exported = ScheduleExporter.exportIcs(table(), [ownTimeCourse()])
        // 导出端指纹: DESCRIPTION 里有时间行
        XCTAssertTrue(exported.contains("20:50-22:00"), "导出 DESCRIPTION 必须含 20:50-22:00 时间行")

        let parsed = try parseOrThrow(exported)
        XCTAssertEqual(1, parsed.courses.count)
        let c = parsed.courses[0]
        XCTAssertTrue(c.ownTime, "ownTime 必须恢复; got startTime=\(c.startTime) endTime=\(c.endTime)")
        XCTAssertEqual("20:50", c.startTime)
        XCTAssertEqual("22:00", c.endTime)
        // 节次定位仍保留(网格布局兜底用)
        XCTAssertEqual(11, c.startNode)
        XCTAssertEqual(2, c.step)
    }

    func testIcsWakeUpNative_WithoutTimeLine_StaysFalse() throws {
        // WakeUp 原生 ICS: DESCRIPTION="第X - Y节\n教室\n教师", 无 Sleepy 时间行
        let wakeUpIcs = """
            BEGIN:VCALENDAR
            VERSION:2.0
            PRODID:-//WakeUpSchedule//Course//CN
            BEGIN:VEVENT
            UID:1@wakeup
            DTSTAMP:20260922T000000Z
            DTSTART:20260908T205000
            DTEND:20260908T220000
            RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261222T235959Z
            SUMMARY:WakeUpCourse
            LOCATION:教室W
            DESCRIPTION:第11 - 12节\\n教室W\\n王老师
            END:VEVENT
            END:VCALENDAR
            """
        let parsed = try parseOrThrow(wakeUpIcs)
        let c = parsed.courses[0]
        XCTAssertFalse(c.ownTime, "无 Sleepy 时间行时 ownTime 必须保持 false")
        XCTAssertEqual("", c.startTime)
        XCTAssertEqual("", c.endTime)
        XCTAssertEqual("王老师", c.teacher)
    }
}
