// TimeTableDao.swift — ← data/dao/TimeTableDao.kt 逐条 SQL 翻译 (GPL-3.0)

import Foundation
#if !WIDGET_EXT && !WATCH_APP
import GRDB

struct TimeTableDao {
    let db: DatabaseWriter

    // @Insert(onConflict = OnConflictStrategy.REPLACE)
    @discardableResult
    func insert(_ table: TimeTableEntity) throws -> Int64 {
        var table = table
        try db.write { try table.insert($0, onConflict: .replace) }
        return table.id
    }

    /// 事务内直插(JwImportViewModel.importAsNewTable 的 dbQueue.write 闭包里调用;
    /// 再走 db.write 会 reentrant fatal — GRDB SerializedDatabase 禁止重入)
    @discardableResult
    func insertInDb(_ dbw: Database, _ table: TimeTableEntity) throws -> Int64 {
        var table = table
        try table.insert(dbw, onConflict: .replace)
        return table.id
    }

    /// 事务内批量直插 — 迁移 applyOverwrite/applyMerge 共用同一 db.write
    func insertAllInDb(_ dbw: Database, _ tables: [TimeTableEntity]) throws {
        for var t in tables {
            try t.insert(dbw, onConflict: .replace)
        }
    }

    /// 事务内直删全表 — 迁移 applyOverwrite 共用同一 db.write
    func deleteAllInDb(_ dbw: Database) throws {
        try dbw.execute(sql: "DELETE FROM time_tables")
    }

    func setDefaultInDb(_ dbw: Database, _ id: Int64) throws {
        try dbw.execute(sql: "UPDATE time_tables SET isDefault = (id = ?)", arguments: [id])
    }

    // @Query("UPDATE time_tables SET reminderEnabled = :enabled WHERE id = :id") — ← 原版本 TimeTableDao.setReminderEnabled
    func setReminderEnabledInDb(_ dbw: Database, _ id: Int64, _ enabled: Bool) throws -> Int {
        try dbw.execute(sql: "UPDATE time_tables SET reminderEnabled = ? WHERE id = ?", arguments: [enabled, id])
        return dbw.changesCount
    }

    // @Update
    func update(_ table: TimeTableEntity) throws {
        var table = table
        try db.write { try table.update($0) }
    }

    // DELETE FROM time_tables WHERE id = :id
    func deleteById(_ id: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM time_tables WHERE id = ?", arguments: [id]) }
    }

    // SELECT * FROM time_tables WHERE id = :id LIMIT 1
    func getById(_ id: Int64) throws -> TimeTableEntity? {
        try db.read { try TimeTableEntity.fetchOne($0, sql: "SELECT * FROM time_tables WHERE id = ? LIMIT 1", arguments: [id]) }
    }

    // SELECT * FROM time_tables WHERE id = :id LIMIT 1 (Flow<TimeTableEntity?>)
    // Room Flow → GRDB ValueObservation;供 Repository 层 observeTable /
    // observeEffectivePeriodTable (设计 §5.2 立即全部同步的反应式源) 使用。
    func observeById(_ id: Int64) -> DatabasePublishers.Value<TimeTableEntity?> {
        ValueObservation
            .tracking { db in
                try TimeTableEntity.fetchOne(db, sql: "SELECT * FROM time_tables WHERE id = ? LIMIT 1", arguments: [id])
            }
            .publisher(in: db)
    }

    // SELECT * FROM time_tables ORDER BY createdAt DESC
    // (observeAll/getAll 共用;Flow 语义 → ValueObservation 在 Repository 层)
    func getAll() throws -> [TimeTableEntity] {
        try db.read { try TimeTableEntity.fetchAll($0, sql: "SELECT * FROM time_tables ORDER BY createdAt DESC") }
    }

    // SELECT COUNT(*) FROM time_tables
    func count() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM time_tables") ?? 0 }
    }

    // UPDATE time_tables SET isDefault = (id = :id)
    func setDefault(_ id: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE time_tables SET isDefault = (id = ?)", arguments: [id]) }
    }

    // SELECT * FROM time_tables WHERE isDefault = 1 LIMIT 1
    func getDefault() throws -> TimeTableEntity? {
        try db.read { try TimeTableEntity.fetchOne($0, sql: "SELECT * FROM time_tables WHERE isDefault = 1 LIMIT 1") }
    }

    // SELECT * FROM time_tables WHERE periodTableId = :periodTableId ORDER BY createdAt DESC
    // 甲案 (设计 §4.1): 绑定到指定作息表的全部课表 — 弹窗"另有 N 张课表绑定"提示 +
    // 三选项作用域语义共用 (ScheduleRepository.getTablesBoundTo /
    // repoTablesBoundToCount, EditTableScreen.kt:343/404)。
    func getAllBoundTo(_ periodTableId: Int64) throws -> [TimeTableEntity] {
        try db.read {
            try TimeTableEntity.fetchAll($0, sql: "SELECT * FROM time_tables WHERE periodTableId = ? ORDER BY createdAt DESC", arguments: [periodTableId])
        }
    }
}
#else
struct TimeTableDao {
    let db: LiteDatabase

    private static let selectColumns = """
        id, name, startDate, maxWeek, nodesPerDay, timeJson, color, isDefault, \
        smartConfigJson, createdAt, periodTableId, preBindSnapshotJson, reminderEnabled, \
        reminderOverride, importSourceJson, jwSchoolSourceJson, jwSchoolSourceVerified
        """

    private static func mapRow(_ s: LiteStatement) -> TimeTableEntity {
        TimeTableEntity(
            name: s.colString(1),
            startDate: s.colString(2),
            maxWeek: s.colInt(3),
            nodesPerDay: s.colInt(4),
            timeJson: s.colString(5),
            color: s.colString(6),
            isDefault: s.colBool(7),
            smartConfigJson: s.colString(8),
            createdAt: s.colInt64(9),
            periodTableId: s.colOptInt64(10),
            preBindSnapshotJson: s.colString(11),
            reminderEnabled: s.colBool(12),
            reminderOverride: s.colOptBool(13),
            importSourceJson: s.colString(14),
            jwSchoolSourceJson: s.colString(15),
            jwSchoolSourceVerified: s.colBool(16),
            id: s.colInt64(0)
        )
    }

    func getById(_ id: Int64) throws -> TimeTableEntity? {
        try db.read { conn in
            try conn.fetchOne(
                "SELECT \(Self.selectColumns) FROM time_tables WHERE id = ? LIMIT 1",
                arguments: [.int64(id)],
                map: Self.mapRow
            )
        }
    }

    func getAll() throws -> [TimeTableEntity] {
        try db.read { conn in
            try conn.fetchAll(
                "SELECT \(Self.selectColumns) FROM time_tables ORDER BY createdAt DESC",
                map: Self.mapRow
            )
        }
    }

    func count() throws -> Int {
        try db.read { conn in
            try conn.fetchOne("SELECT COUNT(*) FROM time_tables") { $0.colInt(0) } ?? 0
        }
    }

    func getDefault() throws -> TimeTableEntity? {
        try db.read { conn in
            try conn.fetchOne(
                "SELECT \(Self.selectColumns) FROM time_tables WHERE isDefault = 1 LIMIT 1",
                map: Self.mapRow
            )
        }
    }

    func getAllBoundTo(_ periodTableId: Int64) throws -> [TimeTableEntity] {
        try db.read { conn in
            try conn.fetchAll(
                "SELECT \(Self.selectColumns) FROM time_tables WHERE periodTableId = ? ORDER BY createdAt DESC",
                arguments: [.int64(periodTableId)],
                map: Self.mapRow
            )
        }
    }

    @discardableResult
    func insertInDb(_ conn: LiteDatabase.Connection, _ t: TimeTableEntity) throws -> Int64 {
        try conn.execute("""
            INSERT OR REPLACE INTO time_tables (
                id, name, startDate, maxWeek, nodesPerDay, timeJson, color, isDefault,
                smartConfigJson, createdAt, periodTableId, preBindSnapshotJson,
                reminderEnabled, reminderOverride, importSourceJson, jwSchoolSourceJson,
                jwSchoolSourceVerified
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                t.id == 0 ? .null : .int64(t.id),
                .text(t.name),
                .text(t.startDate),
                .int(t.maxWeek),
                .int(t.nodesPerDay),
                .text(t.timeJson),
                .text(t.color),
                .bool(t.isDefault),
                .text(t.smartConfigJson),
                .int64(t.createdAt),
                t.periodTableId.map(LiteBindValue.int64) ?? .null,
                .text(t.preBindSnapshotJson),
                .bool(t.reminderEnabled),
                t.reminderOverride.map(LiteBindValue.bool) ?? .null,
                .text(t.importSourceJson),
                .text(t.jwSchoolSourceJson),
                .bool(t.jwSchoolSourceVerified)
            ]
        )
        return t.id == 0 ? conn.lastInsertRowId : t.id
    }
}
#endif
