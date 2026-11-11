// ScheduleRepository.swift — ← ScheduleRepository.kt
// 课表仓库 — 业务数据访问的唯一入口。
//
// UI 层只调这个类,不直接碰 DAO。
// (Flow → AsyncStream/Combine 视调用方需要;先落 suspend 等价 = 同步 throws)

import Foundation
import Combine
import GRDB

final class ScheduleRepository {
    enum TableEditSaveError: Error {
        case missingTable
        case missingPeriodTable
        case missingPolicy
        case staleTimeTable
        case invalidCourseDraft
    }
    private let db: AppDatabase
    private let courseDao: CourseDao
    /// 库句柄对外只读暴露(镜像快照需要读 course_colors 表) — 只读用途。
    var database: AppDatabase { db }
    private let tableDao: TimeTableDao
    private let periodTableDao: PeriodTableDao
    private let courseColorDao: CourseColorDao
    /// ← SleepyApp.get().notificationScheduler / WidgetUpdater
    /// iOS: 数据变更回调(由 App 壳注入: 刷 WidgetKit timeline + 重排 UNNotification)
    var onDataChangedHook: (() -> Void)?

    init(_ db: AppDatabase) {
        self.db = db
        self.courseDao = db.courseDao
        self.tableDao = db.timeTableDao
        self.periodTableDao = PeriodTableDao(db: db.dbQueue)
        self.courseColorDao = db.courseColorDao
    }

    // ========== v7.10.16 单级撤回 + 2026-09-21 单级 redo ==========

    var canUndo: Bool { UndoManager.shared.hasSnapshot }
    var canRedo: Bool { UndoManager.shared.hasRedoSnapshot }

    /// 普通写入口：同一事务读取旧状态并写入，COMMIT 后才发布撤回快照。
    /// 闭包只使用传入的 Database / InDb 方法，不能重入 DAO 的队列包装。
    /// 批次仍由 UndoManager 保留首个成功写入前的快照；失败与 no-op 不占首拍。
    private func writeWithUndo<T>(_ updates: (Database) throws -> T) throws -> T {
        try db.dbQueue.write { db in
            let tables = try TimeTableEntity.fetchAll(db)
            let snapshot = UndoSnapshot(periodTables: try PeriodTableEntity.fetchAll(db),
                tables: tables, courses: try CourseEntity.fetchAll(db),
                defaultTableId: tables.first(where: { $0.isDefault })?.id)
            let before = try Int.fetchOne(db, sql: "SELECT total_changes()")
            let result = try updates(db)
            if try Int.fetchOne(db, sql: "SELECT total_changes()") != before {
                db.afterNextTransaction { _ in
                    UndoManager.shared.capture(tables: snapshot.tables, courses: snapshot.courses,
                        defaultTableId: snapshot.defaultTableId, periodTables: snapshot.periodTables)
                }
            }
            return result
        }
    }

    /// 取一份当前库态 — 内部用: 给 undo / redo 的反向槽用。
    private func snapshotCurrent() throws -> UndoSnapshot {
        UndoSnapshot(
            periodTables: try periodTableDao.getAll(),
            tables: try tableDao.getAll(),
            courses: try courseDao.getAllCourses(),
            defaultTableId: try tableDao.getDefault()?.id
        )
    }

    private func applySnapshot(_ snap: UndoSnapshot) throws {
        try db.dbQueue.write { db in
            // issue#40: 恢复顺序 courses → time_tables → period_tables 删除,
            // 插入按 period_tables → time_tables → courses。
            // time_tables.periodTableId 指向 period_tables.id — 先插 periodTables
            // 保证引用目标先存在; 先课程后课表会触发外键约束闪退。
            try courseDao.deleteAllInDb(db)
            try db.execute(sql: "DELETE FROM time_tables")
            try db.execute(sql: "DELETE FROM period_tables")
            for t in snap.periodTables { var t = t; try t.insert(db, onConflict: .replace) }
            for t in snap.tables { var t = t; try t.insert(db, onConflict: .replace) }
            for c in snap.courses { var c = c; try c.insert(db, onConflict: .replace) }
            if let defId = snap.defaultTableId {
                try db.execute(sql: "UPDATE time_tables SET isDefault = (id = ?)", arguments: [defId])
            }
        }
    }

    /// 撤回最近一次改动: 事务内清三表→按外键顺序重插快照→恢复 default → 刷 widget/通知。
    /// 撤回前把"撤回前库态"落入 redo 槽(取消撤回用)。false = 无可撤回
    @discardableResult
    func restoreLastSnapshot() throws -> Bool {
        let history = UndoManager.shared
        guard history.hasSnapshot else { return false }
        // 当前态读取失败不动两栈。
        let redoSnap = try snapshotCurrent()
        guard let undoSnap = history.poll() else { return false }
        history.restoring = true
        defer { history.restoring = false }
        do {
            try applySnapshot(undoSnap)
        } catch {
            // GRDB 已回滚；原位放回栈顶，不能用会清 redo 的 capture。
            history.reinsertForRedoSymmetry(undoSnap)
            throw error
        }
        history.recordRedo(redoSnap)
        onDataChanged()
        pruneDefaultTopPrefs()
        return true
    }

    /// 取消最近一次撤回: redo 槽快照恢复回库, undo 槽收回当前库态。false = 无可取消。
    @discardableResult
    func redoLastUndo() throws -> Bool {
        let history = UndoManager.shared
        guard history.hasRedoSnapshot else { return false }
        let undoSnap = try snapshotCurrent()
        guard let redoSnap = history.pollRedo() else { return false }
        history.restoring = true
        defer { history.restoring = false }
        do {
            try applySnapshot(redoSnap)
        } catch {
            history.recordRedo(redoSnap)
            throw error
        }
        history.reinsertForRedoSymmetry(undoSnap)
        onDataChanged()
        pruneDefaultTopPrefs()
        return true
    }

    // ========== TimeTable ==========

    func getAllTables() throws -> [TimeTableEntity] { try tableDao.getAll() }

    func getTable(_ id: Int64) throws -> TimeTableEntity? { try tableDao.getById(id) }

    func getDefaultTable() throws -> TimeTableEntity? { try tableDao.getDefault() }

    @discardableResult
    func insertTable(_ table: TimeTableEntity) throws -> Int64 {
        try writeWithUndo { db in
            let id = try tableDao.insertInDb(db, table)
            let count = try TimeTableEntity.fetchCount(db)
            if table.isDefault || count == 1 {
                try tableDao.setDefaultInDb(db, id)
            }
            return id
        }
    }

    /// 表配置、课程与新组 ID 一次提交；任一插入失败不留下空副本，也不消费撤回历史。
    /// 保留原表绑定与兼容列，不改变当前默认表。
    @discardableResult
    func duplicateTable(_ id: Int64, newName: String? = nil) throws -> Int64 {
        let (newID, copiedCourses) = try writeWithUndo { db in
            guard let source = try TimeTableEntity.fetchOne(db, key: id) else {
                throw TableEditSaveError.missingTable
            }
            let courses = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY id", arguments: [id])
            let courseNames = try String.fetchAll(db, sql: "SELECT name FROM time_tables")
            let periodNames = try String.fetchAll(db, sql: "SELECT name FROM period_tables")
            let names = Set(courseNames + periodNames)
            var name = TimeTableUtils.suggestUniqueName(source.name, courseTableNames: courseNames,
                                                       periodTableNames: periodNames)
            var copy = source
            copy.id = 0
            if let newName {
                let requested = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requested.isEmpty, !names.contains(requested) else { throw TableEditSaveError.invalidCourseDraft }
                name = requested
            }
            copy.name = name
            copy.isDefault = false
            copy.reminderOverride = nil
            copy.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            let newID = try tableDao.insertInDb(db, copy)
            var groupMap: [String: String] = [:]
            let copiedCourses = courses.map { course -> CourseEntity in
                let groupID: String
                if let mapped = groupMap[course.groupId] {
                    groupID = mapped
                } else {
                    groupID = UUID().uuidString
                    groupMap[course.groupId] = groupID
                }
                var row = course
                row.id = 0
                row.tableId = newID
                row.groupId = groupID
                return row
            }
            // Copies keep their own groups; import name matching would rejoin them to the source.
            _ = try courseDao.insertAllInDb(db, copiedCourses)
            return (newID, copiedCourses)
        }
        persistNewGroupColors(copiedCourses)
        onDataChanged()
        return newID
    }

    /// v1.0.62 B7b ← 原版本 ScheduleRepository.importNewTable: 新课表 + 可选私有作息表 +
    /// 课程 + 默认表切换, 单事务原子提交(一个撤回单元)。
    /// 认亲（spec §2.4）: 事务内读导入前全库名册; 新课 hue 同事务落库(见 GRDBNewTableImportStore)。
    @discardableResult
    func importNewTable(table: TimeTableEntity,
                        courses: [CourseEntity],
                        periodTable: PeriodTableEntity?,
                        bindPeriodTableId: Int64? = nil,
                        keepGroups: Bool = false) throws -> Int64 {
        // Confirmation can become stale while another editor changes the shared bell schedule.
        let store = GRDBNewTableImportStore(db: db) { dbw in
            let confirmedTimeJson: String
            if let id = bindPeriodTableId {
                guard let shared = try PeriodTableEntity.fetchOne(dbw, key: id) else {
                    throw NewTableImportError.selectedPeriodTableMissing
                }
                confirmedTimeJson = shared.timeJson
            } else {
                confirmedTimeJson = periodTable?.timeJson ?? table.timeJson
            }
            try CourseImportPolicy.requirePeriodCoverage(courses, timeJson: confirmedTimeJson)
        }
        let id = try importNewTableAtomically(store: store,
                                              table: table,
                                              courses: courses,
                                              period: periodTable,
                                              bindingId: bindPeriodTableId,
                                              keepGroups: keepGroups)
        onDataChanged()
        return id
    }

    func updateTable(_ table: TimeTableEntity) throws {
        try writeWithUndo { db in try table.update(db) }
        onDataChanged()
    }

    func getReminderTables() throws -> [TimeTableEntity] {
        let tables = try getAllTables()
        return resolveReminderTableScope(tables: tables, selectedTableId: tables.first { $0.isDefault }?.id)
    }

    /// The first manual toggle freezes the complete effective selection atomically.
    func setTableReminderEnabled(id: Int64, enabled: Bool) throws {
        let changed = try writeWithUndo { db -> Bool in
            let tables = try TimeTableEntity.fetchAll(db)
            let resolved = resolveReminderTableScope(tables: tables, selectedTableId: tables.first { $0.isDefault }?.id)
            guard let current = resolved.first(where: { $0.id == id }), current.reminderEnabled != enabled else { return false }
            if !tables.contains(where: { $0.reminderOverride != nil }) {
                for table in resolved {
                    try db.execute(sql: "UPDATE time_tables SET reminderEnabled = ?, reminderOverride = ? WHERE id = ?",
                        arguments: [table.id == id ? enabled : table.reminderEnabled, table.id == id ? enabled : table.reminderEnabled, table.id])
                }
                return true
            }
            guard tables.first(where: { $0.id == id })?.reminderOverride != enabled else { return false }
            try db.execute(sql: "UPDATE time_tables SET reminderEnabled = ?, reminderOverride = ? WHERE id = ?", arguments: [enabled, enabled, id])
            return true
        }
        if changed { onDataChanged() }
    }

    /// Apply a reviewed school refresh without replacing timetable preferences or local customizations.
    func updateImportedCourses(tableId: Int64, courses: [CourseEntity], incomingTimeJson: String = "",
                               expectedCourses: [CourseEntity]? = nil) throws {
        try writeWithUndo { db in
            guard var table = try TimeTableEntity.fetchOne(db, key: tableId) else { throw TableEditSaveError.missingTable }
            let existing = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY id", arguments: [tableId])
            if let expectedCourses, existing != expectedCourses.sorted(by: { $0.id < $1.id }) {
                throw TableEditSaveError.staleTimeTable
            }
            let ids = courses.filter { $0.id > 0 }.map(\.id)
            guard Set(ids).count == ids.count, Set(ids).isSubset(of: Set(existing.map(\.id))) else {
                throw TableEditSaveError.invalidCourseDraft
            }
            var period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            if table.periodTableId != nil && period == nil { throw TableEditSaveError.missingPeriodTable }
            let effective = table.hydratedWith(period)
            let reach = try courses.map { row -> Int in
                guard row.step > 0 else { throw TableEditSaveError.invalidCourseDraft }
                let (end, overflow) = row.startNode.addingReportingOverflow(row.step - 1)
                guard !overflow else { throw TableEditSaveError.invalidCourseDraft }
                return end
            }.max() ?? 0
            let extended = CourseImportPolicy.mergeTimeJson(current: effective.timeJson, incoming: incomingTimeJson,
                                                            requiredNodes: max(effective.nodesPerDay, reach))
            var groups: [String: String] = [:]
            var rows = courses
            for index in rows.indices {
                rows[index].id = max(0, rows[index].id)
                rows[index].tableId = tableId
                if rows[index].groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let key = rows[index].courseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let group = groups[key] ?? UUID().uuidString
                    groups[key] = group; rows[index].groupId = group
                }
            }
            let retained = Set(ids)
            for old in existing where !retained.contains(old.id) { try old.delete(db) }
            for var row in rows where row.id > 0 { try row.update(db) }
            let inserts = rows.filter { $0.id == 0 }
            _ = try courseDao.insertAllInDb(db, inserts)
            _ = CourseColorWriteGlue.persistNewGroupHuesInDb(dbw: db, dao: courseColorDao, entities: inserts)
            let maxNode = TimeTableUtils.parseTimeSlotRows(extended).map(\.node).max() ?? effective.nodesPerDay
            if var bound = period {
                if bound.timeJson != extended || bound.nodesPerDay != maxNode {
                    bound.timeJson = extended; bound.nodesPerDay = maxNode
                    bound.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                    try bound.update(db)
                }
            } else { table.timeJson = extended; table.nodesPerDay = maxNode }
            table.maxWeek = max(table.maxWeek, rows.map(\.endWeek).max() ?? table.maxWeek)
            try table.update(db)
        }
        onDataChanged()
    }

    /// 2026-09-23 症状3修复: 编辑课表保存 — 只写课程表自身元数据(name/startDate/maxWeek),
    /// 绑定关系与兼容列原样保留。
    ///
    /// 场景: 课表绑定了共享作息表时, 用户同时改了名字/日期/周次与绑定关系;
    /// updateTable 整行覆盖会带着旧 periodTableId 抹掉并发的 bind 写入(或反之),
    /// 两个独立 launch 的竞态会让"改名不生效"复发。本方法从库内现值合成目标行,
    /// 按字段挑着写, 绝不触碰 periodTableId/preBindSnapshotJson 等列。
    ///
    /// [writeTimeDomain]=true 时同步写 timeJson/smartConfigJson/nodesPerDay — 仅用于
    /// 解绑场景: 用户编辑的是旧源兼容列, 解绑后兼容列是真值。
    func updateTableMetadata(_ table: TimeTableEntity, writeTimeDomain: Bool = false) throws {
        let found = try writeWithUndo { db -> Bool in
            guard let current = try TimeTableEntity.fetchOne(db, key: table.id) else { throw TableEditSaveError.missingTable }
            var merged = current
            merged.name = table.name
            merged.startDate = table.startDate
            merged.maxWeek = table.maxWeek
            if writeTimeDomain {
                merged.timeJson = table.timeJson
                merged.smartConfigJson = table.smartConfigJson
                merged.nodesPerDay = table.nodesPerDay
            }
            let changed = merged.name != current.name
                || merged.startDate != current.startDate
                || merged.maxWeek != current.maxWeek
                || (writeTimeDomain && (merged.timeJson != current.timeJson
                    || merged.smartConfigJson != current.smartConfigJson
                    || merged.nodesPerDay != current.nodesPerDay))
            if changed { try merged.update(db) }
            return true
        }
        if found { onDataChanged() }
    }

    /// 2026-09-23 症状3修复: 编辑课表保存 — 元数据 + 共享作息表内容, 单事务原子双写。
    ///
    /// 场景: 课表绑定共享作息表, 用户改了名字/日期/周次且同时改了节次内容;
    /// 两条独立写(updateTable + updatePeriodTableContent)顺序不保证, 撤回快照
    /// 也可能只拍到一半。本方法一次快照一次事务同时落两行, 要么都成要么都不成。
    func updateTableMetadataWithPeriodTable(table: TimeTableEntity, periodTable: PeriodTableEntity) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let changed = try writeWithUndo { db -> Bool in
            guard let current = try TimeTableEntity.fetchOne(db, key: table.id),
                  try PeriodTableEntity.fetchOne(db, key: periodTable.id) != nil else { throw TableEditSaveError.missingPeriodTable }
            var next = current
            next.name = table.name
            next.startDate = table.startDate
            next.maxWeek = table.maxWeek
            try next.update(db)
            var stamped = periodTable
            stamped.updatedAt = now
            try updatePeriodTableWithEdgeMigrationInDb(db, table: stamped)
            return true
        }
        if changed { onDataChanged() }
    }

    /// 2026-09-23 症状3修复: 编辑课表保存 — 元数据 + 换绑, 单事务原子完成。
    ///
    /// 换绑时编辑区的 slotRows 已随 pendingBind 切到目标作息表 — 用户编辑的是目标表
    /// 内容, 由 [periodContent] 一并落回目标 period_tables; 解绑(periodTableId=nil)
    /// 时用户编辑的是本表兼容列, 时间域从 [table] 落回解绑后的兼容列。
    /// 与 bindPeriodTable 不同: 那条不落元数据, 这条一并落, 一次撤回整步回退。
    func updateTableMetadataAndBind(
        table: TimeTableEntity,
        periodTableId: Int64?,
        periodContent: PeriodTableEntity? = nil
    ) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let changed = try writeWithUndo { db -> Bool in
            guard let current = try TimeTableEntity.fetchOne(db, key: table.id) else { throw TableEditSaveError.missingTable }
            if let pid = periodTableId, try PeriodTableEntity.fetchOne(db, key: pid) == nil { throw TableEditSaveError.missingPeriodTable }
            if let pc = periodContent, try PeriodTableEntity.fetchOne(db, key: pc.id) == nil { throw TableEditSaveError.missingPeriodTable }
            if current.periodTableId == periodTableId && periodContent == nil,
               current.name == table.name, current.startDate == table.startDate, current.maxWeek == table.maxWeek,
               periodTableId != nil || (current.timeJson == table.timeJson
                && current.smartConfigJson == table.smartConfigJson && current.nodesPerDay == table.nodesPerDay) {
                return true
            }
            let next: TimeTableEntity
            if current.periodTableId == nil && periodTableId != nil {
                next = TimeTableEntity.snapshotForBind(table: current, targetId: periodTableId!)
            } else if current.periodTableId != nil && periodTableId == nil {
                // 解绑: 先恢复绑定前快照, 再叠用户本次编辑的时间域(编辑区展示的
                // 就是兼容列内容, 用户改动必须是解绑后的真值)
                var restored = TimeTableEntity.restoredForUnbind(table: current)
                restored.timeJson = table.timeJson
                restored.smartConfigJson = table.smartConfigJson
                restored.nodesPerDay = table.nodesPerDay
                next = restored
            } else {
                var t = current
                t.periodTableId = periodTableId
                next = t
            }
            var merged = next
            merged.name = table.name
            merged.startDate = table.startDate
            merged.maxWeek = table.maxWeek
            if periodTableId == nil {
                merged.timeJson = table.timeJson
                merged.smartConfigJson = table.smartConfigJson
                merged.nodesPerDay = table.nodesPerDay
            }
            if let pc = periodContent {
                var stamped = pc
                stamped.updatedAt = now
                try updatePeriodTableWithEdgeMigrationInDb(db, table: stamped)
            }
            // Existing owners use the target's old identities; the new binding does not.
            try merged.update(db)
            return true
        }
        if changed { onDataChanged() }
    }

    /// issue#28 P3: 编辑课表保存 — timeJson 变更时课程按绝对时间自适应新节次。
    ///
    /// 节次编号语义 = "该节在新表上的钟点", 表变了编号必须跟着变, 否则改完 16→12 节
    /// 课程还停在 13-16 节。ownTime 课自带绝对时间(timeToNode 直接定位), 普通课按
    /// remapCourseNodes 重排; 无法映射的课保持原节次。与 updateTable 同为单动作
    /// 撤回单元(首快照 = 改表前)。
    func updateTableRemappingCourses(_ table: TimeTableEntity) throws {
        try writeWithUndo { db in
            guard let old = try TimeTableEntity.fetchOne(db, key: table.id) else { throw TableEditSaveError.missingTable }
            try updateTableRemappingCoursesInDb(db, table: table, oldTimeJson: old.timeJson)
        }
        onDataChanged()
    }

    /// A policy save is one database transaction and one undo action. No nested DAO writes.
    func executeScheduleEditPolicy(editedTable: TimeTableEntity, draft: PeriodTableEntity,
                                   policy: SchedulePolicy) throws {
        try writeWithUndo { db in
            guard let current = try TimeTableEntity.fetchOne(db, key: editedTable.id) else { throw TableEditSaveError.missingTable }
            let oldPeriod = try current.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            let oldTimeJson = current.hydratedWith(oldPeriod).timeJson
            switch policy {
            case .detachCopy:
                var detached = editedTable
                detached.periodTableId = nil
                detached.preBindSnapshotJson = ""
                detached.timeJson = draft.timeJson
                detached.smartConfigJson = draft.smartConfigJson
                detached.nodesPerDay = draft.nodesPerDay
                try updateTableRemappingCoursesInDb(db, table: detached, oldTimeJson: oldTimeJson)
            case .createNew:
                let name = TimeTableUtils.suggestUniqueName(current.name,
                    courseTableNames: try TimeTableEntity.fetchAll(db).map(\.name),
                    periodTableNames: try PeriodTableEntity.fetchAll(db).map(\.name), defaultName: current.name)
                let period = PeriodTableEntity(name: name, nodesPerDay: draft.nodesPerDay,
                                              timeJson: draft.timeJson, smartConfigJson: draft.smartConfigJson)
                let newID = try periodTableDao.insertInDb(db, period)
                let bound = current.periodTableId == nil
                    ? TimeTableEntity.snapshotForBind(table: current, targetId: newID) : current
                var rebound = editedTable
                rebound.periodTableId = newID
                rebound.preBindSnapshotJson = bound.preBindSnapshotJson
                rebound.timeJson = current.timeJson
                rebound.smartConfigJson = current.smartConfigJson
                rebound.nodesPerDay = current.nodesPerDay
                try updateTableRemappingCoursesInDb(db, table: rebound, oldTimeJson: oldTimeJson,
                                                   newTimeJson: draft.timeJson)
            case .sync:
                guard let boundID = current.periodTableId,
                      try PeriodTableEntity.fetchOne(db, key: boundID) != nil else { throw TableEditSaveError.missingPeriodTable }
                var synced = draft
                synced.id = boundID
                synced.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                try updatePeriodTableWithEdgeMigrationInDb(db, table: synced)
                var next = editedTable
                next.periodTableId = current.periodTableId
                next.preBindSnapshotJson = current.preBindSnapshotJson
                next.timeJson = current.timeJson
                next.smartConfigJson = current.smartConfigJson
                next.nodesPerDay = current.nodesPerDay
                try next.update(db)
            case .none:
                throw TableEditSaveError.missingPolicy
            }
        }
        onDataChanged()
    }

    private func updateTableRemappingCoursesInDb(_ db: Database, table: TimeTableEntity,
                                               oldTimeJson: String, newTimeJson: String? = nil) throws {
            let destinationTimeJson = newTimeJson ?? table.timeJson
            try table.update(db)
            guard destinationTimeJson != oldTimeJson else { return }
            let courses = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ?", arguments: [table.id])
            let edgeRemapped = remapRenumberedEdgeCourses(courses, oldTimeJson: oldTimeJson,
                                                        newTimeJson: destinationTimeJson)
            let remapped = zip(courses, edgeRemapped).map { c, edge -> CourseEntity in
                // Shared edge identity takes precedence over absolute-clock remapping.
                if c.isIrregularNode {
                    return edge
                } else if c.ownTime {
                    if let mapped = TimeTableUtils.timeToNode(c.startTime, c.endTime, destinationTimeJson) {
                        var copy = c
                        copy.startNode = mapped.0
                        copy.step = mapped.1
                        return copy
                    }
                    return c
                } else {
                    let (node, step) = Self.remapCourseNodes(
                        startNode: c.startNode, step: c.step,
                        oldTimeJson: oldTimeJson, newTimeJson: destinationTimeJson
                    )
                    if node == c.startNode && step == c.step { return c }
                    var copy = c
                    copy.startNode = node
                    copy.step = step
                    return copy
                }
            }
            let changed = zip(remapped, courses).filter { $0.0 != $0.1 }
                .map { $0.0 }
            for course in changed { try course.update(db) }
    }

    /// Shared saves retain standard course ordinals and migrate only edge identities.
    /// Called inside the enclosing save transaction so all owners and Undo change together.
    private func updatePeriodTableWithEdgeMigrationInDb(_ db: Database, table: PeriodTableEntity) throws {
        guard let previous = try PeriodTableEntity.fetchOne(db, key: table.id) else {
            throw TableEditSaveError.missingPeriodTable
        }
        try table.update(db)
        guard previous.timeJson != table.timeJson else { return }
        let owners = try Int64.fetchAll(db, sql: "SELECT id FROM time_tables WHERE periodTableId = ?", arguments: [table.id])
        for owner in owners {
            let courses = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ?", arguments: [owner])
            let migrated = remapRenumberedEdgeCourses(courses, oldTimeJson: previous.timeJson, newTimeJson: table.timeJson)
            for (old, next) in zip(courses, migrated) where old != next {
                try next.update(db)
            }
        }
    }

    /// issue#28 P3: 作息表变更后的课程节次自适应(TimeTableUtils.remapCourseNodes)。
    ///
    /// 节次编号只是旧表绝对时间窗的载体: 取课程首节在旧表的 start 与末节在旧表的
    /// end, 在新表上找与之重叠的节点区间 — 首节 = 第一个 end 晚于课程起点的节,
    /// 末节 = 最后一个 start 早于课程终点的节。旧表缺行(课程锚的节次不存在)或
    /// 新表无任何重叠 → 返回原值(孤儿课保持原节次, 不猜不丢)。
    /// NOTE: 原版本 侧此函数归属 TimeTableUtils; iOS 先落本文件私有静态成员,
    /// 集成者可原样平移至 Sleepy/util/TimeTableUtils.swift。
    static func remapCourseNodes(startNode: Int, step: Int, oldTimeJson: String, newTimeJson: String) -> (Int, Int) {
        if startNode < 1 || step < 1 { return (startNode, step) }
        let oldRows = TimeTableUtils.parseTimeSlotRows(oldTimeJson).sorted { $0.node < $1.node }
        let newRows = TimeTableUtils.parseTimeSlotRows(newTimeJson).sorted { $0.node < $1.node }
        let oldStart = oldRows.first(where: { $0.node == startNode })?.start ?? ""
        let oldEnd = oldRows.first(where: { $0.node == startNode + step - 1 })?.end ?? ""
        if oldStart.isEmpty || oldEnd.isEmpty { return (startNode, step) }
        guard let firstIdx = newRows.firstIndex(where: { $0.end > oldStart }) else { return (startNode, step) }
        guard let revIdx = newRows.lastIndex(where: { $0.start < oldEnd }) else { return (startNode, step) }
        if revIdx < firstIdx { return (startNode, step) }
        let firstNode = newRows[firstIdx].node
        let lastNode = newRows[revIdx].node
        return (firstNode, max(lastNode - firstNode + 1, 1))
    }

    func deleteTable(_ id: Int64) throws {
        // ★ 删除前先取该表全部课程 id:外键 CASCADE 级联删课程,
        //   删完后这些 id 已不在库里,当天的课前闹钟会残留到点继续响。
        //   因此必须在删除前捕获 id 列表,删除后对这些"孤儿 id"显式取消通知。
        let orphanCourseIds = try writeWithUndo { db in
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM courses WHERE tableId = ?", arguments: [id])
            try TimeTableEntity.deleteOne(db, key: id)
            return ids
        }
        // issue#44: 同步清该表调休映射(UserDefaults 孤儿 key 防残留)
        AppPrefs.shared.clearHolidayTransfers(id)
        if !orphanCourseIds.isEmpty {
            NotificationScheduler.shared.cancelCourseAlarms(courseIds: orphanCourseIds)
        }
        onDataChanged()
    }

    func setDefault(_ id: Int64) throws {
        try tableDao.setDefault(id)
        onDataChanged()
    }

    func tableCount() throws -> Int { try tableDao.count() }

    // ========== PeriodTable (issue#40 独立时间节次表) ==========

    func getAllPeriodTables() throws -> [PeriodTableEntity] { try periodTableDao.getAll() }

    func getPeriodTable(_ id: Int64) throws -> PeriodTableEntity? { try periodTableDao.getById(id) }

    /// 某时间节次表被多少张课程表绑定 — 管理页"已绑定 N 张课表"与删除守卫共用。
    func periodTableBoundCount(_ id: Int64) throws -> Int { try periodTableDao.boundTableCount(id) }

    /// 有效时间节次表解析(设计 §5.1): 绑定表存在 → 返回它; 悬空/未绑定 → nil, 调用方回退旧兼容列。
    func effectivePeriodTable(tableId: Int64) throws -> PeriodTableEntity? {
        guard let table = try tableDao.getById(tableId) else { return nil }
        guard let boundId = table.periodTableId else { return nil }
        return try periodTableDao.getById(boundId)
    }

    /// 甲案 (设计 §4.1): 绑定到指定作息表的全部课表 —
    /// 弹窗"另有 N 张课表绑定"提示 + 三选项作用域语义共用 (tableDao.getAllBoundTo)。
    func getTablesBoundTo(_ periodTableId: Int64) throws -> [TimeTableEntity] {
        try tableDao.getAllBoundTo(periodTableId)
    }

    /// 新建时间节次表, 返回新 id。独立写动作 = 独立撤回单元。
    @discardableResult
    func insertPeriodTable(_ table: PeriodTableEntity) throws -> Int64 {
        var withStamp = table
        if withStamp.createdAt == 0 {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            withStamp.createdAt = now
            withStamp.updatedAt = now
        }
        return try writeWithUndo { db in try periodTableDao.insertInDb(db, withStamp) }
    }

    /// 复制时间节次表(设计 §4.2): 生成新实体, 原表与原绑定关系零改动。返回新副本 id。
    @discardableResult
    func copyPeriodTable(sourceId: Int64) throws -> Int64 {
        try writeWithUndo { db in
            guard let src = try PeriodTableEntity.fetchOne(db, key: sourceId) else { return -1 }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var copy = src
            copy.id = 0
            copy.createdAt = now
            copy.updatedAt = now
            return try periodTableDao.insertInDb(db, copy)
        }
    }

    /// v1.0.56 T8: 按指定名建副本 — 复制弹窗确认后调用, 名字已由 UI 层查重。
    @discardableResult
    func copyPeriodTableAs(sourceId: Int64, newName: String) throws -> Int64 {
        try writeWithUndo { db in
            guard let src = try PeriodTableEntity.fetchOne(db, key: sourceId) else { return -1 }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var copy = src
            copy.id = 0
            copy.name = newName
            copy.createdAt = now
            copy.updatedAt = now
            return try periodTableDao.insertInDb(db, copy)
        }
    }

    /// 绑定/解绑独立作息表: 绑定是单向指针, 不改本课表的兼容列。
    /// 首次绑定存 preBindSnapshotJson; 解绑恢复; 悬空目标拒绝。
    func bindPeriodTable(timeTableId: Int64, periodTableId: Int64?) throws {
        let changed = try writeWithUndo { db -> Bool in
            guard let table = try TimeTableEntity.fetchOne(db, key: timeTableId) else { throw TableEditSaveError.missingTable }
            if let pid = periodTableId, try PeriodTableEntity.fetchOne(db, key: pid) == nil { throw TableEditSaveError.missingPeriodTable }
            if table.periodTableId == periodTableId { return false }
            let next: TimeTableEntity
            if table.periodTableId == nil && periodTableId != nil {
                next = TimeTableEntity.snapshotForBind(table: table, targetId: periodTableId!)
            } else if table.periodTableId != nil && periodTableId == nil {
                next = TimeTableEntity.restoredForUnbind(table: table)
            } else {
                next = { var t = table; t.periodTableId = periodTableId; return t }()
            }
            try next.update(db)
            return true
        }
        if changed { onDataChanged() }
    }

    /// 修改时间节次表内容(设计 §5.2): 更新实体+updatedAt。
    func updatePeriodTable(_ table: PeriodTableEntity) throws {
        var stamped = table
        stamped.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try writeWithUndo { db in try updatePeriodTableWithEdgeMigrationInDb(db, table: stamped) }
        onDataChanged()
    }

    /// 保存独立作息表内容, 返回绑定课表数(供 UI 预览文案)。
    @discardableResult
    func savePeriodTable(_ table: PeriodTableEntity) throws -> Int {
        let bound = try writeWithUndo { db -> Int? in
            guard try PeriodTableEntity.fetchOne(db, key: table.id) != nil else { throw TableEditSaveError.missingPeriodTable }
            let bound = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_tables WHERE periodTableId = ?", arguments: [table.id]) ?? 0
            var stamped = table
            stamped.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try updatePeriodTableWithEdgeMigrationInDb(db, table: stamped)
            return bound
        }
        guard let bound else { return 0 }
        onDataChanged()
        return bound
    }

    /// 显式删除可冻结各绑定表当前作息；旧调用及草稿清理默认保留未绑定守卫。
    @discardableResult
    func deletePeriodTable(_ id: Int64, onlyIfUnbound: Bool = true) throws -> Bool {
        let deleted = try db.dbQueue.write { db -> Bool in
            guard let period = try PeriodTableEntity.fetchOne(db, key: id) else { return false }
            let tables = try TimeTableEntity.fetchAll(db)
            let owners = tables.filter { $0.periodTableId == id }
            if onlyIfUnbound && !owners.isEmpty { return false }
            let snapshot = UndoSnapshot(periodTables: try PeriodTableEntity.fetchAll(db),
                tables: tables, courses: try CourseEntity.fetchAll(db),
                defaultTableId: tables.first(where: { $0.isDefault })?.id)
            for owner in owners {
                var frozen = owner.hydratedWith(period)
                frozen.periodTableId = nil
                frozen.preBindSnapshotJson = ""
                try frozen.update(db)
            }
            try PeriodTableEntity.deleteOne(db, key: id)
            db.afterNextTransaction { _ in
                UndoManager.shared.capture(tables: snapshot.tables, courses: snapshot.courses,
                    defaultTableId: snapshot.defaultTableId, periodTables: snapshot.periodTables)
            }
            return true
        }
        if deleted { onDataChanged() }
        return deleted
    }

    // ========== Course ==========

    func getCourses(_ tableId: Int64) throws -> [CourseEntity] { try courseDao.getByTable(tableId) }

    /// issue#40: 全库课程 — 时间节次表保存预览须统计所有绑定表的课。
    func getAllCourses() throws -> [CourseEntity] { try courseDao.getAllCourses() }

    /// v1.0.62 B1: 全库课程 groupId 去重列表 — recalcAll 用。
    func getAllGroupIds() -> [String] {
        (try? courseDao.getAllCourses())?
            .map { $0.groupId }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } ?? []
    }

    func getCoursesByDay(_ tableId: Int64, day: Int) throws -> [CourseEntity] {
        try courseDao.getByTableAndDay(tableId, day: day)
    }

    func getCourse(_ id: Int64) throws -> CourseEntity? { try courseDao.getById(id) }

    @discardableResult
    func insertCourse(_ course: CourseEntity) throws -> Int64 {
        let id = try writeWithUndo { db in try courseDao.insertInDb(db, course) }
        persistNewGroupColors([course])
        onDataChanged()
        return id
    }

    @discardableResult
    func insertCourses(_ courses: [CourseEntity]) throws -> [Int64] {
        // 导入时以规范化课程名为身份;时间、教师、教室只属于课程的一个时段。
        let (ids, withGroupIds) = try writeWithUndo { db in
            let grouped = try assignGroupIds(courses, in: db)
            return (try courseDao.insertAllInDb(db, grouped), grouped)
        }
        persistNewGroupColors(withGroupIds)
        onDataChanged()
        return ids
    }

    func updateCourse(_ course: CourseEntity) throws {
        try writeWithUndo { db in try course.update(db) }
        onDataChanged()
    }

    /// 单次编辑/删除：预览快照在事务内复核，失败不改数据库、不消费撤销历史。
    /// expectedTable 必须是 hydratedWith 后的有效作息；replacement=nil 只删除这一次。
    @discardableResult
    func saveOccurrence(_ occurrence: CourseOccurrence, replacement: CourseEntity?,
                        expectedCourses: [CourseEntity], expectedTable: TimeTableEntity,
                        expectedTransfers: [HolidayTransferEntry]) throws -> Bool {
        let saved = try db.dbQueue.write { db -> Bool in
            guard let table = try TimeTableEntity.fetchOne(db, key: expectedTable.id),
                  let source = try CourseEntity.fetchOne(db, key: occurrence.course.id),
                  source == occurrence.course, source.tableId == table.id else { return false }
            let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            let effective = table.hydratedWith(period)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard try encoder.encode(effective) == encoder.encode(expectedTable),
                  try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY id", arguments: [table.id])
                    == expectedCourses.sorted(by: { $0.id < $1.id }),
                  AppPrefs.shared.getHolidayTransfers(table.id) == expectedTransfers,
                  let resolved = CourseOccurrences.resolve(course: source, displayDate: occurrence.displayDate,
                                                           table: effective, transfers: expectedTransfers),
                  HolidayTransferOps.dayKey(resolved.sourceDate) == HolidayTransferOps.dayKey(occurrence.sourceDate)
            else { return false }
            let remaining = try CourseOccurrences.without(source, sourceDate: occurrence.sourceDate, startDate: table.startDate)
            var replacement = replacement
            if var row = replacement {
                try CourseOccurrences.validateTime(row, table: effective)
                let parsedFixed = row.fixedDate.flatMap { CourseOccurrences.parseDate($0, calendar: nil) }
                guard row.startWeek == row.endWeek, row.type == 0,
                      let date = parsedFixed ?? CourseOccurrences.date(startDate: table.startDate, week: row.startWeek, day: row.day),
                      let week = CourseOccurrences.week(startDate: table.startDate, date: date), week <= table.maxWeek,
                      week == row.startWeek, CourseOccurrences.day(date) == row.day else {
                    throw CourseOccurrences.ValidationError.invalidDate
                }
                if let fixed = row.fixedDate, CourseOccurrences.parseDate(fixed, calendar: nil) == nil {
                    throw CourseOccurrences.ValidationError.invalidDate
                }
                row.id = remaining.isEmpty ? source.id : 0
                row.tableId = table.id
                row.groupId = source.groupId
                replacement = row
            }
            let tables = try TimeTableEntity.fetchAll(db)
            let snapshot = UndoSnapshot(periodTables: try PeriodTableEntity.fetchAll(db), tables: tables,
                                        courses: try CourseEntity.fetchAll(db), defaultTableId: tables.first(where: { $0.isDefault })?.id)
            try CourseEntity.deleteOne(db, key: source.id)
            for var row in remaining + (replacement.map { [$0] } ?? []) { try row.insert(db) }
            if replacement != nil, !source.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let original = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? AND groupId = ?",
                                                        arguments: [table.id, source.groupId])
                let merged = CourseOccurrences.mergeMatchingRows(original)
                let retained = Set(merged.map { $0.id })
                for row in original where !retained.contains(row.id) { try CourseEntity.deleteOne(db, key: row.id) }
                for row in merged where !original.contains(row) { try row.update(db) }
            }
            // 与共享作息的其它绑定表一起计算引用，回收也属于同一撤销单元。
            let owners = period.map { p in tables.filter { $0.periodTableId == p.id } } ?? [table]
            let ownerIds = Set(owners.map { $0.id })
            let rows = try CourseEntity.fetchAll(db).filter { ownerIds.contains($0.tableId) }
            var used: Set<Int> = []
            for row in rows where row.step > 0 && row.step <= 10_000 && row.startNode <= Int.max - row.step {
                used.formUnion(row.startNode..<(row.startNode + row.step))
                let normalized = row.normalizeNode(timeJson: effective.timeJson)
                if normalized.step > 0, normalized.step <= 10_000, normalized.startNode <= Int.max - normalized.step {
                    used.formUnion(normalized.startNode..<(normalized.startNode + normalized.step))
                }
            }
            let reclaimed = Self.reclaimUnusedEdgeNodes(timeJson: effective.timeJson, usedNodes: used)
            if reclaimed != effective.timeJson {
                if var period { period.timeJson = reclaimed; try period.update(db) }
                else { var next = table; next.timeJson = reclaimed; try next.update(db) }
            }
            db.afterNextTransaction { _ in
                UndoManager.shared.capture(tables: snapshot.tables, courses: snapshot.courses,
                                           defaultTableId: snapshot.defaultTableId, periodTables: snapshot.periodTables)
            }
            return true
        }
        if saved { onDataChanged(); pruneDefaultTopPrefs() }
        return saved
    }

    enum CourseOccurrenceMoveError: LocalizedError {
        case missingCourse
        case invalidOccurrence
        case invalidDestination
        case invalidTime

        var errorDescription: String? {
            switch self {
            case .missingCourse: return "课程已不存在，请刷新课表。"
            case .invalidOccurrence: return "原周次没有该课程，或课程数据已失效。"
            case .invalidDestination: return "目标周次、星期或节次超出课表范围。"
            case .invalidTime: return "课程时间或目标作息无效，无法保留课程时长。"
            }
        }
    }

    /// 仅移动指定周的一次课程。原始行从事务内读取，不能传入调休/归一化后的渲染副本。
    /// 原行最多拆成两个同类型区间，目标另建单周行；同周同位置返回 false，不改撤销历史。
    /// 横移自定义时间课时传 targetStartTime 保留分数行时刻；显式改时刻属于一次真实移动。
    @discardableResult
    func moveCourseOccurrence(courseId: Int64, sourceWeek: Int, targetWeek: Int,
                              targetDay: Int, targetNode: Int, targetStartTime: String? = nil) throws -> Bool {
        let changed = try db.dbQueue.write { db -> Bool in
            guard let source = try CourseEntity.fetchOne(db, key: courseId) else {
                throw CourseOccurrenceMoveError.missingCourse
            }
            guard let table = try TimeTableEntity.fetchOne(db, key: source.tableId),
                  table.maxWeek > 0, sourceWeek >= 1, sourceWeek <= table.maxWeek,
                  source.startWeek >= 1, source.endWeek >= source.startWeek,
                  (0...3).contains(source.type), (1...7).contains(source.day),
                   source.step > 0,
                   (source.fixedDate == nil ? source.inWeek(sourceWeek) : source.fixedDate.flatMap { CourseOccurrences.parseDate($0, calendar: nil) }
                        .flatMap { CourseOccurrences.week(startDate: table.startDate, date: $0) } == sourceWeek) else {
                throw CourseOccurrenceMoveError.invalidOccurrence
            }
            let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            let effective = table.hydratedWith(period)
            guard targetWeek >= 1, targetWeek <= table.maxWeek, (1...7).contains(targetDay) else {
                throw CourseOccurrenceMoveError.invalidDestination
            }
            let destination: CourseOccurrenceDestination
            do {
                destination = try CourseOccurrenceDestination.resolve(source: source, targetNode: targetNode,
                                                                      table: effective, targetStartTime: targetStartTime)
            } catch CourseOccurrenceDestination.ResolutionError.invalidTime {
                throw CourseOccurrenceMoveError.invalidTime
            } catch {
                throw CourseOccurrenceMoveError.invalidDestination
            }
            let sourceNode = source.normalizeNode(timeJson: effective.timeJson).startNode
            let sameTime = targetStartTime == nil
                || TimeTableUtils.hmToSeconds(source.startTime) == TimeTableUtils.hmToSeconds(destination.startTime)
            let sourceDay = source.fixedDate.flatMap { CourseOccurrences.parseDate($0, calendar: nil) }.map { CourseOccurrences.day($0, calendar: nil) } ?? source.day
            if sourceWeek == targetWeek && sourceDay == targetDay && sourceNode == targetNode && sameTime {
                return false
            }

            var moved = source
            moved.id = 0
            moved.startWeek = targetWeek
            moved.endWeek = targetWeek
            moved.type = 0
            moved.day = targetDay
            if source.fixedDate != nil {
                guard let date = CourseOccurrences.date(startDate: table.startDate, week: targetWeek, day: targetDay) else {
                    throw CourseOccurrenceMoveError.invalidDestination
                }
                moved.fixedDate = HolidayTransferOps.dayKey(date)
            }
            moved.startNode = destination.startNode
            moved.isIrregularNode = false // 目标为标准网格节次。
            if destination.usesOwnTime {
                moved.startTime = destination.startTime
                moved.endTime = destination.endTime
            }

            // 在同一事务拍改动前库态；只在实际 COMMIT 后发布快照，失败不清空 undo/redo。
            let tables = try TimeTableEntity.fetchAll(db)
            let snapshot = UndoSnapshot(
                periodTables: try PeriodTableEntity.fetchAll(db), tables: tables,
                courses: try CourseEntity.fetchAll(db), defaultTableId: tables.first(where: { $0.isDefault })?.id)
            var remaining: [CourseEntity] = []
            if source.fixedDate == nil, source.startWeek < sourceWeek,
               let left = Self.occurrenceRange(source, first: source.startWeek, last: sourceWeek - 1) {
                remaining.append(left)
            }
            if source.fixedDate == nil, sourceWeek < source.endWeek,
               let right = Self.occurrenceRange(source, first: sourceWeek + 1, last: source.endWeek) {
                remaining.append(right)
            }
            if let first = remaining.first {
                try first.update(db) // 保留一个剩余区间的原 ID，不影响其它课程行。
                for var extra in remaining.dropFirst() {
                    extra.id = 0
                    try courseDao.insertInDb(db, extra)
                }
            } else {
                try CourseEntity.deleteOne(db, key: source.id)
            }
            try courseDao.insertInDb(db, moved)
            db.afterNextTransaction { _ in
                UndoManager.shared.capture(tables: snapshot.tables, courses: snapshot.courses,
                                           defaultTableId: snapshot.defaultTableId, periodTables: snapshot.periodTables)
            }
            return true
        }
        if changed { onDataChanged() }
        return changed
    }

    /// 保留单双周语义，丢弃只有非上课周的空区间；不把整个学期展开成单周行。
    private static func occurrenceRange(_ course: CourseEntity, first: Int, last: Int) -> CourseEntity? {
        guard first <= last else { return nil }
        if course.type == 1 || course.type == 2 {
            let parity = course.type == 1 ? 1 : 0
            if first == last && first % 2 != parity { return nil }
        }
        var range = course
        range.startWeek = first
        range.endWeek = last
        return range
    }

    /// 查同 groupId 下所有课程(用于编辑回填,按时段分 block)
    func getGroupCourses(_ tableId: Int64, _ groupId: String) throws -> [CourseEntity] {
        try courseDao.getByGroupId(tableId, groupId)
    }

    /// 编辑课程组:原子地删除同 groupId 全部记录并插入新草稿。
    /// 防呆: groupId 空串(早期版本导入的存量数据)禁止走组替换 — 否则 DELETE WHERE groupId=''
    /// 会把该表全部空组课程一起删掉。空组时退化为逐条插入。
    func updateCourseGroup(_ tableId: Int64, _ groupId: String, _ newCourses: [CourseEntity]) throws {
        try writeWithUndo { db in
            if !groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try db.execute(sql: "DELETE FROM courses WHERE tableId = ? AND groupId = ?", arguments: [tableId, groupId])
            }
            _ = try courseDao.insertAllInDb(db, newCourses)
        }
        onDataChanged()
    }

    /// issue#22 行级 diff/patch 落库 ← applyDiff(tableId, diff)
    /// 内部取写前快照，提交后发布；delete → update → insert → 节次回收同一事务。
    func applyDiff(_ tableId: Int64, _ diff: DiffResult) throws {
        try writeWithUndo { db in
            for id in diff.toDelete { try CourseEntity.deleteOne(db, key: id) }
            for course in diff.toUpdate { try course.update(db) }
            _ = try courseDao.insertAllInDb(db, diff.toInsert)
            // issue#23: 编辑删行也要回收，回收失败时一并回滚课程变更。
            if !diff.toDelete.isEmpty { try reclaimUnusedEdgeNodes(tableId, in: db) }
        }
        onDataChanged()
    }

    /// The course editor stages edge slots against the effective schedule it loaded.
    struct CourseTimeChange {
        let expectedPeriodTableId: Int64?
        let originalTimeJson: String
        let updatedTimeJson: String
    }

    /// Course rows and their staged edge slots either commit together or remain a draft.
    func saveCourseDrafts(tableId: Int64, editingGroupId: String?, drafts: [CourseEntity],
                          timeChange: CourseTimeChange? = nil, editingCourseId: Int64? = nil) throws {
        let newGroups = try writeWithUndo { db -> [CourseEntity] in
            guard let table = try TimeTableEntity.fetchOne(db, key: tableId) else { throw TableEditSaveError.missingTable }
            guard drafts.allSatisfy({ $0.tableId == tableId }) else { throw TableEditSaveError.invalidCourseDraft }
            if let editingCourseId {
                guard let source = try CourseEntity.fetchOne(db, key: editingCourseId),
                      source.tableId == tableId, source.groupId == editingGroupId else {
                    throw TableEditSaveError.invalidCourseDraft
                }
            }
            let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            if let change = timeChange {
                guard table.periodTableId == change.expectedPeriodTableId,
                      table.hydratedWith(period).timeJson == change.originalTimeJson else { throw TableEditSaveError.staleTimeTable }
                if table.periodTableId != nil && period == nil { throw TableEditSaveError.missingPeriodTable }
            }
            let inserted: [CourseEntity]
            var deletedRows = false
            if let groupID = editingGroupId {
                guard drafts.allSatisfy({ $0.groupId == groupID }) else { throw TableEditSaveError.invalidCourseDraft }
                let existing = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? AND groupId = ?",
                                                          arguments: [tableId, groupID])
                let diff = RowKeyDiffer.diff(drafts, existing)
                for id in diff.toDelete { try CourseEntity.deleteOne(db, key: id) }
                for course in diff.toUpdate { try course.update(db) }
                _ = try courseDao.insertAllInDb(db, diff.toInsert)
                deletedRows = !diff.toDelete.isEmpty
                inserted = []
            } else {
                inserted = try assignGroupIds(drafts, in: db)
                _ = try courseDao.insertAllInDb(db, inserted)
            }
            if let change = timeChange, change.updatedTimeJson != change.originalTimeJson {
                if var period {
                    period.timeJson = change.updatedTimeJson
                    period.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                    try period.update(db)
                } else {
                    var next = table
                    next.timeJson = change.updatedTimeJson
                    try next.update(db)
                }
            }
            if deletedRows { try reclaimUnusedEdgeNodes(tableId, in: db) }
            return inserted
        }
        persistNewGroupColors(newGroups)
        onDataChanged()
    }

    /// 改组色(issue#22 spec §6.2 "改组色"按钮的落库路径):
    /// 把选中色写到同 groupId 所有 colorMode=GROUP 行的 color 字段。
    ///
    /// 只动 GROUP 行 — AUTO 行 hue 源来自组色源(groupSourceColorHex),组色变则
    /// 自动行跟着变(spec §5.2"组色变则自动跟随"),不需要写;CUSTOM 行独立色不跟组。
    /// 落所有 GROUP 行而非只落最小 id 行:避免 RowKeyDiffer 把未改 GROUP 行 diff 出假更新。
    func setGroupSourceColor(_ tableId: Int64, _ groupId: String, _ hex: String) throws {
        if groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let changed = try writeWithUndo { db -> Bool in
            let group = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? AND groupId = ?",
                                                 arguments: [tableId, groupId])
                .filter { $0.colorMode == CourseColorMode.GROUP }
            for var row in group {
                row.color = hex
                try row.update(db)
            }
            return !group.isEmpty
        }
        if changed { onDataChanged() }
    }

    func deleteCourse(_ id: Int64) throws {
        let changed = try writeWithUndo { db -> Bool in
            guard let course = try CourseEntity.fetchOne(db, key: id) else { return false }
            try CourseEntity.deleteOne(db, key: id)
            try reclaimUnusedEdgeNodes(course.tableId, in: db)
            return true
        }
        guard changed else { return }
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// 删除同 groupId 全部记录。防呆: 空 groupId 拒删(否则整表空组课程全没了)
    func deleteCourseGroup(_ tableId: Int64, _ groupId: String) throws {
        if groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        try writeWithUndo { db in
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ? AND groupId = ?", arguments: [tableId, groupId])
            try reclaimUnusedEdgeNodes(tableId, in: db)
        }
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// issue#23 修: 删课/删组后扫描该表 timeJson, 回收所有无人引用的边缘节次节点。
    /// 在调用方写事务内更新；课程和节点一起回滚/撤回，不叠加中间快照。
    /// NOTE: 原版本 调 TimeTableUtils.reclaimUnusedEdgeNodes; iOS 该工具文件归他人,
    /// 同款算法先落本文件私有静态成员(← TimeTableUtils.kt:624), 集成者可平移。
    private func reclaimUnusedEdgeNodes(_ tableId: Int64, in db: Database) throws {
        guard let table = try TimeTableEntity.fetchOne(db, key: tableId) else { return }
        let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
        let effective = table.hydratedWith(period)
        let owners = try period.map { period in
            try TimeTableEntity.fetchAll(db).filter { $0.periodTableId == period.id }
        } ?? [table]
        let ownerIDs = Set(owners.map(\.id))
        let remaining = try CourseEntity.fetchAll(db).filter { ownerIDs.contains($0.tableId) }
        var used = Set<Int>()
        for c in remaining {
            // Malformed spans cannot safely prove an edge unused.
            guard c.step > 0, c.step <= 10_000, c.startNode <= Int.max - c.step else { return }
            let normalized = c.normalizeNode(timeJson: effective.timeJson)
            guard normalized.step > 0, normalized.step <= 10_000,
                  normalized.startNode <= Int.max - normalized.step else { return }
            used.formUnion(normalized.startNode..<(normalized.startNode + normalized.step))
            // 防御: 存储的 startNode 也算"用户意图", 即便 normalize 后位置不同
            // 也保留节点 — 防止误回收导致课崩。
            used.formUnion(c.startNode..<(c.startNode + c.step))
        }
        let reclaimed = Self.reclaimUnusedEdgeNodes(timeJson: effective.timeJson, usedNodes: used)
        if reclaimed != effective.timeJson {
            if var period {
                period.timeJson = reclaimed
                period.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                try period.update(db)
            } else {
                var next = table
                next.timeJson = reclaimed
                try next.update(db)
            }
        }
    }

    /// 扫描全部边缘节次节点, 逐个回收未被引用的 — from before + after 两个方向。
    /// 标准节点(1..N) 绝不回收(removeEdgeNodeIfUnused 内部有 edgeClass!=nil 硬闸)。
    static func reclaimUnusedEdgeNodes(timeJson: String, usedNodes: Set<Int>) -> String {
        var json = timeJson
        for n in TimeTableUtils.edgeNodesOf(timeJson: json, edgeClass: .before) {
            json = TimeTableUtils.removeEdgeNodeIfUnused(timeJson: json, edgeNode: n, usedNodes: usedNodes)
        }
        for n in TimeTableUtils.edgeNodesOf(timeJson: json, edgeClass: .after) {
            json = TimeTableUtils.removeEdgeNodeIfUnused(timeJson: json, edgeNode: n, usedNodes: usedNodes)
        }
        return json
    }

    func countCourses(_ tableId: Int64) throws -> Int { try courseDao.countByTable(tableId) }

    func totalCourseCount() throws -> Int { try courseDao.totalCount() }

    enum ImportMutationError: LocalizedError {
        case tableMissing, periodMissing
        var errorDescription: String? {
            switch self {
            case .tableMissing: return L10n.t("import_target_missing")
            case .periodMissing: return L10n.t("import_period_missing")
            }
        }
    }

    func replaceImportedTable(_ tableId: Int64, name: String, startDate: String, maxWeek: Int,
                              nodesPerDay: Int, timeJson: String, courses: [CourseEntity], keepGroups: Bool) throws {
        try writeWithUndo { db in
            guard var table = try TimeTableEntity.fetchOne(db, key: tableId) else { throw ImportMutationError.tableMissing }
            table.name = name
            table.startDate = startDate
            if maxWeek > 0 { table.maxWeek = maxWeek }
            if let periodId = table.periodTableId {
                guard var period = try PeriodTableEntity.fetchOne(db, key: periodId) else { throw ImportMutationError.periodMissing }
                period.timeJson = timeJson
                if nodesPerDay > 0 { period.nodesPerDay = nodesPerDay }
                try period.update(db)
            } else {
                table.timeJson = timeJson
                if nodesPerDay > 0 { table.nodesPerDay = nodesPerDay }
            }
            try table.update(db)
            var rows = courses.map { row -> CourseEntity in
                var copy = row; copy.id = 0; copy.tableId = tableId; return copy
            }
            if !keepGroups { rows = try assignGroupIds(rows, in: db) }
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ?", arguments: [tableId])
            _ = try courseDao.insertAllInDb(db, rows)
            _ = CourseColorWriteGlue.persistNewGroupHuesInDb(dbw: db, dao: courseColorDao, entities: rows)
        }
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    func appendImportedCourses(_ tableId: Int64, courses: [CourseEntity], incomingTimeJson: String,
                               requiredNodeCount: Int, keepGroups: Bool) throws {
        try writeWithUndo { db in
            guard var table = try TimeTableEntity.fetchOne(db, key: tableId) else { throw ImportMutationError.tableMissing }
            let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            if table.periodTableId != nil && period == nil { throw ImportMutationError.periodMissing }
            let extended = CourseImportPolicy.timeJsonForAppend(current: period?.timeJson ?? table.timeJson,
                incoming: incomingTimeJson,
                requiredNodes: max(requiredNodeCount, courses.map { $0.startNode + $0.step - 1 }.max() ?? 0),
                bound: period != nil)
            try CourseImportPolicy.requirePeriodCoverage(courses, timeJson: extended)
            let count = TimeTableUtils.parseTimeSlotRows(extended).map(\.node).max() ?? table.nodesPerDay
            if period == nil {
                table.timeJson = extended
                table.nodesPerDay = count
                try table.update(db)
            }
            var rows = courses.map { row -> CourseEntity in
                var copy = row; copy.id = 0; copy.tableId = tableId; return copy
            }
            if !keepGroups { rows = try assignGroupIds(rows, in: db) }
            _ = try courseDao.insertAllInDb(db, rows)
            _ = CourseColorWriteGlue.persistNewGroupHuesInDb(dbw: db, dao: courseColorDao, entities: rows)
        }
        onDataChanged()
    }

    /// Add-course imports use one live database snapshot for conflict filtering,
    /// the optional frozen backup, and the append. A stale preview cannot bypass
    /// a course added by another writer, and a failed append cannot leave a backup.
    @discardableResult
    func appendImportedCoursesWithBackup(_ tableId: Int64, courses: [CourseEntity], incomingTimeJson: String,
                                         requiredNodeCount: Int, keepGroups: Bool, backupOriginal: Bool,
                                         appendConflicts: Bool = false) throws -> Int {
        let added = try writeWithUndo { db -> Int in
            guard var table = try TimeTableEntity.fetchOne(db, key: tableId) else {
                throw ImportMutationError.tableMissing
            }
            let period = try table.periodTableId.flatMap { try PeriodTableEntity.fetchOne(db, key: $0) }
            if table.periodTableId != nil && period == nil { throw ImportMutationError.periodMissing }
            let effective = table.hydratedWith(period)
            let existing = try CourseEntity.fetchAll(db,
                sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY id", arguments: [tableId])
            let incomingEnd = try courses.map { row -> Int in
                guard row.step > 0 else { throw TableEditSaveError.invalidCourseDraft }
                let (end, overflow) = row.startNode.addingReportingOverflow(row.step - 1)
                guard !overflow else { throw TableEditSaveError.invalidCourseDraft }
                return end
            }.max() ?? 0
            let extended = CourseImportPolicy.timeJsonForAppend(current: effective.timeJson,
                incoming: incomingTimeJson, requiredNodes: max(requiredNodeCount, incomingEnd), bound: period != nil)
            let accepted = CourseImportPolicy.selectIncoming(incoming: courses, existing: existing,
                appendConflicts: appendConflicts, timeJson: extended)
            guard !accepted.isEmpty else { return 0 }
            try CourseImportPolicy.requirePeriodCoverage(accepted, timeJson: extended)

            if backupOriginal {
                let names = try String.fetchAll(db, sql: "SELECT name FROM time_tables")
                let periodNames = try String.fetchAll(db, sql: "SELECT name FROM period_tables")
                var backup = effective
                backup.id = 0
                backup.name = TimeTableUtils.suggestUniqueName(L10n.format("import_backup_name", table.name),
                    courseTableNames: names, periodTableNames: periodNames)
                backup.isDefault = false
                backup.reminderEnabled = false
                backup.reminderOverride = nil
                backup.periodTableId = nil
                backup.preBindSnapshotJson = ""
                backup.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
                let backupId = try tableDao.insertInDb(db, backup)
                _ = try courseDao.insertAllInDb(db, existing.map { row in
                    var copy = row
                    copy.id = 0
                    copy.tableId = backupId
                    return copy
                })
            }

            var prepared = accepted
            var groups: [String: String] = [:]
            for index in prepared.indices {
                // Match AddCoursesImport.groupKey for every parser: a selected
                // source group must remain one group after appending. This file
                // also compiles in extensions that do not include the UI helper.
                let source = prepared[index]
                let sourceKey = source.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "name:" + source.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
                        + "|" + source.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
                    : source.groupId
                let newGroup = groups[sourceKey] ?? UUID().uuidString
                groups[sourceKey] = newGroup
                prepared[index].id = 0
                prepared[index].tableId = tableId
                prepared[index].groupId = newGroup
            }
            _ = try courseDao.insertAllInDb(db, prepared)
            _ = CourseColorWriteGlue.persistNewGroupHuesInDb(dbw: db, dao: courseColorDao, entities: prepared)
            let count = TimeTableUtils.parseTimeSlotRows(extended).map(\.node).max() ?? effective.nodesPerDay
            if period == nil {
                table.timeJson = extended
                table.nodesPerDay = count
            }
            table.maxWeek = max(table.maxWeek, accepted.map(\.endWeek).max() ?? table.maxWeek)
            try table.update(db)
            try tableDao.setDefaultInDb(db, tableId)
            return prepared.count
        }
        if added > 0 { onDataChanged() }
        return added
    }

    /// 覆盖式导入(先删后插)
    func replaceCourses(_ tableId: Int64, _ courses: [CourseEntity]) throws {
        let withGroupIds = try writeWithUndo { db in
            // 名册须在覆盖删除之前读取，被覆盖表自身的旧行仍参与认亲。
            let grouped = try assignGroupIds(courses, in: db)
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ?", arguments: [tableId])
            _ = try courseDao.insertAllInDb(db, grouped)
            return grouped
        }
        persistNewGroupColors(withGroupIds)
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// sleepy-v1 (§3.4 契约一): groupId 已由解析端权威生成(按文档内 token 分区),
    /// 落库绕过 assignGroupIds — 否则同名不同 token 的分区会被静默合并, 分区往返被破坏。
    @discardableResult
    func insertCoursesKeepingGroups(_ courses: [CourseEntity]) throws -> [Int64] {
        let ids = try writeWithUndo { db in try courseDao.insertAllInDb(db, courses) }
        onDataChanged()
        return ids
    }

    /// 覆盖式导入(保留解析端 groupId), 配合 insertCoursesKeepingGroups 的 sleepy-v1 路径
    func replaceCoursesKeepingGroups(_ tableId: Int64, _ courses: [CourseEntity]) throws {
        try writeWithUndo { db in
            try db.execute(sql: "DELETE FROM courses WHERE tableId = ?", arguments: [tableId])
            _ = try courseDao.insertAllInDb(db, courses)
        }
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// 数据变更后:刷新所有 widget,并在提醒开启时重排通知。
    /// ★ 修复(继承自 原版本):之前只刷 widget 不重排通知,导致编辑课表后课前提醒仍按旧时间。
    /// ← 原版本: pruneDefaultTopPrefs 不在本回调内, 只在删课/覆盖导入/撤回等
    ///   课程集真正变化的写路径显式调用(6 处), 与 原版本 调用点一一对应。
    private func onDataChanged() {
        onDataChangedHook?()
    }

    /// v7.10.16p: 课程集变化后清理指向已失效课程的置顶偏好 — repId 已删/键已不存在
    /// (锚课被删·簇解体)的条目静默失效还会画出幽灵图层选项, 按现存课全量校验删除。
    /// 删课/删组/覆盖导入/撤销四条写路径都会走到(全部收敛于 onDataChanged)。
    /// 用户报障 2026-09-10: liveKeys 与网格聚簇同一时间域, 偏好不被节点域误删。
    private func pruneDefaultTopPrefs() {
        let stored = AppPrefs.shared.getConflictDefaultTop()
        if stored.isEmpty { return }
        guard let allCourses = try? courseDao.getAllCourses() else { return }
        let timeJson = try? tableDao.getDefault()?.timeJson
        let pruned = ConflictLayoutEngine.pruneConflictDefaultTop(
            stored, allCourses, timeJson: timeJson ?? nil)
        if pruned.count != stored.count {
            AppPrefs.shared.setConflictDefaultTop(pruned)
        }
    }

    // ========== Flow 观察 ← observeAllTables / observeCourses(Room Flow) ==========

    /// Room Flow → GRDB ValueObservation(Combine Publisher)。
    /// 数据库任何写操作后自动 emit 最新列表(表列表/课程列表各自观察)。

    func observeAllTables() -> DatabasePublishers.Value<[TimeTableEntity]> {
        ValueObservation
            .tracking { db in try TimeTableEntity.fetchAll(db, sql: "SELECT * FROM time_tables ORDER BY createdAt DESC") }
            .publisher(in: db.dbQueue)
    }

    func observeCourses(_ tableId: Int64) -> DatabasePublishers.Value<[CourseEntity]> {
        ValueObservation
            .tracking { db in try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? ORDER BY day, startNode, startWeek", arguments: [tableId]) }
            .publisher(in: db.dbQueue)
    }

    /// ← observeTable(id): Flow<TimeTableEntity?> — 单表实时观察(编辑页真源)。
    func observeTable(_ id: Int64) -> DatabasePublishers.Value<TimeTableEntity?> {
        tableDao.observeById(id)
    }

    /// ← observeCoursesByDay(tableId, day): Flow<List<CourseEntity>>
    /// SELECT * FROM courses WHERE tableId = :tableId AND day = :day ORDER BY startNode
    func observeCoursesByDay(tableId: Int64, day: Int) -> DatabasePublishers.Value<[CourseEntity]> {
        ValueObservation
            .tracking { db in try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses WHERE tableId = ? AND day = ? ORDER BY startNode", arguments: [tableId, day]) }
            .publisher(in: db.dbQueue)
    }

    /// ← observeAllPeriodTables(): Flow<List<PeriodTableEntity>> — 管理页列表实时刷新。
    func observeAllPeriodTables() -> DatabasePublishers.Value<[PeriodTableEntity]> {
        periodTableDao.observeAll()
    }

    /// 绑定时间节次表的观察流 — 绑定切换/时间表内容修改都会 emit 新值,
    /// 上游(如 ScheduleViewModel)合并此流实现"立即全部同步"(设计 §5.2)。
    /// ← 原版本 flatMapLatest: tableDao.observeById → periodTableDao.observeById(boundId),
    /// 未绑定 emit nil。★ map + switchToLatest(而非 flatMap): Combine 的 flatMap 是
    /// MERGE 语义 — 解绑后旧 boundId 的内层观察不取消, 其后续变更会"复活"旧作息;
    /// switchToLatest 在绑定时机切换即取消内层, 与 flatMapLatest 一致。
    func observeEffectivePeriodTable(tableId: Int64) -> AnyPublisher<PeriodTableEntity?, Error> {
        tableDao.observeById(tableId)
            .map { table -> AnyPublisher<PeriodTableEntity?, Error> in
                guard let boundId = table?.periodTableId else {
                    return Just<PeriodTableEntity?>(nil)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
                return self.periodTableDao.observeById(boundId).eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// 认亲 + 重写 groupId — ← 原版本 ScheduleRepository.assignGroupIds。
    /// 身份键 = trim + 空白折叠 + 小写(ImportRoster.importNameKey)。
    /// 优先级: 全局名册(同名历史课程) > 该行自带非空 groupId > 新 UUID。
    /// 名册按 id 升序读取全库课程(原版本 knownNameToGroupId(courseDao.getAll()) 的确定性来源)。
    private func assignGroupIds(_ courses: [CourseEntity], in db: Database) throws -> [CourseEntity] {
        let rows = try CourseEntity.fetchAll(db, sql: "SELECT * FROM courses ORDER BY id")
        let roster = ImportRoster.knownNameToGroupId(rows)
        return ImportRoster.normalizedImportGroups(courses, knownNameToGroup: roster)
    }

    /// 新组补持久色相 — ← 原版本 ScheduleRepository.persistNewGroupColors。
    /// 导入/单课新增时同步补色；编辑既有课程组不重排颜色。
    /// 配色是增值数据: 失败一律吞掉降级为不写, 不影响课程落库主流程。
    private func persistNewGroupColors(_ entities: [CourseEntity]) {
        _ = CourseColorWriteGlue.persistNewGroupHues(dao: courseColorDao, entities: entities)
    }
}
