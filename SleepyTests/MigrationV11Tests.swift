// MigrationV11Tests.swift — 原版本 MIGRATION_10_11 等价迁移测试 (GPL-3.0)
// 验证 v10 旧库升 v11: time_tables 加 reminderEnabled 列 (INTEGER NOT NULL DEFAULT 1),
// 老行读时值=1, 新行可显式写 0/1 且往返不丢。

import XCTest
import GRDB
@testable import Sleepy

final class MigrationV11Tests: XCTestCase {
    /// 建 v10 终态形状的 time_tables (列集 = v1~v10 累积), 预插一行老数据。
    private func makeV10Database() throws -> DatabaseQueue {
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
                t.column("periodTableId", .integer)
                t.column("preBindSnapshotJson", .text).notNull().defaults(to: "")
            }
            try db.execute(sql: "INSERT INTO time_tables (id, name, startDate, createdAt) VALUES (1, '老表', '2026-02-23', 1000)")
        }
        return queue
    }

    func testV11AddsReminderEnabledWithDefaultOn() throws {
        let queue = try makeV10Database()

        // 老行在 ALTER 后由列默认值回填 1
        var m = DatabaseMigrator()
        m.registerMigration("v11.addReminderEnabled") { db in
            try db.execute(
                sql: "ALTER TABLE time_tables ADD COLUMN reminderEnabled INTEGER NOT NULL DEFAULT 1")
        }
        try m.migrate(queue)

        try queue.read { db in
            let flags = try Int.fetchAll(db, sql: "SELECT reminderEnabled FROM time_tables")
            XCTAssertEqual([1], flags, "老行 reminderEnabled 默认 1 (原 DEFAULT 1 语义)")
        }
    }

    func testFullMigratorChainReachV11AndEntityRoundTrip() throws {
        let appdb = try AppDatabase.inMemory()
        try appdb.dbQueue.read { db in
            // PRAGMA table_info 多列, 直接取第一列=ciD 无意义, 用 pragma_table_info 取列名
            let cols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('time_tables')")
            XCTAssertTrue(cols.contains("reminderEnabled"), "全链路 v11 落地: \(cols)")
        }

        // 显式关提醒的新行可写 0 并往返
        var off = TimeTableEntity(name: "关提醒表", startDate: "2026-09-07")
        off.reminderEnabled = false
        let offId = try appdb.timeTableDao.insert(off)
        off.id = offId
        let readOff = try appdb.timeTableDao.getAll().first { $0.id == offId }
        XCTAssertEqual(false, readOff?.reminderEnabled)

        // 默认新行 = 开提醒 (原版本 Room defaultValue=1 同语义)
        var on = TimeTableEntity(name: "默认表", startDate: "2026-09-07")
        let onId = try appdb.timeTableDao.insert(on)
        on.id = onId
        let readOn = try appdb.timeTableDao.getAll().first { $0.id == onId }
        XCTAssertEqual(true, readOn?.reminderEnabled)
    }
}
