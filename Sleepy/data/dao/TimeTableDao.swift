// TimeTableDao.swift — ← data/dao/TimeTableDao.kt 逐条 SQL 翻译 (GPL-3.0)

import Foundation
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
}
