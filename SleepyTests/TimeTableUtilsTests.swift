// TimeTableUtilsTests.swift — TimeTableUtils 无 Android 专测,按 Kotlin 函数行为写对齐测试
// (G4 链①地基;SmartPeriodConfig 的 Android 用例见 SmartPeriodConfigTests)

import XCTest
@testable import Sleepy

final class TimeTableUtilsTests: XCTestCase {

    func testDefaultTimeJsonParses12Nodes() {
        let nodes = TimeTableUtils.parseNodes(TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertEqual(12, nodes.count)
        XCTAssertEqual(1, nodes[0].node)
        XCTAssertEqual("08:00", TimeTableUtils.formatTime(nodes[0].start))
        XCTAssertEqual("22:30", TimeTableUtils.formatTime(nodes[11].end))
    }

    func testParseNodesInvalidJsonReturnsEmpty() {
        XCTAssertEqual([], TimeTableUtils.parseNodes("not json"))
        XCTAssertEqual([], TimeTableUtils.parseNodes(""))
    }

    func testCourseTimeString() {
        // 1-2 节 → 08:00-09:40
        XCTAssertEqual("08:00-09:40",
            TimeTableUtils.courseTimeString(courseStartNode: 1, courseStep: 2, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        // 5-6 节 → 14:00-15:40
        XCTAssertEqual("14:00-15:40",
            TimeTableUtils.courseTimeString(courseStartNode: 5, courseStep: 2, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        // 找不到节点 → nil
        XCTAssertNil(TimeTableUtils.courseTimeString(courseStartNode: 99, courseStep: 1, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
    }

    func testCourseTimePartsOwnTime() {
        let parts = TimeTableUtils.courseTimeParts(courseStartNode: 3, courseStep: 2, timeJson: "",
                                                   ownTime: true, startTime: "18:30", endTime: "20:55")
        let p = parts; XCTAssertNotNil(p); if let p = p { XCTAssertEqual("18:30", p.0); XCTAssertEqual("20:55", p.1) }
    }

    func testTimeToNode() {
        // 08:00-09:40 → 覆盖节点1(start 08:00 ≤ 08:00)到节点2(end 09:40 ≥ 09:40) → (1,2)
        let r1 = TimeTableUtils.timeToNode("08:00", "09:40", TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertNotNil(r1); if let r = r1 { XCTAssertEqual(1, r.0); XCTAssertEqual(2, r.1) }
        // 早于第一节 → 第1节; 晚于最后一节 → 最后一节: 07:00-23:00 → (1,12)
        let r2 = TimeTableUtils.timeToNode("07:00", "23:00", TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertNotNil(r2); if let r = r2 { XCTAssertEqual(1, r.0); XCTAssertEqual(12, r.1) }
        // 非法格式 → nil
        XCTAssertNil(TimeTableUtils.timeToNode("bad", "09:40", TimeTableUtils.DEFAULT_TIME_JSON))
        // 空 timeJson → nil
        XCTAssertNil(TimeTableUtils.timeToNode("08:00", "09:40", "[]"))
    }

    func testRowsRoundTrip() {
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertEqual(12, rows.count)
        let json = TimeTableUtils.buildTimeJsonFromRows(rows)
        let rows2 = TimeTableUtils.parseTimeSlotRows(json)
        XCTAssertEqual(rows, rows2)
    }

    func testRemoveAndRenumber() {
        var rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.DEFAULT_TIME_JSON)
        rows = TimeTableUtils.removeAndRenumber(rows, node: 3)
        XCTAssertEqual(11, rows.count)
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], rows.map { $0.node })
        // 原 node4 (10:55) 现在是 node3(删的是 node3=10:00)
        XCTAssertEqual("10:55", rows[2].start)
    }

    func testAppendEmptyRow() {
        var rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.DEFAULT_TIME_JSON)
        rows = TimeTableUtils.appendEmptyRow(rows)
        XCTAssertEqual(13, rows.count)
        XCTAssertEqual(13, rows[12].node)
        XCTAssertEqual("", rows[12].start)
    }

    func testEntityInWeek() {
        var c = CourseEntity(groupId: "g", tableId: 1, courseName: "高数", day: 1,
                             startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "#FF6750A4")
        XCTAssertTrue(c.inWeek(1))
        XCTAssertTrue(c.inWeek(16))
        XCTAssertFalse(c.inWeek(0))
        XCTAssertFalse(c.inWeek(17))
        c.type = 1 // 单周
        XCTAssertTrue(c.inWeek(3))
        XCTAssertFalse(c.inWeek(2))
        c.type = 2 // 双周
        XCTAssertTrue(c.inWeek(2))
        XCTAssertFalse(c.inWeek(3))
    }

    func testEntityNormalizeNode() {
        let c = CourseEntity(groupId: "g", tableId: 1, courseName: "晚课", day: 1,
                             startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "#FF6750A4",
                             ownTime: true, startTime: "19:00", endTime: "20:40")
        let n = c.normalizeNode(timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        // 19:00 → 节点9(start 19:00), 20:40 → 节点10(end 20:40) → (9, 2)
        XCTAssertEqual(9, n.startNode)
        XCTAssertEqual(2, n.step)
        // ownTime=false 原样返回
        let plain = CourseEntity(groupId: "g", tableId: 1, courseName: "x", day: 1,
                                 startNode: 3, step: 2, startWeek: 1, endWeek: 16, color: "#FF6750A4")
        let pn = plain.normalizeNode(timeJson: TimeTableUtils.DEFAULT_TIME_JSON); XCTAssertEqual(plain.startNode, pn.startNode); XCTAssertEqual(plain.step, pn.step); XCTAssertEqual(plain.courseName, pn.courseName)
    }
}
