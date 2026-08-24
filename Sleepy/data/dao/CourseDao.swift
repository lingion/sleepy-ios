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
