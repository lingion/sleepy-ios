// AppDatabase.swift — ← data/AppDatabase.kt (GPL-3.0)
// Room @Database(version=3) → GRDB。建表 SQL 与 Room schema 逐列对齐
// (列名/类型亲和/索引/FK CASCADE — Room 注解生成语义手工落 SQL)。
// fallbackToDestructiveMigration → migrator 语义等价(v3 已是最新,降级/未知版本重建)。

import Foundation
import GRDB

final class AppDatabase {
    static let DB_NAME = "sleepy.db"

    /// 单例 (companion object { instance; fun get(context) })
    private static var instance: AppDatabase?
    private static let lock = NSLock()

    static func getShared() -> AppDatabase {
        lock.lock(); defer { lock.unlock() }
        if let i = instance { return i }
        let i = AppDatabase()
        instance = i
        return i
    }

    /// 测试用独立内存库(G4 链条测试起真数据层,不碰单例)
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(queue: DatabaseQueue())
    }

    let dbQueue: DatabaseQueue
    let courseDao: CourseDao
    let timeTableDao: TimeTableDao

    /// 默认走共享目录(AppGroupResolver: AltStore 侧载共享给 widget;Xcode 直跑回退沙箱)
    convenience init() {
        let dir = AppGroupResolver.sharedDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(Self.DB_NAME).path
        do {
            let queue = try DatabaseQueue(path: path)
            self.init(queue: queue)
        } catch {
            // 目录不可写等极端情形 → 内存库保命(与 Android fallbackToDestructiveMigration 同精神)
            self.init(queue: try! DatabaseQueue())
        }
    }

    init(queue: DatabaseQueue) {
        self.dbQueue = queue
        self.courseDao = CourseDao(db: queue)
        self.timeTableDao = TimeTableDao(db: queue)
        try? migrator.migrate(queue)
    }

    /// Room @Database version=3 的建表 DDL(逐列对齐 @Entity 注解)
    var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        // time_tables (TimeTableEntity.kt @Entity(tableName="time_tables"))
        m.registerMigration("v1.createTimeTables") { db in
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
        }

        // courses (CourseEntity.kt @Entity: 3 索引 + FK CASCADE)
        m.registerMigration("v1.createCourses") { db in
            try db.create(table: "courses") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("groupId", .text).notNull()
                t.column("tableId", .integer).notNull()
                    .references("time_tables", onDelete: .cascade)
                t.column("courseName", .text).notNull()
                t.column("teacher", .text).notNull().defaults(to: "")
                t.column("room", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
                t.column("day", .integer).notNull()
                t.column("startNode", .integer).notNull()
                t.column("step", .integer).notNull()
                t.column("startWeek", .integer).notNull()
                t.column("endWeek", .integer).notNull()
                t.column("type", .integer).notNull().defaults(to: 0)
                t.column("color", .text).notNull()
                t.column("ownTime", .boolean).notNull().defaults(to: false)
                t.column("startTime", .text).notNull().defaults(to: "")
                t.column("endTime", .text).notNull().defaults(to: "")
                t.column("credit", .double).notNull().defaults(to: 0.0)
                t.column("level", .integer).notNull().defaults(to: 0)
            }
            // Room: Index("tableId"), Index("day"), Index("startWeek","endWeek")
            try db.create(indexOn: "courses", columns: ["tableId"])
            try db.create(indexOn: "courses", columns: ["day"])
            try db.create(indexOn: "courses", columns: ["startWeek", "endWeek"])
        }

        return m
    }
}
