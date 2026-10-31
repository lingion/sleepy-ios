// AppDatabase.swift — ← data/AppDatabase.kt + Migrations.kt (GPL-3.0)
// Room @Database(version=10) → GRDB。建表 SQL 与 Room schema 逐列对齐
// (列名/类型亲和/索引/FK CASCADE — Room 注解生成语义手工落 SQL)。
// Room 仅在 @ColumnInfo(defaultValue=) 声明处输出 DEFAULT,故 v1 建表 DDL 各列裸 NOT NULL。
// Android 严禁 fallbackToDestructiveMigration (AppDatabase.kt:45-46) — 迁移失败即抛;
// iOS 等价物: migrate 失败 fatalError,绝不静默在未迁移库上运行。
// 目录不可写 → 内存库保命,是 iOS 侧独有防御,与 Android 机制无关。
// v4 = 1.0.52 issue#22 colorMode; v5 = issue#23 isIrregularNode/isIrregularTime;
// v6 = issue#26 alias; v7 = issue#39 import_drafts; v8 = issue#40 period_tables
//      + time_tables.periodTableId; v9 = issue#40 C2 preBindSnapshotJson;
// v10 = Sleepy 托管系统日历导入记录 (与 Android Migrations.kt 一一对应, Android 1.0.61 终点)。
// v11 = 每表独立提醒开关 reminderEnabled — 对齐 Android 目标 schema v11
//      (~/sleepy app/schemas/com.lingion.sleepy.data.AppDatabase/11.json:
//      `reminderEnabled INTEGER NOT NULL DEFAULT 1`; RoomSchemaContractTest.kt:47、
//      TableReminderMigrationTest.kt 同向锁定)。Android 仓 Kotlin 侧落地中
//      (AppDatabase version=10、Migrations.kt 止于 9_10、TimeTableEntity.kt 无该字段),
//      11.json 与其测试先入库; iOS 按 11.json 契约建列, SQL 形状逐字一致。

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
    let periodTableDao: PeriodTableDao
    let importDraftDao: ImportDraftDao
    let calendarImportRecordDao: CalendarImportRecordDao
    let courseColorDao: CourseColorDao

    /// 默认走共享目录(AppGroupResolver: AltStore 侧载共享给 widget;Xcode 直跑回退沙箱)
    convenience init() {
        let dir = AppGroupResolver.sharedDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(Self.DB_NAME).path
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: path)
        } catch {
            // 文件库打不开(目录不可写等极端情形)→ 内存库保命。
            // 注: 这是 iOS 侧独有防御;Android 无对应机制,勿引用其名义。
            queue = try! DatabaseQueue()
        }
        do {
            try self.init(queue: queue)
        } catch {
            // 对齐 Android 严禁 fallbackToDestructiveMigration (AppDatabase.kt:45-46):
            // Room 迁移失败在首次访问即抛出、应用崩溃,绝不在未迁移的库上继续运行。
            fatalError("AppDatabase schema migration failed — 禁止静默运行在未迁移库上: \(error)")
        }
    }

    /// throws: 迁移失败向上抛(Room 无兜底 = 响亮失败),调用方不得吞掉。
    /// 已知调用侧均处理: 生产路径走 convenience init(fatalError 上抛),测试路径显式 try/try?。
    init(queue: DatabaseQueue) throws {
        self.dbQueue = queue
        self.courseDao = CourseDao(db: queue)
        self.timeTableDao = TimeTableDao(db: queue)
        self.periodTableDao = PeriodTableDao(db: queue)
        self.importDraftDao = ImportDraftDao(db: queue)
        self.calendarImportRecordDao = CalendarImportRecordDao(db: queue)
        self.courseColorDao = CourseColorDao(db: queue)
        try migrator.migrate(queue)
    }

    /// Room @Database version=3 的建表 DDL(逐列对齐 @Entity 注解)
    var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        // time_tables (TimeTableEntity.kt @Entity(tableName="time_tables"))
        // Room DDL 逐列对齐: maxWeek/nodesPerDay/timeJson/color/isDefault/smartConfigJson
        // 在实体上均无 @ColumnInfo(defaultValue=) → Room 建表输出裸 NOT NULL。
        // Kotlin 侧的 20/12/DEFAULT_TIME_JSON/#FF6750A4/false/"" 是构造器默认,
        // 由 TimeTableEntity.swift 的 Swift 属性默认值承担,不落 DDL。
        m.registerMigration("v1.createTimeTables") { db in
            try db.create(table: "time_tables") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("startDate", .text).notNull()
                t.column("maxWeek", .integer).notNull()
                t.column("nodesPerDay", .integer).notNull()
                t.column("timeJson", .text).notNull()
                t.column("color", .text).notNull()
                t.column("isDefault", .boolean).notNull()
                t.column("smartConfigJson", .text).notNull()
                t.column("createdAt", .integer).notNull()
            }
        }

        // courses (CourseEntity.kt @Entity: 3 索引 + FK CASCADE)
        // 同上: teacher/room/note/type/ownTime/startTime/endTime/credit/level
        // 无 @ColumnInfo(defaultValue=) → 裸 NOT NULL (alias/colorMode/isIrregular*
        // 是后续 ALTER 且 Room 声明了 defaultValue,故那些列保留 DEFAULT)。
        m.registerMigration("v1.createCourses") { db in
            try db.create(table: "courses") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("groupId", .text).notNull()
                t.column("tableId", .integer).notNull()
                    .references("time_tables", onDelete: .cascade)
                t.column("courseName", .text).notNull()
                t.column("teacher", .text).notNull()
                t.column("room", .text).notNull()
                t.column("note", .text).notNull()
                t.column("day", .integer).notNull()
                t.column("startNode", .integer).notNull()
                t.column("step", .integer).notNull()
                t.column("startWeek", .integer).notNull()
                t.column("endWeek", .integer).notNull()
                t.column("type", .integer).notNull()
                t.column("color", .text).notNull()
                t.column("ownTime", .boolean).notNull()
                t.column("startTime", .text).notNull()
                t.column("endTime", .text).notNull()
                t.column("credit", .double).notNull()
                t.column("level", .integer).notNull()
            }
            // Room: Index("tableId"), Index("day"), Index("startWeek","endWeek")
            try db.create(indexOn: "courses", columns: ["tableId"])
            try db.create(indexOn: "courses", columns: ["day"])
            try db.create(indexOn: "courses", columns: ["startWeek", "endWeek"])
        }

        // ← MIGRATION_3_4 (1.0.52 issue#22): courses 加 colorMode 列, 旧数据全默认 0=GROUP
        m.registerMigration("v4.addColorMode") { db in
            try db.execute(sql: "ALTER TABLE courses ADD COLUMN colorMode INTEGER NOT NULL DEFAULT 0")
        }

        // ← MIGRATION_4_5 (issue#23 逐卡非常规重构): isIrregularNode / isIrregularTime
        //    ownTime=1 旧行 isIrregularTime=1 (旧「自定义时间」语义并入新标志)
        m.registerMigration("v5.addIrregular") { db in
            try db.execute(sql: "ALTER TABLE courses ADD COLUMN isIrregularNode INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE courses ADD COLUMN isIrregularTime INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "UPDATE courses SET isIrregularTime = 1 WHERE ownTime = 1")
        }

        // ← MIGRATION_5_6 (issue#26 课程别名): alias 列, 旧行全空 → 处处显示原名
        m.registerMigration("v6.addAlias") { db in
            try db.execute(sql: "ALTER TABLE courses ADD COLUMN alias TEXT NOT NULL DEFAULT ''")
        }

        // ← MIGRATION_6_7 (issue#39): import_drafts 导入草稿快照表。
        //   草稿由显式 id 标识, payloadJson 保持导入预览数据的演进空间。
        m.registerMigration("v7.createImportDrafts") { db in
            try db.create(table: "import_drafts") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("sourceType", .text).notNull().defaults(to: "")
                t.column("sourceUrl", .text).notNull().defaults(to: "")
                t.column("payloadJson", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
        }

        // ← MIGRATION_7_8 (issue#40): 独立时间节次表 + time_tables.periodTableId。
        //   迁移: 每张旧课表生成一张独立时间节次表(继承 timeJson/smartConfigJson/nodesPerDay),
        //   periodTableId 指过去 — 旧用户课表不意外共享同一份作息;
        //   旧 timeJson/smartConfigJson/nodesPerDay 保留为兼容列(异常回退)。
        m.registerMigration("v8.createPeriodTables") { db in
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

            // 保留旧课表 id → 回填确定, UPDATE 可逐行核对
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, nodesPerDay, timeJson, smartConfigJson, createdAt FROM time_tables ORDER BY id
                """)
            for row in rows {
                let id: Int64 = row["id"]
                let name: String = row["name"]
                let nodesPerDay: Int = row["nodesPerDay"]
                let timeJson: String = row["timeJson"]
                let smartConfigJson: String = row["smartConfigJson"]
                let createdAt: Int64 = row["createdAt"]
                try db.execute(sql: """
                    INSERT INTO period_tables (id, name, nodesPerDay, timeJson, smartConfigJson, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, name, nodesPerDay, timeJson, smartConfigJson, createdAt, createdAt])
                try db.execute(sql: "UPDATE time_tables SET periodTableId = ? WHERE id = ?", arguments: [id, id])
            }
        }

        // ← MIGRATION_8_9 (issue#40 C2 换绑前快照, 2026-09-20):
        //   加 time_tables.preBindSnapshotJson; 纯加列, 旧行默认空串 = 无快照(行为不变)
        m.registerMigration("v9.addPreBindSnapshot") { db in
            try db.execute(sql: "ALTER TABLE time_tables ADD COLUMN preBindSnapshotJson TEXT NOT NULL DEFAULT ''")
        }

        // ← MIGRATION_9_10: Sleepy 托管的系统日历事件登记表(同步去重/清理)
        m.registerMigration("v10.createCalendarImportRecords") { db in
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
            try db.create(indexOn: "calendar_import_records",
                          columns: ["tableId", "courseId", "eventDate", "calendarId"], options: [.unique])
            try db.create(indexOn: "calendar_import_records", columns: ["tableId"])
            try db.create(indexOn: "calendar_import_records", columns: ["batchId"])
        }

        // v11 (iOS-ahead, 2026-10-08): 每表独立提醒开关。
        // Android 1.0.61 无此迁移(version=10)——其提醒开关是 AppPrefs 全局值
        // (CalendarImportDialog.kt:78 getCalendarReminderMinutes);本列为 iOS 侧
        // 每课表粒度功能,记录为 iOS-ahead 而非对齐项。
        // SQLite ALTER ADD COLUMN ... DEFAULT 1 使老行回填 1(继续参与提醒,行为不变)。
        m.registerMigration("v11.addReminderEnabled") { db in
            try db.execute(
                sql: "ALTER TABLE time_tables ADD COLUMN reminderEnabled INTEGER NOT NULL DEFAULT 1")
        }

        // ← MIGRATION_11_12 (v1.0.62 B1): 课程持久色相表 course_colors。
        // (tableKey, groupId) 复合主键 → hue REAL，不回填（新表为空,CLASSIC 档不读）。
        m.registerMigration("v12.createCourseColors") { db in
            try db.create(table: "course_colors", options: []) { t in
                t.column("tableKey", .text).notNull()
                t.column("groupId", .text).notNull()
                t.column("hue", .double).notNull()
                t.primaryKey(["tableKey", "groupId"])
            }
        }

        return m
    }
}
