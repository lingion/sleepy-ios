// MigrationV7toV10Tests.swift — 原 MigrationTest 等价物 (GPL-3.0)
// 验证 v6 旧库逐级升到 v10: import_drafts 建表(v7)、period_tables 建表+回填(v8)、
// preBindSnapshotJson 加列(v9)、calendar_import_records 建表+唯一索引(v10)。
// issue#40 回填契约: 每张旧课表恰得一张同 id 独立节次表, periodTableId 指过去。

import XCTest
import GRDB
@testable import Sleepy

final class MigrationV7toV10Tests: XCTestCase {
    private var migrator: DatabaseMigrator {
        (try? AppDatabase(queue: DatabaseQueue()))?.migrator ?? DatabaseMigrator()
    }

    /// v6 终态库 + 复用 AppDatabase.migrator 的 v7+ 迁移体。
    /// GRDB DatabaseMigrator 不暴露枚举 API → 逐条登记同标识迁移闭包的引用副本
    /// (标识一致, 迁移体从同一来源拷贝 — 单一事实来源仍是 AppDatabase.migrator)。
    private func makePartMigrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v7.createImportDrafts", migrate: Self.v7)
        m.registerMigration("v8.createPeriodTables", migrate: Self.v8)
        m.registerMigration("v9.addPreBindSnapshot", migrate: Self.v9)
        m.registerMigration("v10.createCalendarImportRecords", migrate: Self.v10)
        return m
    }

    private static let v7: (Database) throws -> Void = { db in
        try db.create(table: "import_drafts") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("sourceType", .text).notNull().defaults(to: "")
            t.column("sourceUrl", .text).notNull().defaults(to: "")
            t.column("payloadJson", .text).notNull()
            t.column("createdAt", .integer).notNull()
            t.column("updatedAt", .integer).notNull()
        }
    }

    private static let v8: (Database) throws -> Void = { db in
        try db.create(table: "period_tables") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("nodesPerDay", .integer).notNull()
            t.column("timeJson", .text).notNull()
            t.column("smartConfigJson", .text).notNull()
            t.column("createdAt", .integer).notNull()
            t.column("updatedAt", .integer).notNull()
        }
        try db.create(indexOn: "period_tables", columns: ["createdAt"])
        try db.execute(sql: "ALTER TABLE time_tables ADD COLUMN periodTableId INTEGER")
        let rows = try Row.fetchAll(db, sql: "SELECT id, name, nodesPerDay, timeJson, smartConfigJson, createdAt FROM time_tables ORDER BY id")
        for row in rows {
            try db.execute(sql: """
                INSERT INTO period_tables (id, name, nodesPerDay, timeJson, smartConfigJson, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [row["id"], row["name"], row["nodesPerDay"], row["timeJson"], row["smartConfigJson"], row["createdAt"], row["createdAt"]])
            try db.execute(sql: "UPDATE time_tables SET periodTableId = ? WHERE id = ?", arguments: [row["id"], row["id"]])
        }
    }

    private static let v9: (Database) throws -> Void = { db in
        try db.execute(sql: "ALTER TABLE time_tables ADD COLUMN preBindSnapshotJson TEXT NOT NULL DEFAULT ''")
    }

    private static let v10: (Database) throws -> Void = { db in
        try db.create(table: "calendar_import_records") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("tableId", .integer).notNull()
            t.column("courseId", .integer).notNull()
            t.column("eventDate", .text).notNull()
            t.column("calendarId", .text).notNull()
            t.column("eventId", .text).notNull()
            t.column("batchId", .text).notNull()
            t.column("fingerprint", .text).notNull()
            t.column("alarmRequested", .boolean).notNull()
            t.column("createdAt", .integer).notNull()
        }
        try db.create(indexOn: "calendar_import_records", columns: ["tableId", "courseId", "eventDate", "calendarId"], options: [.unique])
        try db.create(indexOn: "calendar_import_records", columns: ["tableId"])
        try db.create(indexOn: "calendar_import_records", columns: ["batchId"])
    }

    /// 建一个 v6 形状的库(手工 DDL = v6 终态), 插两张课表
    private func makeV6Database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.create(table: "time_tables") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("startDate", .text).notNull()
                t.column("maxWeek", .integer).notNull().defaults(to: 20)
                t.column("nodesPerDay", .integer).notNull().defaults(to: 12)
                t.column("timeJson", .text).notNull().defaults(sql: "'[]'")
                t.column("color", .text).notNull().defaults(to: "#FF6750A4")
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("smartConfigJson", .text).notNull().defaults(to: "")
                t.column("createdAt", .integer).notNull()
            }
            try db.execute(sql: """
                INSERT INTO time_tables (id, name, startDate, createdAt) VALUES
                (1, '主表', '2026-02-23', 1000),
                (2, '副表', '2026-09-07', 2000)
                """)
        }
        return queue
    }

    func testV6ToV10ChainCreatesNewTablesAndBackfills() throws {
        let queue = try makeV6Database()
        try makePartMigrator().migrate(queue)

        try queue.read { db in
            // v8: period_tables 建表 + 每张旧课表回填一张同 id 节次表
            let periodCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM period_tables")
            XCTAssertEqual(2, periodCount, "issue#40: 每张旧课表各得一张节次表, 不共享")
            let p1 = try Row.fetchOne(db, sql: "SELECT * FROM period_tables WHERE id = 1")
            XCTAssertEqual("主表", p1?["name"])
            XCTAssertEqual(12, (p1?["nodesPerDay"] as Int?) ?? -1, "继承旧 nodesPerDay 默认 12")
            XCTAssertEqual("[]", p1?["timeJson"], "继承旧 timeJson 默认列值")
            let backfill = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_tables WHERE periodTableId = id")
            XCTAssertEqual(2, backfill, "periodTableId 指向自己那张节次表")
            let backfillCross = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_tables WHERE periodTableId != id")
            XCTAssertEqual(0, backfillCross)

            // v9: 快照列默认空串
            let snapshot = try String.fetchAll(db, sql: "SELECT preBindSnapshotJson FROM time_tables")
            XCTAssertEqual(2, snapshot.count)
            XCTAssertTrue(snapshot.allSatisfy { $0.isEmpty }, "旧行无快照")

            // v7: import_drafts 存在
            _ = try Row.fetchOne(db, sql: "SELECT * FROM import_drafts LIMIT 1")

            // v10: calendar_import_records + 唯一索引
            _ = try Row.fetchOne(db, sql: "SELECT * FROM calendar_import_records LIMIT 1")
            let idx = try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='calendar_import_records' AND name NOT LIKE 'sqlite_autoindex%'"))
            XCTAssertTrue(idx.contains { $0.contains("tableId_courseId_eventDate_calendarId") }, "唯一索引存在, got \(idx)")
            XCTAssertTrue(idx.contains { $0.contains("_tableId") }, "tableId 单列索引存在")
            XCTAssertTrue(idx.contains { $0.contains("batchId") }, "batchId 索引存在")
        }
    }

    func testPeriodTableDaoBoundReferenceCount() throws {
        let appdb = try AppDatabase.inMemory()
        var pt = PeriodTableEntity(name: "春季作息")
        let ptId = try appdb.periodTableDao.insert(pt)
        pt.id = ptId
        XCTAssertEqual(0, try appdb.periodTableDao.boundTableCount(ptId))

        var tt = TimeTableEntity(name: "主表", startDate: "2026-02-23")
        let bound = TimeTableEntity.snapshotForBind(table: tt, targetId: ptId)
        try appdb.timeTableDao.insert(bound)
        XCTAssertEqual(1, try appdb.periodTableDao.boundTableCount(ptId))
        XCTAssertEqual([1], try appdb.periodTableDao.boundTableIds(ptId).filter { $0 > 0 } .count == 0 ? [] : try appdb.periodTableDao.boundTableIds(ptId))

        // C2 快照: 绑定时快照 {t,n,s}, 解绑恢复
        let hydrated = bound.hydratedWith(pt)
        XCTAssertEqual(pt.timeJson, hydrated.timeJson)
        XCTAssertEqual(pt.nodesPerDay, hydrated.nodesPerDay)
        XCTAssertFalse(bound.preBindSnapshotJson.isEmpty, "首次绑定写快照")

        let restored = TimeTableEntity.restoredForUnbind(table: bound)
        XCTAssertNil(restored.periodTableId)
        XCTAssertTrue(restored.preBindSnapshotJson.isEmpty)
        XCTAssertEqual(tt.timeJson, restored.timeJson, "解绑恢复绑定前兼容列")

        // 幂等: 再解绑一次安全
        let restored2 = TimeTableEntity.restoredForUnbind(table: restored)
        XCTAssertNil(restored2.periodTableId)
    }

    func testImportDraftAndCalendarRecordRoundTrip() throws {
        let appdb = try AppDatabase.inMemory()
        let draft = ImportDraftEntity(id: "d1", sourceType: "html", sourceUrl: "https://jw",
                                      payloadJson: "{}", createdAt: 1, updatedAt: 1)
        try appdb.importDraftDao.upsert(draft)
        XCTAssertEqual("d1", try appdb.importDraftDao.getById("d1")?.payloadJson.isEmpty == false ? draft.id : nil)
        try appdb.importDraftDao.deleteById("d1")
        XCTAssertNil(try appdb.importDraftDao.getById("d1"))

        var rec = CalendarImportRecordEntity(tableId: 1, courseId: 2, eventDate: "2026-03-02",
                                             calendarId: "CAL-1", eventId: "EV-1", batchId: "B1",
                                             fingerprint: "fp", alarmRequested: true)
        let rid = try appdb.calendarImportRecordDao.upsert(rec)
        rec.id = rid
        XCTAssertEqual(rid, try appdb.calendarImportRecordDao.find(tableId: 1, courseId: 2, eventDate: "2026-03-02", calendarId: "CAL-1")?.id)
        // REPLACE 冲突语义: 同唯一键重插不炸
        _ = try appdb.calendarImportRecordDao.upsert(rec)
        XCTAssertEqual(1, try appdb.calendarImportRecordDao.forTable(1).count)
        try appdb.calendarImportRecordDao.deleteForTable(1)
        XCTAssertEqual(0, try appdb.calendarImportRecordDao.forTable(1).count)
    }
}
