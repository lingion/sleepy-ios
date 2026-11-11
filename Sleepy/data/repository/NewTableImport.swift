// NewTableImport.swift — ← data/repository/NewTableImport.kt (v1.0.62, GPL-3.0)
// 导入新建课表的原子写核心 — 新课表 + 可选私有作息表 + 课程 + 默认表切换,
// 单事务一次提交、一个撤回单元。
//
// 纯函数半边(normalizedImportGroups / importNameKey / knownNameToGroupId)已落
// ImportRoster.swift(同名函数逐条对齐), 本文件只保留 store 协议 + 原子编排。
//
// iOS 适配(记录在案): 原版本 的 store 方法跑在 Room withTransaction 内,
// DAO 调用自动并入当前事务; GRDB 的 DatabaseQueue.write 禁止重入(DAO 的
// db.read/db.write 在写事务里会死锁), 故协议方法统一携带事务句柄 dbw 下传,
// 实现侧必须用 InDb 变体 / dbw 直查(与 JwImportViewModel.importAsNewTable 同手法)。

import Foundation
import GRDB

/// 挂到协议上的错误 — 原 `require(...) { "Selected period table no longer exists" }`。
enum NewTableImportError: Error {
    case selectedPeriodTableMissing
}

/// 导入写面抽象 — 原版本 NewTableImportStore(测试可注入假仓库, 生产走 GRDB 适配)。
protocol NewTableImportStore {
    /// 事务边界 — block 内所有方法调用共用同一 dbw(GRDB 禁重入, 句柄必须下传)。
    func atomic(_ block: (Database) throws -> Int64) throws -> Int64
    func periodExists(_ id: Int64, in dbw: Database) throws -> Bool
    func tableCount(in dbw: Database) throws -> Int
    /// 撤回快照 — 原版本 在事务内拍(require 之后、首写之前); iOS 用 dbw 直读同序。
    func captureUndo(in dbw: Database) throws
    func insertPeriod(_ period: PeriodTableEntity, in dbw: Database) throws -> Int64
    func insertTable(_ table: TimeTableEntity, in dbw: Database) throws -> Int64
    func insertCourses(_ courses: [CourseEntity], in dbw: Database) throws
    func setDefault(_ id: Int64, in dbw: Database) throws

    /// 认亲名册（spec §2.4）— 默认空 = v1.0.61 行为; 生产适配覆盖为全库查询。
    func knownNameRoster(in dbw: Database) throws -> [String: String]

    /// 派生档新课补色落库 — 默认无操作; 生产适配写 course_colors。
    func persistNewGroupColors(_ courses: [CourseEntity], in dbw: Database) throws
}

extension NewTableImportStore {
    func knownNameRoster(in dbw: Database) throws -> [String: String] { [:] }
    func persistNewGroupColors(_ courses: [CourseEntity], in dbw: Database) throws {}
}

/// 生产适配 — 协议方法直通 GRDB InDb DAO 变体; 事务包 dbQueue.write。
/// (ScheduleRepository.importNewTable 的匿名 NewTableImportStore)
final class GRDBNewTableImportStore: NewTableImportStore {
    private let db: AppDatabase
    private let validateImport: ((Database) throws -> Void)?

    init(db: AppDatabase, validateImport: ((Database) throws -> Void)? = nil) {
        self.db = db
        self.validateImport = validateImport
    }

    func atomic(_ block: (Database) throws -> Int64) throws -> Int64 {
        try db.dbQueue.write { dbw in
            try validateImport?(dbw)
            return try block(dbw)
        }
    }

    func periodExists(_ id: Int64, in dbw: Database) throws -> Bool {
        // ← periodTableDao.getById(id) != null — 事务内直查(DAO 的 db.read 会重入死锁)
        try PeriodTableEntity.fetchOne(
            dbw, sql: "SELECT * FROM period_tables WHERE id = ? LIMIT 1", arguments: [id]) != nil
    }

    func tableCount(in dbw: Database) throws -> Int {
        try Int.fetchOne(dbw, sql: "SELECT COUNT(*) FROM time_tables") ?? 0
    }

    func captureUndo(in dbw: Database) throws {
        // ← captureForUndo() — 快照形状与 ScheduleRepository.captureForUndo 同一四元组;
        //   GRDB 禁 db.read 重入, 改用事务句柄直读(列序与各 DAO 的 SELECT 语句一致)。
        let snapshot = UndoSnapshot(
            periodTables: try PeriodTableEntity.fetchAll(dbw),
            tables: try TimeTableEntity.fetchAll(dbw, sql: "SELECT * FROM time_tables ORDER BY createdAt DESC"),
            courses: try CourseEntity.fetchAll(dbw, sql: "SELECT * FROM courses ORDER BY id"),
            defaultTableId: try TimeTableEntity.fetchOne(
                dbw, sql: "SELECT * FROM time_tables WHERE isDefault = 1 LIMIT 1")?.id)
        dbw.afterNextTransaction { _ in
            UndoManager.shared.capture(tables: snapshot.tables, courses: snapshot.courses,
                defaultTableId: snapshot.defaultTableId, periodTables: snapshot.periodTables)
        }
    }

    func insertPeriod(_ period: PeriodTableEntity, in dbw: Database) throws -> Int64 {
        try db.periodTableDao.insertInDb(dbw, period)
    }

    func insertTable(_ table: TimeTableEntity, in dbw: Database) throws -> Int64 {
        try db.timeTableDao.insertInDb(dbw, table)
    }

    func insertCourses(_ courses: [CourseEntity], in dbw: Database) throws {
        _ = try db.courseDao.insertAllInDb(dbw, courses)
    }

    func setDefault(_ id: Int64, in dbw: Database) throws {
        try db.timeTableDao.setDefaultInDb(dbw, id)
    }

    func knownNameRoster(in dbw: Database) throws -> [String: String] {
        // 认亲（spec §2.4）: 事务内读导入前全库名册; 新课 hue 同事务落库。
        let rows = try CourseEntity.fetchAll(dbw, sql: "SELECT * FROM courses ORDER BY id")
        return ImportRoster.knownNameToGroupId(rows)
    }

    func persistNewGroupColors(_ courses: [CourseEntity], in dbw: Database) throws {
        _ = CourseColorWriteGlue.persistNewGroupHuesInDb(dbw: dbw,
                                                         dao: db.courseColorDao,
                                                         entities: courses)
    }
}

/// 原子导入编排 — ← 原版本 importNewTableAtomically。
/// 顺序: 悬空绑定拒绝 → 撤回快照 → (私有作息表) → 课表 → 课程(认亲) → 补色 → 设默认。
/// 任一步抛错 = 整笔事务回滚, 库态与调用前完全一致。
func importNewTableAtomically(store: NewTableImportStore,
                              table: TimeTableEntity,
                              courses: [CourseEntity],
                              period: PeriodTableEntity?,
                              bindingId: Int64?,
                              keepGroups: Bool) throws -> Int64 {
    try store.atomic { dbw in
        // ← require(bindingId == null || store.periodExists(bindingId))
        if let bindingId = bindingId {
            guard try store.periodExists(bindingId, in: dbw) else {
                throw NewTableImportError.selectedPeriodTableMissing
            }
        }
        try store.captureUndo(in: dbw)
        let isFirst = try store.tableCount(in: dbw) == 0
        // 选中既有作息表 → 共享(不新建不覆盖); 否则确认行 owns 新作息表。
        let periodId: Int64?
        if let bindingId = bindingId {
            periodId = bindingId
        } else if var draft = period {
            draft.id = 0
            periodId = try store.insertPeriod(draft, in: dbw)
        } else {
            periodId = nil
        }
        var newTable = table
        newTable.id = 0
        newTable.periodTableId = periodId
        newTable.isDefault = isFirst
        let tableId = try store.insertTable(newTable, in: dbw)
        var rows = courses
        for i in rows.indices {
            rows[i].id = 0
            rows[i].tableId = tableId
        }
        let grouped = keepGroups
            ? rows
            : ImportRoster.normalizedImportGroups(rows, knownNameToGroup: try store.knownNameRoster(in: dbw))
        try store.insertCourses(grouped, in: dbw)
        try store.persistNewGroupColors(grouped, in: dbw)
        if isFirst { try store.setDefault(tableId, in: dbw) }
        return tableId
    }
}
