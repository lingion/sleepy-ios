// CourseColorDao.swift — ← data/dao/CourseColorDao.kt (v1.0.62, GPL-3.0)
// Room @Dao interface → GRDB。SQL 文本与 Room 生成的语句语义一致。

import Foundation
import GRDB

struct CourseColorDao {
    let db: DatabaseWriter

    /// @Insert(onConflict = OnConflictStrategy.REPLACE) — 复合主键 upsert
    func upsertAll(_ rows: [CourseColorEntity]) throws {
        guard !rows.isEmpty else { return }
        try db.write { dbw in
            for var row in rows {
                try row.insert(dbw, onConflict: .replace)
            }
        }
    }

    func upsert(_ row: CourseColorEntity) throws {
        var r = row
        try db.write { try r.insert($0, onConflict: .replace) }
    }

    /// 事务内直写(join 既有事务) — Room 同事务内 @Insert 语义。
    /// 必须在调用方已持写事务时使用(否则 db.write 重入死锁)。
    func upsertAllInDb(_ dbw: Database, _ rows: [CourseColorEntity]) throws {
        guard !rows.isEmpty else { return }
        for var row in rows {
            try row.insert(dbw, onConflict: .replace)
        }
    }

    /// 事务内直读 — 避免在写事务里另开 db.read 造成死锁。
    func getHueMapInDb(_ dbw: Database, _ tableKey: String) throws -> [String: Float] {
        let rows = try Row.fetchAll(dbw, sql: """
            SELECT groupId, hue FROM course_colors WHERE tableKey = ?
            """, arguments: [tableKey])
        var map: [String: Float] = [:]
        map.reserveCapacity(rows.count)
        for var row in rows {
            let gid: String = row["groupId"]
            let hue: Float = row["hue"]
            map[gid] = hue
        }
        return map
    }

    /// @Query("SELECT groupId, hue FROM course_colors WHERE tableKey = :tableKey")
    func getHueMap(_ tableKey: String) throws -> [String: Float] {
        try db.read { dbw in
            let rows = try Row.fetchAll(dbw, sql: """
                SELECT groupId, hue FROM course_colors WHERE tableKey = ?
                """, arguments: [tableKey])
            var map: [String: Float] = [:]
            map.reserveCapacity(rows.count)
            for var row in rows {
                let gid: String = row["groupId"]
                let hue: Float = row["hue"]
                map[gid] = hue
            }
            return map
        }
    }

    /// @Query("SELECT hue FROM course_colors WHERE tableKey = :tableKey AND groupId = :groupId")
    func getHue(_ tableKey: String, _ groupId: String) throws -> Float? {
        try db.read { dbw in
            try Float.fetchOne(dbw, sql: """
                SELECT hue FROM course_colors WHERE tableKey = ? AND groupId = ?
                """, arguments: [tableKey, groupId])
        }
    }

    /// @Query("DELETE FROM course_colors WHERE tableKey = :tableKey")
    func clear(_ tableKey: String) throws {
        try db.write { dbw in
            try dbw.execute(sql: "DELETE FROM course_colors WHERE tableKey = ?", arguments: [tableKey])
        }
    }
}
