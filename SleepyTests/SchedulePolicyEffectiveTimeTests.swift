import XCTest
@testable import Sleepy

final class SchedulePolicyEffectiveTimeTests: XCTestCase {
    private func checkEffectiveTimeMapping(_ policy: SchedulePolicy) throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let compatibility = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
        let effective = #"[{"node":1,"start":"10:00","end":"10:45"}]"#
        let changed = #"[{"node":1,"start":"09:00","end":"09:45"},{"node":2,"start":"10:00","end":"10:45"}]"#
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "实际作息", nodesPerDay: 1, timeJson: effective))
        let tableID = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-11-02", nodesPerDay: 1, timeJson: compatibility))
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        try repo.insertCourse(CourseEntity(groupId: "g", tableId: tableID, courseName: "十点的课", day: 1,
                                           startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: ""))
        var edited = try XCTUnwrap(repo.getTable(tableID))
        edited.timeJson = changed
        edited.nodesPerDay = 2
        var draft = try XCTUnwrap(repo.getPeriodTable(periodID))
        draft.timeJson = changed
        draft.nodesPerDay = 2
        try repo.executeScheduleEditPolicy(editedTable: edited, draft: draft, policy: policy)
        XCTAssertEqual(try repo.getCourses(tableID).first?.startNode, 2,
                       "The old course time comes from its bound schedule, not the dormant 08:00 compatibility column")
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, effective)
    }

    func testDetachRemapsFromActualBoundSchedule() throws {
        try checkEffectiveTimeMapping(.detachCopy)
    }

    func testCreateNewRemapsFromActualBoundSchedule() throws {
        try checkEffectiveTimeMapping(.createNew)
    }
}
