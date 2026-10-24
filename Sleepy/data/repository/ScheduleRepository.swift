// ScheduleRepository.swift — ← ScheduleRepository.kt
// 课表仓库 — 业务数据访问的唯一入口。
//
// UI 层只调这个类,不直接碰 DAO。
// (Flow → AsyncStream/Combine 视调用方需要;先落 suspend 等价 = 同步 throws)

import Foundation
import Combine
import GRDB

final class ScheduleRepository {
    private let db: AppDatabase
    private let courseDao: CourseDao
    private let tableDao: TimeTableDao
    /// ← SleepyApp.get().notificationScheduler / WidgetUpdater
    /// iOS: 数据变更回调(由 App 壳注入: 刷 WidgetKit timeline + 重排 UNNotification)
    var onDataChangedHook: (() -> Void)?

    init(_ db: AppDatabase) {
        self.db = db
        self.courseDao = db.courseDao
        self.tableDao = db.timeTableDao
        self.periodTableDao = PeriodTableDao(db: db.dbQueue)
    }

    // ========== v7.10.16 单级撤回 + 2026-09-21 单级 redo ==========

    var canUndo: Bool { UndoManager.shared.hasSnapshot }
    var canRedo: Bool { UndoManager.shared.hasRedoSnapshot }

    /// 公开写方法执行前调用 — 拍下改动前的全库状态。
    /// 复合动作(如导入)入口先 UndoManager.shared.beginBatch(), 批内只保首个快照=动作前时点。
    /// issue#40: 快照须含 period_tables — 否则撤回任何作息写无法恢复作息表内容。
    private func captureForUndo() throws {
        UndoManager.shared.capture(
            tables: try tableDao.getAll(),
            courses: try courseDao.getAllCourses(),
            defaultTableId: try tableDao.getDefault()?.id,
            periodTables: try periodTableDao.getAll()
        )
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
        guard let undoSnap = UndoManager.shared.poll() else { return false }
        // 把"撤回前"库态(=当前库态)落入 redo 槽, 用户点 redo 时再恢复回去。
        let redoSnap = try snapshotCurrent()
        UndoManager.shared.restoring = true
        defer { UndoManager.shared.restoring = false }
        try applySnapshot(undoSnap)
        UndoManager.shared.recordRedo(redoSnap)
        onDataChanged()
        pruneDefaultTopPrefs()
        return true
    }

    /// 取消最近一次撤回: redo 槽快照恢复回库, undo 槽收回当前库态。false = 无可取消。
    @discardableResult
    func redoLastUndo() throws -> Bool {
        guard let redoSnap = UndoManager.shared.pollRedo() else { return false }
        let undoSnap = try snapshotCurrent()
        UndoManager.shared.restoring = true
        defer { UndoManager.shared.restoring = false }
        try applySnapshot(redoSnap)
        // 把"刚恢复到的 redo 起点之前那一刻"重新填回 undo 槽,
        // 用户再次点撤回应能回到"被我们撤回来的那次修改之前的库态"。
        UndoManager.shared.reinsertForRedoSymmetry(undoSnap)
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
        try captureForUndo()
        let id = try tableDao.insert(table)
        let count = try tableDao.count()
        if table.isDefault || count == 1 {
            try tableDao.setDefault(id)
        }
        return id
    }

    func updateTable(_ table: TimeTableEntity) throws {
        try captureForUndo()
        try tableDao.update(table)
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
        guard let current = try tableDao.getById(table.id) else { return }
        try captureForUndo()
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
        if changed { try tableDao.update(merged) }
        onDataChanged()
    }

    /// 2026-09-23 症状3修复: 编辑课表保存 — 元数据 + 共享作息表内容, 单事务原子双写。
    ///
    /// 场景: 课表绑定共享作息表, 用户改了名字/日期/周次且同时改了节次内容;
    /// 两条独立写(updateTable + updatePeriodTableContent)顺序不保证, 撤回快照
    /// 也可能只拍到一半。本方法一次快照一次事务同时落两行, 要么都成要么都不成。
    func updateTableMetadataWithPeriodTable(table: TimeTableEntity, periodTable: PeriodTableEntity) throws {
        guard let current = try tableDao.getById(table.id) else { return }
        guard try periodTableDao.getById(periodTable.id) != nil else { return }
        try captureForUndo()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try db.dbQueue.write { db in
            var next = current
            next.name = table.name
            next.startDate = table.startDate
            next.maxWeek = table.maxWeek
            try next.update(db)
            var stamped = periodTable
            stamped.updatedAt = now
            try stamped.update(db)
        }
        onDataChanged()
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
        guard let current = try tableDao.getById(table.id) else { return }
        if let pid = periodTableId, try periodTableDao.getById(pid) == nil { return }
        if let pc = periodContent, try periodTableDao.getById(pc.id) == nil { return }
        if current.periodTableId == periodTableId && periodContent == nil {
            // 绑定关系与目标内容都没变 — 退化为纯元数据写; 解绑态写时间域(兼容列即真值)
            try updateTableMetadata(table, writeTimeDomain: periodTableId == nil)
            return
        }
        try captureForUndo()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try db.dbQueue.write { db in
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
            try merged.update(db)
            if let pc = periodContent {
                var stamped = pc
                stamped.updatedAt = now
                try stamped.update(db)
            }
        }
        onDataChanged()
    }

    /// issue#28 P3: 编辑课表保存 — timeJson 变更时课程按绝对时间自适应新节次。
    ///
    /// 节次编号语义 = "该节在新表上的钟点", 表变了编号必须跟着变, 否则改完 16→12 节
    /// 课程还停在 13-16 节。ownTime 课自带绝对时间(timeToNode 直接定位), 普通课按
    /// remapCourseNodes 重排; 无法映射的课保持原节次。与 updateTable 同为单动作
    /// 撤回单元(首快照 = 改表前)。
    func updateTableRemappingCourses(_ table: TimeTableEntity) throws {
        try captureForUndo()
        let oldJson = try tableDao.getById(table.id)?.timeJson ?? ""
        try tableDao.update(table)
        if table.timeJson != oldJson {
            let courses = try courseDao.getByTable(table.id)
            let remapped = courses.map { c -> CourseEntity in
                if c.ownTime {
                    if let mapped = TimeTableUtils.timeToNode(c.startTime, c.endTime, table.timeJson) {
                        var copy = c
                        copy.startNode = mapped.0
                        copy.step = mapped.1
                        return copy
                    }
                    return c
                } else {
                    let (node, step) = Self.remapCourseNodes(
                        startNode: c.startNode, step: c.step,
                        oldTimeJson: oldJson, newTimeJson: table.timeJson
                    )
                    if node == c.startNode && step == c.step { return c }
                    var copy = c
                    copy.startNode = node
                    copy.step = step
                    return copy
                }
            }
            let changed = zip(remapped, courses).filter { $0.0.id != $0.1.id || $0.0.startNode != $0.1.startNode || $0.0.step != $0.1.step }
                .map { $0.0 }
            if !changed.isEmpty { try courseDao.updateAll(changed) }
        }
        onDataChanged()
    }

    /// issue#28 P3: 作息表变更后的课程节次自适应(← Android TimeTableUtils.remapCourseNodes)。
    ///
    /// 节次编号只是旧表绝对时间窗的载体: 取课程首节在旧表的 start 与末节在旧表的
    /// end, 在新表上找与之重叠的节点区间 — 首节 = 第一个 end 晚于课程起点的节,
    /// 末节 = 最后一个 start 早于课程终点的节。旧表缺行(课程锚的节次不存在)或
    /// 新表无任何重叠 → 返回原值(孤儿课保持原节次, 不猜不丢)。
    /// NOTE: Android 侧此函数归属 TimeTableUtils; iOS 先落本文件私有静态成员,
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
        try captureForUndo()
        let orphanCourseIds = try courseDao.getByTable(id).map { $0.id }
        try tableDao.deleteById(id)
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

    /// ← Android: 三 DAO 同源 db — init 注入 dbQueue, 禁自取单例
    /// (测试/多库实例注入时观察流与写路径必须指向同一队列)。
    private let periodTableDao: PeriodTableDao

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
    /// 弹窗"另有 N 张课表绑定"提示 + 三选项作用域语义共用 (← Android tableDao.getAllBoundTo)。
    func getTablesBoundTo(_ periodTableId: Int64) throws -> [TimeTableEntity] {
        try tableDao.getAllBoundTo(periodTableId)
    }

    /// 新建时间节次表, 返回新 id。独立写动作 = 独立撤回单元。
    @discardableResult
    func insertPeriodTable(_ table: PeriodTableEntity) throws -> Int64 {
        try captureForUndo()
        var withStamp = table
        if withStamp.createdAt == 0 {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            withStamp.createdAt = now
            withStamp.updatedAt = now
        }
        return try periodTableDao.insert(withStamp)
    }

    /// 复制时间节次表(设计 §4.2): 生成新实体, 原表与原绑定关系零改动。返回新副本 id。
    @discardableResult
    func copyPeriodTable(sourceId: Int64) throws -> Int64 {
        guard let src = try periodTableDao.getById(sourceId) else { return -1 }
        try captureForUndo()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var copy = src
        copy.id = 0
        copy.createdAt = now
        copy.updatedAt = now
        return try periodTableDao.insert(copy)
    }

    /// v1.0.56 T8: 按指定名建副本 — 复制弹窗确认后调用, 名字已由 UI 层查重。
    @discardableResult
    func copyPeriodTableAs(sourceId: Int64, newName: String) throws -> Int64 {
        guard let src = try periodTableDao.getById(sourceId) else { return -1 }
        try captureForUndo()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var copy = src
        copy.id = 0
        copy.name = newName
        copy.createdAt = now
        copy.updatedAt = now
        return try periodTableDao.insert(copy)
    }

    /// 绑定/解绑独立作息表: 绑定是单向指针, 不改本课表的兼容列。
    /// 首次绑定存 preBindSnapshotJson; 解绑恢复; 悬空目标拒绝。
    func bindPeriodTable(timeTableId: Int64, periodTableId: Int64?) throws {
        guard let table = try tableDao.getById(timeTableId) else { return }
        if let pid = periodTableId, try periodTableDao.getById(pid) == nil { return }
        if table.periodTableId == periodTableId { return }
        try captureForUndo()
        let next: TimeTableEntity
        if table.periodTableId == nil && periodTableId != nil {
            next = TimeTableEntity.snapshotForBind(table: table, targetId: periodTableId!)
        } else if table.periodTableId != nil && periodTableId == nil {
            next = TimeTableEntity.restoredForUnbind(table: table)
        } else {
            next = { var t = table; t.periodTableId = periodTableId; return t }()
        }
        // ← Android db.withTransaction { tableDao.update(next) } — 单语句包事务,
        //   与 Room 事务语义一致(GRDB 禁重入: 事务内直接 entity.update(db))
        try db.dbQueue.write { db in try next.update(db) }
        onDataChanged()
    }

    /// 修改时间节次表内容(设计 §5.2): 更新实体+updatedAt。
    func updatePeriodTable(_ table: PeriodTableEntity) throws {
        try captureForUndo()
        var stamped = table
        stamped.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try periodTableDao.update(stamped)
        onDataChanged()
    }

    /// 保存独立作息表内容, 返回绑定课表数(供 UI 预览文案)。
    @discardableResult
    func savePeriodTable(_ table: PeriodTableEntity) throws -> Int {
        guard try periodTableDao.getById(table.id) != nil else { return 0 }
        try captureForUndo()
        let bound = try periodTableDao.boundTableCount(table.id)
        var stamped = table
        stamped.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try periodTableDao.update(stamped)
        onDataChanged()
        return bound
    }

    /// 删除守卫(设计 §7): 被引用的时间节次表禁止删除, 无绑定才真删。
    @discardableResult
    func deletePeriodTable(_ id: Int64) throws -> Bool {
        if try periodTableDao.boundTableCount(id) > 0 { return false }
        try captureForUndo()
        try periodTableDao.deleteById(id)
        onDataChanged()
        return true
    }

    // ========== Course ==========

    func getCourses(_ tableId: Int64) throws -> [CourseEntity] { try courseDao.getByTable(tableId) }

    /// issue#40: 全库课程 — 时间节次表保存预览须统计所有绑定表的课。
    func getAllCourses() throws -> [CourseEntity] { try courseDao.getAllCourses() }

    func getCoursesByDay(_ tableId: Int64, day: Int) throws -> [CourseEntity] {
        try courseDao.getByTableAndDay(tableId, day: day)
    }

    func getCourse(_ id: Int64) throws -> CourseEntity? { try courseDao.getById(id) }

    @discardableResult
    func insertCourse(_ course: CourseEntity) throws -> Int64 {
        try captureForUndo()
        let id = try courseDao.insert(course)
        onDataChanged()
        return id
    }

    @discardableResult
    func insertCourses(_ courses: [CourseEntity]) throws -> [Int64] {
        // 导入时以规范化课程名为身份;时间、教师、教室只属于课程的一个时段。
        try captureForUndo()
        let withGroupIds = assignGroupIds(courses)
        let ids = try courseDao.insertAll(withGroupIds)
        onDataChanged()
        return ids
    }

    func updateCourse(_ course: CourseEntity) throws {
        try captureForUndo()
        try courseDao.update(course)
        onDataChanged()
    }

    /// 查同 groupId 下所有课程(用于编辑回填,按时段分 block)
    func getGroupCourses(_ tableId: Int64, _ groupId: String) throws -> [CourseEntity] {
        try courseDao.getByGroupId(tableId, groupId)
    }

    /// 编辑课程组:原子地删除同 groupId 全部记录并插入新草稿(DAO 层事务)。
    /// 防呆: groupId 空串(早期版本导入的存量数据)禁止走组替换 — 否则 DELETE WHERE groupId=''
    /// 会把该表全部空组课程一起删掉。空组时退化为逐条插入。
    func updateCourseGroup(_ tableId: Int64, _ groupId: String, _ newCourses: [CourseEntity]) throws {
        try captureForUndo()
        if groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try courseDao.insertAll(newCourses)
            onDataChanged()
            return
        }
        try courseDao.replaceGroup(tableId: tableId, groupId: groupId, newCourses: newCourses)
        onDataChanged()
    }

    /// issue#22 行级 diff/patch 落库 ← applyDiff(tableId, diff)
    /// Android 注释要求"调用前必须已 captureForUndo";iOS 侧 captureForUndo 是 private,
    /// 这里改为内部捕获(功能等价:撤销快照仍在写库前生成)。顺序 delete → update → insert。
    func applyDiff(_ tableId: Int64, _ diff: DiffResult) throws {
        try captureForUndo()
        if !diff.toDelete.isEmpty { try courseDao.deleteByIds(diff.toDelete) }
        if !diff.toUpdate.isEmpty { try courseDao.updateAll(diff.toUpdate) }
        if !diff.toInsert.isEmpty { try courseDao.insertAll(diff.toInsert) }
        // issue#23 修: 编辑删行也要回收(否则编辑掉 edge 上的 block 后节点残留)
        if !diff.toDelete.isEmpty { try reclaimUnusedEdgeNodes(tableId) }
        onDataChanged()
    }

    /// 改组色(issue#22 spec §6.2 "改组色"按钮的落库路径):
    /// 把选中色写到同 groupId 所有 colorMode=GROUP 行的 color 字段。
    ///
    /// 只动 GROUP 行 — AUTO 行 hue 源来自组色源(groupSourceColorHex),组色变则
    /// 自动行跟着变(spec §5.2"组色变则自动跟随"),不需要写;CUSTOM 行独立色不跟组。
    /// 落所有 GROUP 行而非只落最小 id 行:避免 RowKeyDiffer 把未改 GROUP 行 diff 出假更新。
    func setGroupSourceColor(_ tableId: Int64, _ groupId: String, _ hex: String) throws {
        try captureForUndo()
        if groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let group = try courseDao.getByGroupId(tableId, groupId)
            .filter { $0.colorMode == CourseColorMode.GROUP }
        if group.isEmpty { return }
        var rows = group
        for i in rows.indices { rows[i].color = hex }
        try courseDao.updateAll(rows)
        onDataChanged()
    }

    func deleteCourse(_ id: Int64) throws {
        try captureForUndo()
        guard let course = try courseDao.getById(id) else { return }
        try courseDao.deleteById(id)
        try reclaimUnusedEdgeNodes(course.tableId)
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// 删除同 groupId 全部记录。防呆: 空 groupId 拒删(否则整表空组课程全没了)
    func deleteCourseGroup(_ tableId: Int64, _ groupId: String) throws {
        try captureForUndo()
        if groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        try courseDao.deleteByGroupId(tableId, groupId)
        try reclaimUnusedEdgeNodes(tableId)
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// issue#23 修: 删课/删组后扫描该表 timeJson, 回收所有无人引用的边缘节次节点。
    /// 直接走 tableDao.update 绕过 updateTable 的 captureForUndo — 撤回时上层
    /// (deleteCourse 等)已捕获了"删前完整快照(含完整 timeJson)", 撤回 = 回到删前,
    /// 课程和节点都复原, 此处不应再叠加中间快照。
    /// NOTE: Android 调 TimeTableUtils.reclaimUnusedEdgeNodes; iOS 该工具文件归他人,
    /// 同款算法先落本文件私有静态成员(← TimeTableUtils.kt:624), 集成者可平移。
    private func reclaimUnusedEdgeNodes(_ tableId: Int64) throws {
        guard let table = try tableDao.getById(tableId) else { return }
        let remaining = try courseDao.getByTable(tableId)
        var used = Set<Int>()
        for c in remaining {
            let effStart: Int
            if c.ownTime, let mapped = TimeTableUtils.timeToNode(c.startTime, c.endTime, table.timeJson) {
                effStart = mapped.0
            } else {
                effStart = c.startNode
            }
            let end = max(effStart + c.step - 1, effStart)
            for n in effStart...end { used.insert(n) }
            // 防御: 存储的 startNode 也算"用户意图", 即便 normalize 后位置不同
            // 也保留节点 — 防止误回收导致课崩。
            let storedEnd = max(c.startNode + c.step - 1, c.startNode)
            for n in c.startNode...storedEnd { used.insert(n) }
        }
        let reclaimed = Self.reclaimUnusedEdgeNodes(timeJson: table.timeJson, usedNodes: used)
        if reclaimed != table.timeJson {
            var next = table
            next.timeJson = reclaimed
            try tableDao.update(next)
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

    /// 覆盖式导入(先删后插)
    func replaceCourses(_ tableId: Int64, _ courses: [CourseEntity]) throws {
        try captureForUndo()
        let withGroupIds = assignGroupIds(courses)
        try courseDao.replaceAll(tableId: tableId, courses: withGroupIds)
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// sleepy-v1 (§3.4 契约一): groupId 已由解析端权威生成(按文档内 token 分区),
    /// 落库绕过 assignGroupIds — 否则同名不同 token 的分区会被静默合并, 分区往返被破坏。
    @discardableResult
    func insertCoursesKeepingGroups(_ courses: [CourseEntity]) throws -> [Int64] {
        try captureForUndo()
        let ids = try courseDao.insertAll(courses)
        onDataChanged()
        return ids
    }

    /// 覆盖式导入(保留解析端 groupId), 配合 insertCoursesKeepingGroups 的 sleepy-v1 路径
    func replaceCoursesKeepingGroups(_ tableId: Int64, _ courses: [CourseEntity]) throws {
        try captureForUndo()
        try courseDao.replaceAll(tableId: tableId, courses: courses)
        onDataChanged()
        pruneDefaultTopPrefs()
    }

    /// 数据变更后:刷新所有 widget,并在提醒开启时重排通知。
    /// ★ 修复(继承自 Android):之前只刷 widget 不重排通知,导致编辑课表后课前提醒仍按旧时间。
    /// ← Android: pruneDefaultTopPrefs 不在本回调内, 只在删课/覆盖导入/撤回等
    ///   课程集真正变化的写路径显式调用(6 处), 与 Android 调用点一一对应。
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
    /// ← Android flatMapLatest: tableDao.observeById → periodTableDao.observeById(boundId),
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

    private func assignGroupIds(_ courses: [CourseEntity]) -> [CourseEntity] {
        var nameToGroupId: [String: String] = [:]
        return courses.map { c in
            // ← courseName.trim().replace(Regex("\\s+"), " ").lowercase()
            let key = c.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .lowercased()
            let gid: String
            if let existing = nameToGroupId[key] {
                gid = existing
            } else {
                let newGid = !c.groupId.isEmpty ? c.groupId : UUID().uuidString
                nameToGroupId[key] = newGid
                gid = newGid
            }
            var copy = c
            copy.groupId = gid
            return copy
        }
    }
}
