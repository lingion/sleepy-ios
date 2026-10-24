// Ics28NeuPeriodsTests.swift — ← Ics28NeuPeriodsTest.kt + NeuRealFixtureImportTest.kt + NeuRoundTripIcsTest.kt
// issue #28: NEU ICS "导入前自动识别每节课时间乱成一团" — 教学块模型整表重建。
// NEU 导出五个教学块 [08:00-09:40, 10:00-11:40, 14:00-15:40, 16:00-17:40, 18:30-22:00]
// 对应节次 [1-2, 3-4, 5-6, 7-8, 9-12]; 连排事件跨两个教学块。
// 旧实现两个缺陷(真实文件上同时发生):
//  1) 同一开始时刻"最长事件步数"套给所有事件 → 08:00-09:40 被拉成 1-4 节;
//  2) 长块路径把长事件 start 写进 endNode.start → 第4节时间倒挂。

import XCTest
@testable import Sleepy

final class Ics28NeuPeriodsTests: XCTestCase {

    private func neuFixture() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "neu-schedule-2026-2027-1", withExtension: "ics")
            ?? bundle.url(forResource: "neu-schedule-2026-2027-1", withExtension: "ics", subdirectory: "resources")
            ?? bundle.url(forResource: "neu-schedule-2026-2027-1", withExtension: "ics", subdirectory: "SleepyTests_resources")
        return try String(contentsOf: try XCTUnwrap(url, "NEU fixture is missing"), encoding: .utf8)
    }

    private func parseOrThrow(_ text: String, tableId: Int64 = 1) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: tableId) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // ---- ← Ics28NeuPeriodsTest.kt ----

    func testNeuIcs_eventsSpanAtomicBlocks_notInflated() throws {
        let pr = try parseOrThrow(neuFixture())
        // 真实文件全部 7 种时间形态 → 期望映射。旧实现把 (1,2) 和 (5,2) 整体吞掉
        // (08:00/14:00 两个时刻的所有事件都被最长事件拉成 4 步), 所以 (1,2)/(5,2) 必缺。
        let expected: Set<[Int]> = [
            [1, 2],  // 08:00-09:40 上午一
            [1, 4],  // 08:00-11:40 上午连排(跨 1-2 + 3-4)
            [3, 2],  // 10:00-11:40 上午二
            [5, 2],  // 14:00-15:40 下午一
            [5, 4],  // 14:00-17:40 下午连排(跨 5-6 + 7-8)
            [7, 2],  // 16:00-17:40 下午二
            [9, 4],  // 18:30-22:00 晚间(9-12)
        ]
        let actual = Set(pr.courses.map { [$0.startNode, $0.step] })
        XCTAssertEqual(expected, actual,
                       "span set mismatch: missing=\(expected.subtracting(actual)) unexpected=\(actual.subtracting(expected))")
    }

    func testNeuIcs_timetableIsCompleteMonotonicAndAnchored() throws {
        let pr = try parseOrThrow(neuFixture())
        let rows = TimeTableUtils.parseTimeSlotRows(pr.timeJson)

        XCTAssertEqual(12, pr.nodesPerDay, "nodesPerDay")
        XCTAssertEqual(Array(1...12), rows.map { $0.node }, "timetable rows")

        // 严格递增: 第 N+1 节开始不得早于第 N 节开始(旧实现第4节 08:00 排第3节 10:00 之后)
        for i in 1..<rows.count {
            XCTAssertLessThan(rows[i - 1].start, rows[i].start,
                              "node \(rows[i].node) start \(rows[i].start) not after node \(rows[i-1].node) start \(rows[i-1].start)")
        }
        // 每节 start < end
        for row in rows {
            XCTAssertLessThan(row.start, row.end, "node \(row.node) start>=end (\(row.start)>=\(row.end))")
        }

        // 教学块锚点: 块首节 start = 块起点钟点, 块末节 end = 块终点钟点
        let anchors: [Int: String] = [
            1: "08:00", 2: "09:40",
            3: "10:00", 4: "11:40",
            5: "14:00", 6: "15:40",
            7: "16:00", 8: "17:40",
            9: "18:30", 12: "22:00",
        ]
        let blockStarts: Set<Int> = [1, 3, 5, 7, 9]
        for (node, time) in anchors {
            let row = rows.first { $0.node == node }
            XCTAssertNotNil(row, "node \(node) missing")
            guard let row else { continue }
            let actual = blockStarts.contains(node) ? row.start : row.end
            XCTAssertEqual(time, actual, "node \(node) expected \(time) got start=\(row.start) end=\(row.end)")
        }
    }

    // ---- ← NeuRealFixtureImportTest.kt ----

    func testRealNeuIcs_mapsKnownDailyTimeBlocksToActualSections() throws {
        let ics = try neuFixture()
        let parsed = try parseOrThrow(ics, tableId: 999)
        XCTAssertFalse(parsed.courses.isEmpty)
        XCTAssertEqual(Set([1, 3, 5, 7, 9]), Set(parsed.courses.map { $0.startNode }),
                       "courses=\(parsed.courses.map { ($0.startNode, $0.step) }) nodes=\(parsed.nodesPerDay) time=\(parsed.timeJson)")
        XCTAssertEqual(12, parsed.nodesPerDay)
    }

    // ---- ← NeuRoundTripIcsTest.kt ----

    private func roundTripTable(_ first: ScheduleParser.ParseResult) -> TimeTableEntity {
        var t = TimeTableEntity(name: "neu-round-trip", startDate: first.startDate)
        t.id = 999
        t.maxWeek = first.courses.map { $0.endWeek }.max() ?? 1
        t.nodesPerDay = first.nodesPerDay
        t.timeJson = first.timeJson
        t.createdAt = 0
        return t
    }

    func testNeuRoundTrip_preservesCourseCountAndNodeSpan() throws {
        let first = try parseOrThrow(try neuFixture(), tableId: 999)
        XCTAssertFalse(first.courses.isEmpty, "parser dropped all courses")

        let exported = ScheduleExporter.exportIcs(roundTripTable(first), first.courses)
        let second = try parseOrThrow(exported, tableId: 999)

        XCTAssertEqual(first.courses.count, second.courses.count,
                       "Re-imported course count must equal the first parse")
        // Day 1..7 only.
        XCTAssertTrue(second.courses.allSatisfy { (1...7).contains($0.day) }, "Days must stay within 1..7")
        // Re-imported nodes must fit within the originally harvested window.
        let maxNode = first.nodesPerDay
        XCTAssertTrue(second.courses.allSatisfy { $0.startNode >= 1 && $0.startNode + $0.step - 1 <= maxNode },
                      "Second-parse nodes must stay within nodesPerDay=\(maxNode)")
    }

    func testNeuRoundTrip_eventDayWeekIsMappedBackToIdenticalRange() throws {
        let first = try parseOrThrow(try neuFixture(), tableId: 999)
        let exported = ScheduleExporter.exportIcs(roundTripTable(first), first.courses)
        let second = try parseOrThrow(exported, tableId: 999)

        func key(_ c: CourseEntity) -> [Int] { [c.day, c.startNode, c.step] }
        let firstByKey = Dictionary(grouping: first.courses, by: key)
        let secondByKey = Dictionary(grouping: second.courses, by: key)

        for (k, originals) in firstByKey {
            guard let reimported = secondByKey[k] else {
                return XCTFail("No re-imported match for day=\(k[0]) node=\(k[1]) step=\(k[2])")
            }
            let minStart = originals.map { $0.startWeek }.min()!
            let maxEnd = originals.map { $0.endWeek }.max()!
            let rMin = reimported.map { $0.startWeek }.min()!
            let rMax = reimported.map { $0.endWeek }.max()!
            XCTAssert(minStart == rMin && maxEnd == rMax,
                      "Week span must survive round-trip for \(k): (\(minStart),\(maxEnd)) vs (\(rMin),\(rMax))")  // 元组不合 Equatable, 用复合条件
        }
    }

    func testNeuRoundTrip_preservesDeclaredNodeWindow() throws {
        let first = try parseOrThrow(try neuFixture(), tableId: 999)
        let second = try parseOrThrow(
            ScheduleExporter.exportIcs(roundTripTable(first), first.courses), tableId: 999)

        XCTAssertEqual(first.nodesPerDay, second.nodesPerDay, "Declared node window must survive round-trip")
        let firstRows = TimeTableUtils.parseTimeSlotRows(first.timeJson)
        let secondRows = TimeTableUtils.parseTimeSlotRows(second.timeJson)
        XCTAssertTrue(firstRows.contains { $0.edgeClass == nil }, "Original timetable must contain standard rows")
        XCTAssertTrue(secondRows.contains { $0.edgeClass == nil }, "Re-imported timetable must contain standard rows")
    }
}
