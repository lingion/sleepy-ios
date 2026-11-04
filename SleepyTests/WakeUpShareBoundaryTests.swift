import XCTest
@testable import Sleepy

final class WakeUpShareBoundaryTests: XCTestCase {
    private func convert(nodes: Any = 10_000, detail: [String: Any] = [:],
                         ui: [String: Any] = [:], slotNode: Any = 10_000) throws -> String {
        var course: [String: Any] = ["id": 1, "day": 7, "startNode": 9_999, "step": 2,
                                     "startWeek": 1, "endWeek": 16, "type": 0]
        course.merge(detail) { _, new in new }
        var config: [String: Any] = ["nodes": nodes, "maxWeek": 16, "startDate": "2026/9/7"]
        config.merge(ui) { _, new in new }
        let blocks: [Any] = [[:], [["node": slotNode, "startTime": "08:00", "endTime": "08:45"]],
                             config, [["id": 1, "courseName": "边界课程"]], [course]]
        let raw = try blocks.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
        }.joined(separator: "\n")
        return try WakeUpShareProtocol.buildScheduleJson(WakeUpShareProtocol.parseRawScheduleData(raw))
    }

    func testScalarAndArrayUpperBoundaryReallyParseThrough() throws {
        for nodes in [10_000, "10000", [1, 10_000], ["1", "10000", "10000"]] as [Any] {
            let parsed = try ScheduleParser.parse(convert(nodes: nodes), defaultTableId: 42).get()
            XCTAssertEqual(parsed.nodesPerDay, 10_000)
            XCTAssertEqual(parsed.courses.count, 1)
            let course = try XCTUnwrap(parsed.courses.first)
            XCTAssertEqual(course.courseName, "边界课程")
            XCTAssertEqual(course.tableId, 42)
            XCTAssertEqual(course.startNode, 9_999)
            XCTAssertEqual(course.step, 2)
            XCTAssertEqual(course.day, 7)
            XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(parsed.timeJson).map(\.node), [10_000])
        }
    }

    func testMinimumBoundaryReallyParsesThrough() throws {
        let json = try convert(nodes: ["1"], detail: ["startNode": "1", "step": "1", "day": "1",
                                                     "startWeek": "1", "endWeek": "1"], slotNode: "1")
        let parsed = try ScheduleParser.parse(json, defaultTableId: 42).get()
        XCTAssertEqual(parsed.nodesPerDay, 1)
        XCTAssertEqual(parsed.courses.map(\.startNode), [1])
        XCTAssertEqual(parsed.courses.map(\.step), [1])
    }

    func testInvalidNodeValuesAreRejectedEquallyInScalarAndArrayForms() throws {
        let invalid: [Any] = [0, -1, 10_001, Int.max, Int.min, "9223372036854775808",
                              "10001", "invalid", true, 1.5, NSNull()]
        for value in invalid {
            for nodes in [value, [1, value]] as [Any] {
                XCTAssertThrowsError(try convert(nodes: nodes), "nodes=\(nodes)") {
                    XCTAssertEqual($0 as? WakeUpShareError, .incompleteSchedule)
                }
            }
        }
    }

    func testInvalidCourseSpansFailInConverterBeforeUnsafeParser() throws {
        let invalid: [[String: Any]] = [
            ["startNode": String(Int.max), "step": 2], ["startNode": Int.min],
            ["startNode": 1, "step": Int.max], ["startNode": 0], ["step": 0], ["step": -1],
            ["startNode": 10_000, "step": 2], ["startNode": 10_001, "step": 1],
            ["startNode": "9223372036854775808"], ["step": true], ["startNode": 1.5]
        ]
        // 故障版本只跑转换层断言，不能把溢出输入送进同进程 parser 造成 trap。
        for detail in invalid {
            XCTAssertThrowsError(try convert(detail: detail), "\(detail)") {
                XCTAssertEqual($0 as? WakeUpShareError, .incompleteSchedule)
            }
        }
    }

    func testExtremeCalendarAndSlotNumbersCannotEscapeConverter() throws {
        for field in ["day", "startWeek", "endWeek", "type"] {
            XCTAssertThrowsError(try convert(detail: [field: String(Int.max)])) {
                XCTAssertEqual($0 as? WakeUpShareError, .incompleteSchedule)
            }
        }
        XCTAssertThrowsError(try convert(ui: ["maxWeek": String(Int.max)])) {
            XCTAssertEqual($0 as? WakeUpShareError, .incompleteSchedule)
        }
        XCTAssertThrowsError(try convert(slotNode: Int.max)) {
            XCTAssertEqual($0 as? WakeUpShareError, .incompleteSchedule)
        }
    }
}
