// CourseDao.swift — ← data/dao/CourseDao.kt 逐条 SQL 翻译 (GPL-3.0)
// Room @Dao interface → GRDB。suspend fun → async/await; Flow → AsyncStream(由 Repository 层桥接)。
// SQL 文本与 Room 生成的语句语义一致(列名/ORDER BY/冲突策略)。

import Foundation
import GRDB

struct CourseDao {
    let db: DatabaseWriter

    // @Insert(onConflict = OnConflictStrategy.REPLACE)
    @discardableResult
    func insert(_ course: CourseEntity) throws -> Int64 {
        var course = course
        try db.write { try course.insert($0, onConflict: .replace) }
        return course.id
    }

    /// 事务内直插(同 TimeTableDao.insertInDb 注释)
    func insertAllInDb(_ dbw: Database, _ courses: [CourseEntity]) throws -> [Int64] {
        var ids: [Int64] = []
        for var course in courses {
            try course.insert(dbw, onConflict: .replace)
            ids.append(course.id)
        }
        return ids
    }

    /// 事务内直插单条 — 迁移 applyMerge 共用同一 db.write, 走自增 ID。
    @discardableResult
    func insertInDb(_ dbw: Database, _ course: CourseEntity) throws -> Int64 {
        var c = course
        try c.insert(dbw, onConflict: .replace)
        return c.id
    }

    /// 事务内强制保留原 ID 插入 — 全量迁移包覆盖导入用(原版本 insertKeepId)。
    /// GRDB 的 MutablePersistableRecord.didInsert 会覆盖 id,所以这里改用底层 SQL
    /// INSERT OR REPLACE,SQLite 按提供的 id 落 rowid;这样 course.id 仍为入参值。
    func insertKeepIdInDb(_ dbw: Database, _ course: CourseEntity) throws {
        let columns = CourseEntity.databaseTableName
        // 与 GRDB 的 column order 一致(CourseEntity Codable 字段顺序即 columns),
        // 用 row.toArray() 避免遗漏 future 字段;但 row 是 struct,转 array 需要
        // 走 GRDB 的 PersistenceContainer;简化:用全列显式绑定
        try dbw.execute(
            sql: """
            INSERT OR REPLACE INTO courses
            (id, groupId, tableId, courseName, teacher, room, note, alias, day, startNode,
             step, startWeek, endWeek, type, color, colorMode, ownTime,
             isIrregularNode, isIrregularTime, startTime, endTime, credit, level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                course.id, course.groupId, course.tableId, course.courseName,
                course.teacher, course.room, course.note, course.alias, course.day,
                course.startNode, course.step, course.startWeek, course.endWeek,
                course.type, course.color, course.colorMode, course.ownTime,
                course.isIrregularNode, course.isIrregularTime,
                course.startTime, course.endTime, course.credit, course.level
            ]
        )
    }

    func insertAll(_ courses: [CourseEntity]) throws -> [Int64] {
        try db.write { db in
            var ids: [Int64] = []
            for var c in courses {
                try c.insert(db, onConflict: .replace); ids.append(c.id)
            }
            return ids
        }
    }

    // @Update
    func update(_ course: CourseEntity) throws {
        var course = course
        try db.write { try course.update($0) }
    }

    // @Update — issue#22 行级 diff/patch 用 — 批量 update, 保留各行 id
    func updateAll(_ courses: [CourseEntity]) throws {
        try db.write { db in
            for c in courses { try c.update(db) }
        }
    }

    // DELETE FROM courses WHERE id IN (:ids) — issue#22 行级 diff/patch 用
    func deleteByIds(_ ids: [Int64]) throws {
        try db.write { db in
            let qs = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(sql: "DELETE FROM courses WHERE id IN (\(qs))",
                           arguments: StatementArguments(ids))
        }
    }

    // DELETE FROM courses WHERE id = :id
    func deleteById(_ id: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM courses WHERE id = ?", arguments: [id]) }
    }

    // DELETE FROM courses WHERE tableId = :tableId
    func deleteByTableId(_ tableId: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM courses WHERE tableId = ?", arguments: [tableId]) }
    }

    // DELETE FROM courses WHERE tableId = :tableId AND groupId = :groupId
    func deleteByGroupId(_ tableId: Int64, _ groupId: String) throws {
        try db.write { try $0.execute(sql: "DELETE FROM courses WHERE tableId = ? AND groupId = ?", arguments: [tableId, groupId]) }
    }

    // SELECT * FROM courses WHERE id = :id LIMIT 1
    func getById(_ id: Int64) throws -> CourseEntity? {
        try db.read { try CourseEntity.fetchOne($0, sql: "SELECT * FROM courses WHERE id = ? LIMIT 1", arguments: [id]) }
    }

    // SELECT * FROM courses WHERE tableId = :tableId ORDER BY day, startNode, startWeek
    // (observeByTable: Flow 语义 → 变更通知由 Repository 的 GRDB ValueObservation 承担,查询本体共用本条)
    func getByTable(_ tableId: Int64) throws -> [CourseEntity] {
        try db.read { try CourseEntity.fetchAll($0, sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY day, startNode, startWeek", arguments: [tableId]) }
    }

    /// 全库课程(撤销快照用 ← courseDao.getAll())
    func getAllCourses() throws -> [CourseEntity] {
        try db.read { try CourseEntity.fetchAll($0, sql: "SELECT * FROM courses") }
    }

    /// 全库删除(撤销恢复用 ← courseDao.deleteAll();调用方保证在事务内)
    func deleteAllInDb(_ dbw: Database) throws {
        try dbw.execute(sql: "DELETE FROM courses")
    }

    // SELECT * FROM courses WHERE tableId = :tableId AND day = :day ORDER BY startNode
    // (observeByTableAndDay / getByTableAndDayOnce 共用)
    func getByTableAndDay(_ tableId: Int64, day: Int) throws -> [CourseEntity] {
        try db.read { try CourseEntity.fetchAll($0, sql: "SELECT * FROM courses WHERE tableId = ? AND day = ? ORDER BY startNode", arguments: [tableId, day]) }
    }

    // SELECT * FROM courses WHERE tableId = :tableId AND groupId = :groupId
    func getByGroupId(_ tableId: Int64, _ groupId: String) throws -> [CourseEntity] {
        try db.read { try CourseEntity.fetchAll($0, sql: "SELECT * FROM courses WHERE tableId = ? AND groupId = ?", arguments: [tableId, groupId]) }
    }

    // SELECT COUNT(*) FROM courses WHERE tableId = :tableId
    func countByTable(_ tableId: Int64) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM courses WHERE tableId = ?", arguments: [tableId]) ?? 0 }
    }

    // SELECT COUNT(*) FROM courses
    func totalCount() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM courses") ?? 0 }
    }

    /// 整表导入（覆盖式，原子事务）
    func replaceAll(tableId: Int64, courses: [CourseEntity]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ?", arguments: [tableId])
            for var c in courses { try c.insert(db, onConflict: .replace) }
        }
    }

    /// 编辑课程组：删除同 groupId 全部记录，再插入新记录（原子事务）
    func replaceGroup(tableId: Int64, groupId: String, newCourses: [CourseEntity]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ? AND groupId = ?", arguments: [tableId, groupId])
            for var c in newCourses { try c.insert(db, onConflict: .replace) }
        }
    }
}
