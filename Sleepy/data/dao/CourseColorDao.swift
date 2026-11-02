// CourseColorDao.swift — ← data/dao/CourseColorDao.kt (v1.0.62 B1)
// GRDB 复刻: course_colors 纯读（渲染） + 写（补色/重算）。
// 渲染路径只读；写仅发生在 ViewModel/导入层。

import Foundation
import GRDB

/// course_colors 纯读 DAO — 渲染层使用，写侧经 CourseColorWriteGlue。
struct CourseColorDao {
    let db: DatabaseWriter

    // INSERT OR REPLACE — 同批/重算落库, (tableKey, groupId) 覆盖。
    @discardableResult
    func upsertAll(_ rows: [CourseColorEntity]) throws -> [Int64] {
        try db.write { db in
            var ids: [Int64] = []
            for var row in rows {
                try row.insert(db, onConflict: .replace)
                ids.append(row.rowid ?? 0)
            }
            return ids
        }
    }

    /// 单课补色（导入新课/单课新增）— 幂等 REPLACE。
    @discardableResult
    func upsert(_ row: CourseColorEntity) throws -> Int64 {
        var r = row
        return try db.write { db in
            try r.insert(db, onConflict: .replace)
            return r.rowid ?? 0
        }
    }

    /// 渲染取色: groupId → hue 全量映射（课表页一次加载）。
    /// CLASSIC 档不走本函数 — CourseHueStore.refresh 在 CLASSIC 时直接返回空 map。
    func getHueMap(_ tableKey: String) throws -> [String: Float] {
        try db.read { db in
            var result: [String: Float] = [:]
            let rows = try Row.fetchAll(db,
                sql: "SELECT groupId, hue FROM course_colors WHERE tableKey = ?",
                arguments: [tableKey]
            )
            for row in rows {
                let gid: String = row["groupId"]
                let hue: Float = row["hue"]
                result[gid] = hue
            }
            return result
        }
    }

    /// 渲染兜底查单值: 查无返回 nil → 调用方按 safeArcHue 实时算。
    func getHue(_ tableKey: String, _ groupId: String) -> Float? {
        try? db.read { db in
            try Float.fetchOne(db,
                sql: "SELECT hue FROM course_colors WHERE tableKey = ? AND groupId = ?",
                arguments: [tableKey, groupId]
            )
        }
    }

    /// 课表删除时清理其全局配色行（与 courses 删除同事务，防孤儿行）。
    func clear(_ tableKey: String) throws {
        _ = try db.write { db in
            try CourseColorEntity.filter(Column("tableKey") == tableKey).deleteAll(db)
        }
    }
}
