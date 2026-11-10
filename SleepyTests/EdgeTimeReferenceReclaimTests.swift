import XCTest
@testable import Sleepy

final class EdgeTimeReferenceReclaimTests: XCTestCase {
    private func checkTimeSpanKeepsEveryEdge(legacyOwnTime: Bool) throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let base = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
        var json = TimeTableUtils.insertEdgeNode(timeJson: base, edgeClass: .after, start: "10:00", end: "10:45")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "11:00", end: "11:45")
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 1, timeJson: json))
        let tableID = try repo.insertTable(TimeTableEntity(name: "主表", startDate: "2026-11-02", nodesPerDay: 1, timeJson: base))
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        var timed = CourseEntity(groupId: "timed", tableId: tableID, courseName: "自定义时间课", day: 1,
                                  startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "")
        timed.ownTime = legacyOwnTime
        timed.isIrregularTime = !legacyOwnTime
        timed.startTime = "10:00"
        timed.endTime = "11:45"
        let normalized = timed.normalizeNode(timeJson: json)
        XCTAssertEqual(normalized.startNode, 2)
        XCTAssertEqual(normalized.step, 2)
        try repo.insertCourse(timed)
        let disposable = try repo.insertCourse(CourseEntity(groupId: "remove", tableId: tableID, courseName: "删除触发回收", day: 2,
                                                             startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: ""))
        try repo.deleteCourse(disposable)
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, json,
                       "Both normalized edge nodes remain referenced even when stored step is stale")
        XCTAssertEqual(try repo.getTable(tableID)?.timeJson, base)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.courseName), [timed.courseName])
    }

    func testLegacyOwnTimeKeepsEveryMappedEdgeNode() throws {
        try checkTimeSpanKeepsEveryEdge(legacyOwnTime: true)
    }

    func testIrregularTimeKeepsEveryMappedEdgeNode() throws {
        try checkTimeSpanKeepsEveryEdge(legacyOwnTime: false)
    }
}
