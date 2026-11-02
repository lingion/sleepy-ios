// NewTableImportTests.swift — ← data/repository/NewTableImportTest.kt (v1.0.62 B7b)
// 导入新建课表原子编排五例:
//   1. 撤回快照先于首写(私有/共享两路)
//   2. 任一写段注入失败 → 整笔回滚, 三表与默认表原样
//   3. 显式绑定不复制不覆盖共享作息表
//   4. 确认行私有作息表 + keepGroups 两档分组口径
//   5. 悬空绑定在任何写之前失败
// Android 用 jdbc:sqlite::memory: 假仓库; iOS 用 AppDatabase.inMemory() 真库 +
// 失败注入代理(事务语义由 GRDB dbQueue.write 真实承担)。

import XCTest
import GRDB
@testable import Sleepy

final class NewTableImportTests: XCTestCase {

    private enum FailStage {
        case period, table, courses, `default`
    }

    /// 失败注入代理 — 每个写方法先透传真库再抛错(= Android SqlStore 的写后注入),
    /// captureUndo 记旗; insertPeriod/insertTable 前置断言快照已拍(= Android check(captured))。
    private final class FailingImportStore: NewTableImportStore {
        let base: GRDBNewTableImportStore
        let failAt: FailStage?
        private(set) var captured = false
        private(set) var orderingViolations: [String] = []

        init(db: AppDatabase, failAt: FailStage?) {
            self.base = GRDBNewTableImportStore(db: db)
            self.failAt = failAt
        }

        private struct InjectedFailure: Error {}

        func atomic(_ block: (Database) throws -> Int64) throws -> Int64 {
            try base.atomic(block)
        }

        func periodExists(_ id: Int64, in dbw: Database) throws -> Bool {
            try base.periodExists(id, in: dbw)
        }

        func captureUndo(in dbw: Database) throws {
            captured = true
            try base.captureUndo(in: dbw)
        }

        func insertPeriod(_ period: PeriodTableEntity, in dbw: Database) throws -> Int64 {
            if !captured { orderingViolations.append("period") }
            let id = try base.insertPeriod(period, in: dbw)
            if failAt == .period { throw InjectedFailure() }
            return id
        }

        func insertTable(_ table: TimeTableEntity, in dbw: Database) throws -> Int64 {
            if !captured { orderingViolations.append("table") }
            let id = try base.insertTable(table, in: dbw)
            if failAt == .table { throw InjectedFailure() }
            return id
        }

        func insertCourses(_ courses: [CourseEntity], in dbw: Database) throws {
            if !captured { orderingViolations.append("courses") }
            try base.insertCourses(courses, in: dbw)
            if failAt == .courses { throw InjectedFailure() }
        }

        func setDefault(_ id: Int64, in dbw: Database) throws {
            if !captured { orderingViolations.append("default") }
            try base.setDefault(id, in: dbw)
            if failAt == .default { throw InjectedFailure() }
        }

        func knownNameRoster(in dbw: Database) throws -> [String: String] {
            try base.knownNameRoster(in: dbw)
        }

        func persistNewGroupColors(_ courses: [CourseEntity], in dbw: Database) throws {
            try base.persistNewGroupColors(courses, in: dbw)
        }
    }

    private var db: AppDatabase!

    override func setUp() {
        super.setUp()
        db = try! AppDatabase.inMemory()
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    // ← Android SqlStore 种子: periods(7,'original') / tables(1,period=7,selected) / courses(1,table=1,'old')
    private func seed() throws {
        var period = PeriodTableEntity(name: "original", timeJson: "original")
        period.id = 7
        try db.dbQueue.write { try period.insert($0, onConflict: .replace) }
        var table = TimeTableEntity(name: "old", startDate: "2026-09-07")
        table.id = 1
        table.periodTableId = 7
        table.isDefault = true
        try db.dbQueue.write { try table.insert($0, onConflict: .replace) }
        var course = CourseEntity(groupId: "old", tableId: 1, courseName: "旧课",
                                  day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 20,
                                  color: "#123456")
        course.id = 1
        try db.dbQueue.write { try course.insert($0, onConflict: .replace) }
    }

    private func course(_ group: String) -> CourseEntity {
        // ← Android course(group): 同名双行 — 认亲/keepGroups 口径的输入形状
        CourseEntity(groupId: group, tableId: 1, courseName: " Same  Name ",
                     day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 20, color: "#123456")
    }

    @discardableResult
    private func apply(store: NewTableImportStore,
                       binding: Int64? = nil,
                       keep: Bool = false) throws -> Int64 {
        try importNewTableAtomically(store: store,
                                     table: TimeTableEntity(name: "new", startDate: "2026-09-07"),
                                     courses: [course("a"), course("b")],
                                     period: PeriodTableEntity(name: "new", timeJson: "confirmed"),
                                     bindingId: binding,
                                     keepGroups: keep)
    }

    private func scalarCount(_ sql: String) throws -> Int {
        try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: sql) ?? -1
        }
    }

    // ───────── 1. captureRunsBeforeFirstWriteForPrivateAndSharedSchedules ─────────

    func testCaptureRunsBeforeFirstWriteForPrivateAndSharedSchedules() throws {
        try seed()
        let bindings: [Int64?] = [nil, 7]
        for binding in bindings {
            let store = FailingImportStore(db: db, failAt: nil)
            _ = try apply(store: store, binding: binding)
            XCTAssertTrue(store.captured)
            XCTAssertTrue(store.orderingViolations.isEmpty,
                          "undo must precede the first write: \(store.orderingViolations)")
        }
    }

    // ───────── 2. rollbackAfterEveryWritePreservesAllTablesAndDefault ─────────

    func testRollbackAfterEveryWritePreservesAllTablesAndDefault() throws {
        try seed()
        for stage in [FailStage.period, .table, .courses, .default] {
            let store = FailingImportStore(db: db, failAt: stage)
            XCTAssertThrowsError(try apply(store: store), "Expected failure at \(stage)")
            XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM period_tables"))
            XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM time_tables"))
            XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM courses"))
            XCTAssertEqual(1, try scalarCount("SELECT id FROM time_tables WHERE isDefault = 1"))
        }
    }

    // ───────── 3. explicitBindingIsNotCopiedOrOverwritten ─────────

    func testExplicitBindingIsNotCopiedOrOverwritten() throws {
        try seed()
        let store = FailingImportStore(db: db, failAt: nil)
        let id = try apply(store: store, binding: 7)
        XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM period_tables"))
        let boundTime = try db.dbQueue.read {
            try String.fetchOne($0, sql: "SELECT timeJson FROM period_tables WHERE id = 7")
        }
        XCTAssertEqual("original", boundTime)
        let boundId = try db.dbQueue.read {
            try Int64.fetchOne($0, sql: "SELECT periodTableId FROM time_tables WHERE id = \(id)")
        }
        XCTAssertEqual(7, boundId)
        let defId = try db.dbQueue.read {
            try Int64.fetchOne($0, sql: "SELECT id FROM time_tables WHERE isDefault = 1")
        }
        XCTAssertEqual(id, defId)
    }

    // ───────── 4. confirmedPrivateScheduleAndGroupPolicyArePreserved ─────────

    func testConfirmedPrivateScheduleAndGroupPolicyArePreserved() throws {
        for keep in [false, true] {
            // 每档独立库 — Android 同名用例的 for 循环共用一个干净 SqlStore
            let fresh = try AppDatabase.inMemory()
            let id = try importNewTableAtomically(store: GRDBNewTableImportStore(db: fresh),
                                                  table: TimeTableEntity(name: "new", startDate: "2026-09-07"),
                                                  courses: [course("a"), course("b")],
                                                  period: PeriodTableEntity(name: "new", timeJson: "confirmed"),
                                                  bindingId: nil,
                                                  keepGroups: keep)
            let periodTime = try fresh.dbQueue.read {
                try String.fetchOne($0, sql: "SELECT timeJson FROM period_tables WHERE id = (SELECT periodTableId FROM time_tables WHERE id = \(id))")
            }
            XCTAssertEqual("confirmed", periodTime)
            let distinctGroups = try fresh.dbQueue.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT groupId) FROM courses WHERE tableId = \(id)")
            }
            XCTAssertEqual(keep ? 2 : 1, distinctGroups)
        }
    }

    // ───────── 5. deletedExplicitBindingFailsBeforeAnyWrite ─────────

    func testDeletedExplicitBindingFailsBeforeAnyWrite() throws {
        try seed()
        let store = FailingImportStore(db: db, failAt: nil)
        XCTAssertThrowsError(try apply(store: store, binding: 99), "Missing binding must fail")
        XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM period_tables"))
        XCTAssertEqual(1, try scalarCount("SELECT COUNT(*) FROM time_tables"))
    }

    // ───────── 6. 仓库接线: importNewTable 走同一原子编排并触发 onDataChanged ─────────

    func testRepositoryImportNewTableCommitsAtomicallyAndNotifies() throws {
        try seed()
        var notified = 0
        let repo = ScheduleRepository(db)
        repo.onDataChangedHook = { notified += 1 }
        let id = try repo.importNewTable(
            table: TimeTableEntity(name: "repo-new", startDate: "2026-09-07"),
            courses: [course("a")],
            periodTable: PeriodTableEntity(name: "repo-period", timeJson: "confirmed"),
            bindPeriodTableId: nil,
            keepGroups: false)
        XCTAssertEqual(1, notified)
        let table = try repo.getTable(id)
        XCTAssertNotNil(table)
        XCTAssertEqual(true, table?.isDefault)
        XCTAssertEqual(2, try scalarCount("SELECT COUNT(*) FROM period_tables"))
        // 悬空绑定 → 抛错且不通知
        XCTAssertThrowsError(try repo.importNewTable(
            table: TimeTableEntity(name: "x", startDate: "2026-09-07"),
            courses: [], periodTable: nil, bindPeriodTableId: 404))
        XCTAssertEqual(1, notified)
    }
}
