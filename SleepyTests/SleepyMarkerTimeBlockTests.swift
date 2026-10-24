// SleepyMarkerTimeBlockTests.swift — ← SleepyMarkerTest.kt 中 iOS 缺口的用例(2026-08-26 TIME 标识族 + 收割)
// ParserAuditTests 已覆盖 BEGIN/END 提取、全角归一、Markdown 剥离、day 钳制等;
// 本文件补: SLEEPY-TIME 块标识(严格块/自愈/括号变体/嵌套)、CSV 时间列收割、
// Sleepy JSON time 声明保真、WakeUp timeList 收割、邻接标识边界、step 半数向上取整。

import XCTest
@testable import Sleepy

final class SleepyMarkerTimeBlockTests: XCTestCase {

    private func parseOrThrow(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 0) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    private let courses = "高等数学\t张三\tA101\t1\t1-2\t1-16\t0\n大学英语\t李四\tB202\t3\t3-4\t1-16\t1"

    // ---- 2026-08-26: TIME block 标识符 ----

    func testTimeBlock_valid() throws {
        let input = "<<<SLEEPY-TIME-BEGIN>>>\n第1节 08:00-09:35\n第2节 09:55-11:30\n<<<SLEEPY-TIME-END>>>\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0"
        let r = try parseOrThrow(input)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(2, r.nodesPerDay)
        XCTAssertTrue(r.timeJson.contains("08:00"))
    }

    func testTimeBlock_missingEnd_selfHeal() throws {
        // 无 END 时: 连续作息行被吞掉, 碰到非作息行停止(自愈)
        let input = "<<<SLEEPY-TIME-BEGIN>>>\n第1节 08:00-09:35\n第2节 09:55-11:30\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0"
        let r = try parseOrThrow(input)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(2, r.nodesPerDay)
    }

    func testTimeBlock_noMarkers_inline() throws {
        // 无 TIME 标识时: 裸作息行混排兼容(旧行为)
        let input = "第1节 08:00-09:35\n第2节 09:55-11:30\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0"
        let r = try parseOrThrow(input)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(2, r.nodesPerDay)
    }

    func testTimeBlock_variantBrackets() throws {
        // 括号变体测试独立TIME块
        let input = "{{{SLEEPY-TIME-BEGIN}}}\n第1节 08:00-09:35\n第2节 09:55-11:30\n{{{SLEEPY-TIME-END}}}\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0"
        let r = try parseOrThrow(input)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(2, r.nodesPerDay)
    }

    func testTimeBlock_withinOuter() throws {
        // TIME 块在 BEGIN/END 内, 外层标识先被剥离, TIME 块在剩余内容中
        let input = "<<<SLEEPY-BEGIN>>>\n<<<SLEEPY-TIME-BEGIN>>>\n第1节 08:00-09:35\n<<<SLEEPY-TIME-END>>>\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0\n<<<SLEEPY-END>>>"
        let r = try parseOrThrow(input)
        XCTAssertEqual(1, r.courses.count)
    }

    func testTimeBlock_rangeForm_expandsToBothNodes() throws {
        // 审计: "第1-2节 08:20-10:00" 连上两节 → 每节各一条相同时间(区间展开)
        let input = "<<<SLEEPY-TIME-BEGIN>>>\n第1-2节 08:20-10:00\n<<<SLEEPY-TIME-END>>>\n" + courses
        let r = try parseOrThrow(input)
        XCTAssertEqual(2, r.courses.count)
        let nodes = TimeTableUtils.parseNodes(r.timeJson)
        XCTAssertEqual(2, nodes.count)
        XCTAssertEqual(1, nodes[0].node)
        XCTAssertEqual(2, nodes[1].node)
        XCTAssertEqual("08:20", hm(nodes[0].start))
        XCTAssertEqual("10:00", hm(nodes[1].end))
        XCTAssertEqual(4, r.nodesPerDay)  // max(作息 2, 课程到达 4)
    }

    private func hm(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // ---- 邻接标识边界(审计 issue: extractMarkedBody adjacent-marker edge) ----

    func testAdjacentMarkers_emptyBody_failsWithEmptyContent() {
        // END 紧跟 BEGIN → 空正文 → trim 后 ""(而非 BEGIN-only 分支把 END 字面量留在正文)
        let text = "<<<SLEEPY-BEGIN>>><<<SLEEPY-END>>>废话"
        XCTAssertEqual("", ScheduleParser.extractMarkedBody(text),
                       "邻接标识必须截出空正文, '<<<SLEEPY-END>>>' 字面量不得留在正文里")
        let result = ScheduleParser.parse(text, defaultTableId: 0)
        if case .success(let r) = result {
            XCTFail("应失败, got courses=\(r.courses.count) dropped=\(r.droppedLines)")
        }
    }

    // ---- CSV 时间列收割(← csv_timeColumns_harvested) ----

    func testCsv_timeColumns_harvested() throws {
        let csv = "课程,教师,教室,星期,节次,周次,开始时间,结束时间\n" +
            "高等数学,张三,A101,1,1-2,1-16,08:00,09:35\n" +
            "大学英语,李四,B202,3,3-4,1-16,13:30,15:05"
        let r = try parseOrThrow(csv)
        XCTAssertEqual(2, r.courses.count)
        XCTAssertEqual(4, r.nodesPerDay)
        let nodes = TimeTableUtils.parseNodes(r.timeJson)
        // 1-2 节 08:00-09:35: 首=08:00 末节次=2 的 end=09:35
        XCTAssertEqual("08:00", hm(nodes.first { $0.node == 1 }!.start))
        XCTAssertEqual("09:35", hm(nodes.first { $0.node == 2 }!.end))
        XCTAssertEqual("13:30", hm(nodes.first { $0.node == 3 }!.start))
        XCTAssertEqual("15:05", hm(nodes.first { $0.node == 4 }!.end))
    }

    // ---- Sleepy 自家 JSON 往返(← sleepyJsonRoundTrip_timeJsonPreserved) ----

    func testSleepyJsonRoundTrip_timeJsonPreserved() throws {
        let exported = """
            {
              "name": "我的课表",
              "startDate": "2026-09-07",
              "tableInfo": {
                "name": "我的课表",
                "startDate": "2026-09-07",
                "maxWeek": 20,
                "nodesPerDay": 3,
                "time": "[{\\"node\\":1,\\"start\\":\\"08:00\\",\\"end\\":\\"09:35\\"},{\\"node\\":2,\\"start\\":\\"09:55\\",\\"end\\":\\"11:30\\"}]"
              },
              "courses": [
                {"name":"高等数学","teacher":"张三","position":"A101","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"type":0}
              ]
            }
            """
        let r = try parseOrThrow(exported)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertFalse(r.timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // v7.10.16k 无损: 声明 nodesPerDay=3 > time 行数 2 → 取声明 3(稀疏 timeJson 不丢声明)
        XCTAssertEqual(3, r.nodesPerDay)
    }

    // ---- WakeUp 原生 timeList(← wakeupNative_timeList_harvested) ----

    func testWakeupNative_timeList_harvested() throws {
        let json = """
            {
              "name": "WakeUp表",
              "startDate": "2026-09-07",
              "tableInfo": {
                "timeList": [
                  {"node": 1, "startTime": "08:00", "endTime": "09:35"},
                  {"node": 2, "startTime": "09:55", "endTime": "11:30"}
                ]
              },
              "courses": [
                {"name":"高数","teacher":"张三","position":"A101","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"type":0}
              ]
            }
            """
        let r = try parseOrThrow(json)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(2, r.nodesPerDay)
        XCTAssertTrue(r.timeJson.contains("\"node\":1"))
        XCTAssertTrue(r.timeJson.contains("09:35"))
    }

    // ---- ICS step 半数向上取整(审计: Math.round vs banker's rounding) ----
    // 125min / 50 = 2.5 → Java Math.round 半进位 → 3; Swift 默认 toNearestOrEven → 2(旧漂移)

    func testIcs_extractIcsTime_stepRoundsHalfUp() throws {
        // 单事件无 "第X-Y节" 描述: 08:00-10:05 (125min) → step=3
        let ics = """
            BEGIN:VCALENDAR
            VERSION:2.0
            PRODID:-//test//EN
            BEGIN:VEVENT
            UID:half@up
            DTSTART:20260907T080000
            DTEND:20260907T100500
            SUMMARY:半进位测试
            DESCRIPTION:老师：张三
            END:VEVENT
            END:VCALENDAR
            """
        let r = try parseOrThrow(ics)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(1, r.courses[0].startNode)
        XCTAssertEqual(3, r.courses[0].step, "125min/50 = 2.5 必须向上取整为 3(← Math.round 半进位)")
    }

    // ---- 课名反写/乱行 dropped(← garbageLines_reportedInDropped) ----

    func testGarbageLines_reportedInDropped() throws {
        let text = "<<<SLEEPY-BEGIN>>>\n\(courses)\n这是AI瞎说的一行\n高数\t张三\n<<<SLEEPY-END>>>"
        let r = try parseOrThrow(text)
        XCTAssertEqual(2, r.courses.count)
        XCTAssertEqual(2, r.droppedLines.count)
        XCTAssertTrue(r.droppedLines.contains { $0.contains("这是AI瞎说的") })
    }

    // ---- plain 时间表混排收割 + 无损(← plainText_timeTableLines_harvested) ----

    func testPlainText_timeTableLines_harvested() throws {
        let text = "<<<SLEEPY-BEGIN>>>\n第1节 08:00-09:35\n第2节 09:55-11:30\n第3节 13:30-15:05\n\(courses)\n<<<SLEEPY-END>>>"
        let r = try parseOrThrow(text)
        XCTAssertEqual(2, r.courses.count)
        XCTAssertFalse(r.timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // v7.10.16k 无损: 节次数 = max(作息声明 3, 课程到达 4) = 4
        XCTAssertEqual(4, r.nodesPerDay)
        let nodes = TimeTableUtils.parseNodes(r.timeJson)
        XCTAssertEqual(3, nodes.count)
        XCTAssertEqual("08:00", hm(nodes[0].start))
        XCTAssertEqual("09:35", hm(nodes[0].end))
        XCTAssertEqual("13:30", hm(nodes[2].start))
    }

    func testPlainText_noTimeTable_unaffected() throws {
        // 没有时间行的纯文本 → timeJson 空(不伪造时间); nodesPerDay = 课程到达 4 节(无损)
        let r = try parseOrThrow(courses)
        XCTAssertEqual("", r.timeJson)
        XCTAssertEqual(4, r.nodesPerDay)
    }

    // ---- Excel Frameset 分派位置: frameset 判定在 sleepy-v1 之后、courseDetailJson 之前
    // (审计 issue: Excel frameset branch missing from dispatch) — 已有 ExcelFramesetHtmlTests
    // 覆盖检测/报错文案, 此处锁"含 courseDetailJson 字样的 frameset 仍按 frameset 报错"路径
    func testFrameset_checkedBeforeJsonDispatch() {
        let html = """
            <html><meta name="Excel Workbook Frameset"><frameset rows="*,18">
            <frame src="课表.files/sheet001.html">
            </frameset><!-- "courseDetailJson" 诱饵字样也不得改道 JSON --></html>
            """
        let result = ScheduleParser.parse(html, defaultTableId: 0)
        guard case .failure(let e) = result else { return XCTFail("frameset 必须报错") }
        XCTAssertTrue(e.localizedDescription.contains("Excel"), "msg=\(e.localizedDescription)")
    }
}
