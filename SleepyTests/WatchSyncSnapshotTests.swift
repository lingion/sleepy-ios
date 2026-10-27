// WatchSyncSnapshotTests.swift — sleepy-watch-sync-v1 契约单测 (2026-10 watch 伴侣 App)
// 锁三件事: encode/decode 逐字段往返 (id/绑定/reminderEnabled 不丢)、
// apply 全量重建显式 id 直插 (幂等重放)、旧载荷 (非 v1/缺 format) 拒收。

import XCTest
@testable import Sleepy

final class WatchSyncSnapshotTests: XCTestCase {

    private func makeFixtureBody() -> WatchSyncSnapshot.Body {
        var body = WatchSyncSnapshot.Body()
        body.sentAt = 1_730_000_000_000
        body.periodTables = [
            PeriodTableEntity(name: "标准作息", nodesPerDay: 12,
                              timeJson: TimeTableUtils.DEFAULT_TIME_JSON)
        ]
        body.periodTables[0].id = 7
        body.timeTables = [
            TimeTableEntity(name: "2026春", startDate: "2026-03-02", maxWeek: 20,
                            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                            isDefault: true)
        ]
        body.timeTables[0].id = 3
        body.timeTables[0].periodTableId = 7
        body.timeTables[0].reminderEnabled = false
        var c1 = CourseEntity(groupId: "g1", tableId: 3, courseName: "高等数学",
                              day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16,
                              color: "#FF6750A4")
        c1.id = 101
        c1.alias = "高数"
        var c2 = CourseEntity(groupId: "g2", tableId: 3, courseName: "大学英语",
                              day: 1, startNode: 3, step: 2, startWeek: 1, endWeek: 8,
                              color: "#FF6750A4")
        c2.id = 102
        body.courses = [c1, c2]
        body.prefs = .init(reminderMaster: true, beforeClassEnabled: true,
                           beforeClassMinutes: 15)
        return body
    }

    func testRoundTripKeepsIdsAndBindings() throws {
        let body = makeFixtureBody()
        let ctx = WatchSyncSnapshot.encodeToApplicationContext(body)
        XCTAssertEqual(ctx["format"] as? String, WatchSyncSnapshot.FORMAT)
        let decoded = try XCTUnwrap(WatchSyncSnapshot.decode(from: ctx))
        XCTAssertEqual(decoded.sentAt, body.sentAt)
        XCTAssertEqual(decoded.timeTables.first?.id, 3)
        XCTAssertEqual(decoded.timeTables.first?.periodTableId, 7)
        XCTAssertEqual(decoded.timeTables.first?.reminderEnabled, false)
        XCTAssertEqual(decoded.periodTables.first?.id, 7)
        XCTAssertEqual(decoded.courses.map(\.id), [101, 102])
        XCTAssertEqual(decoded.courses.first?.alias, "高数")
        XCTAssertEqual(decoded.prefs?.beforeClassMinutes, 15)
    }

    func testDecodeRejectsForeignFormats() {
        // 旧文本形态键 / 缺 format / 坏 JSON
        XCTAssertNil(WatchSyncSnapshot.decode(from: ["format": WatchSyncSnapshot.FORMAT]))
        XCTAssertNil(WatchSyncSnapshot.decode(from: ["tables": ["#sleepy-v1"]]))
        XCTAssertNil(WatchSyncSnapshot.decode(from: ["format": "other", "sync": [:]]))
        XCTAssertNil(WatchSyncSnapshot.decode(from: ["format": WatchSyncSnapshot.FORMAT,
                                                     "sync": ["version": 99]]))
    }

    func testApplyRebuildsMirrorWithExplicitIds() throws {
        let db = try AppDatabase.inMemory()
        let body = makeFixtureBody()
        try WatchSyncSnapshot.apply(db: db, body: body)

        let repo = ScheduleRepository(db)
        let tables = try repo.getAllTables()
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].id, 3)
        XCTAssertEqual(tables[0].reminderEnabled, false)
        XCTAssertEqual(try repo.getAllCourses().map(\.id).sorted(), [101, 102])
        XCTAssertEqual(try XCTUnwrap(repo.getPeriodTable(7)).name, "标准作息")
        // 水合链完整: 绑定可解
        let bound = try XCTUnwrap(repo.effectivePeriodTable(tableId: 3))
        XCTAssertEqual(bound.id, 7)
    }

    func testApplyIsIdempotentFullReplace() throws {
        let db = try AppDatabase.inMemory()
        try WatchSyncSnapshot.apply(db: db, body: makeFixtureBody())
        // 重放同载荷 = 内容不变
        try WatchSyncSnapshot.apply(db: db, body: makeFixtureBody())
        let repo = ScheduleRepository(db)
        XCTAssertEqual(try repo.getAllCourses().count, 2)
        // 新载荷删表 = 镜像跟删 (无残留行)
        var emptied = makeFixtureBody()
        emptied.timeTables = []
        emptied.courses = []
        try WatchSyncSnapshot.apply(db: db, body: emptied)
        XCTAssertEqual(try repo.getAllCourses().count, 0)
        XCTAssertEqual(try repo.getAllTables().count, 0)
    }

    func testApplyFailureRollsBackKeepingPreviousMirror() throws {
        let db = try AppDatabase.inMemory()
        let good = makeFixtureBody()
        try WatchSyncSnapshot.apply(db: db, body: good)
        // 坏载荷: 课程指向不存在的表 (FK 违例) → 事务整体回滚, 旧镜像原样
        var broken = good
        broken.timeTables = []
        broken.courses = good.courses  // 101/102 引用 tableId=3 但表已不在
        XCTAssertThrowsError(try WatchSyncSnapshot.apply(db: db, body: broken))
        let repo = ScheduleRepository(db)
        XCTAssertEqual(try repo.getAllCourses().map(\.id).sorted(), [101, 102])
        XCTAssertEqual(try repo.getAllTables().count, 1)
    }
}
