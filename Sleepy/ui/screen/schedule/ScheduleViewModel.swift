// ScheduleViewModel.swift — ← ui/screen/schedule/ScheduleViewModel.kt
// 课表页 VM: 表列表观察 → 选中表课程观察 → 状态派生。
// StateFlow/viewModelScope → @MainActor ObservableObject + Combine sink。

import Foundation
import Combine
import GRDB

struct ScheduleState {
    var tables: [TimeTableEntity] = []
    var selectedTableId: Int64? = nil
    var courses: [CourseEntity] = []
    var currentWeek: Int = 1
    var selectedWeek: Int = 1
    var weekDisplayContext: WeekDisplayContext? = nil
    /// true = 用户手动选周；false = 跟随自动展示周。
    var weekSelectionManual: Bool = false
    /// false=首次加载(本周), true=用户/系统已选定周 — 课程变更时 selectedWeek 不再被重置
    var initialWeekSettled: Bool = false
    var nodesPerDay: Int = 12
    var selectedCourseId: Int64? = nil
    var showCourseDialog: Bool = false
    var error: String? = nil
    /// issue#40: 当前表绑定的独立时间节次表(null=未绑定/悬空, 渲染回退旧兼容列)
    var effectivePeriodTable: PeriodTableEntity? = nil
    /// issue#44: 当前表的调休映射; 切换课表/写盘后由 VM 刷新
    var transfers: [HolidayTransferEntry] = []

    /// 原始行(库内数据, timeJson 兼容列可能过期)
    var currentTable: TimeTableEntity? { tables.first { $0.id == selectedTableId } }

    /// issue#40: 水合后的当前表 — 节次时间域一律从这里读, 不得直接读 currentTable.timeJson
    var effectiveCurrentTable: TimeTableEntity? {
        currentTable.map { $0.hydratedWith(effectivePeriodTable) }
    }

    var currentWeekCourses: [CourseEntity] {
        let list = courses.filter { $0.inWeek(selectedWeek) }
        // issue#40: 节次→时间 的解释真源 = 水合后的 effectiveCurrentTable,
        // 绑定作息表被编辑后立即生效(设计 §5.2 立即全部同步)。
        guard let tj = effectiveCurrentTable?.timeJson else { return list }
        return list.map { $0.normalizeNode(timeJson: tj) }
    }

    /// issue#44: 给定日期实际应"按星期几取课"; 命中映射=targetDate 星期, 未命中=自然星期
    func transferDayFor(_ date: Date) -> Int {
        HolidayTransferOps.effectiveDayOfWeek(date, transfers)
    }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var state = ScheduleState()

    /// issue#40: 全部独立时间节次表(管理页列表) — 实时发布, 库内变化即刷新列表。
    /// ← Android repo.observeAllPeriodTables().stateIn(WhileSubscribed(5000));
    /// GRDB ValueObservation 常驻观察, 语义等价(订阅即推最新值)。
    @Published private(set) var allPeriodTables: [PeriodTableEntity] = []

    private let repo: ScheduleRepository
    /// 数据变更 → 刷 WidgetKit timeline(← WidgetUpdater.notifyDataChanged)
    private let onWidgetsNeedReload: () -> Void

    /// Whether the user has explicitly selected a table (vs auto-picking default on load)
    private var manualSelectDone = false
    private var tablesCancellable: AnyCancellable?
    private var coursesCancellable: AnyCancellable?
    private var periodTablesCancellable: AnyCancellable?

    /// ← coursesJob: 切换表时取消上一个课程观察, 避免多订阅互相覆盖 state.courses
    /// (iOS 侧用单一 coursesCancellable + loadCourses 先 cancel, 同名守卫见 sink 内 tableId 比对)

    /// 甲案 (设计文档 §2.1): 每张课表一个作息编辑会话状态, 按 tableId 缓存。
    /// EditTableScreen 打开时经 editStateFor 拿到; 弹窗/再次保存逻辑全走它。
    /// 表被删除时对应条目一并清理 (见 removeEditState), 避免长会话堆积。
    private var editStates: [Int64: ScheduleEditPolicyState] = [:]

    init(repo: ScheduleRepository, onWidgetsNeedReload: @escaping () -> Void = {}) {
        self.repo = repo
        self.onWidgetsNeedReload = onWidgetsNeedReload
        loadTables()
        observePeriodTables()
    }

    // ← allPeriodTables = observeAllPeriodTables().stateIn(...): 管理页列表实时刷新
    private func observePeriodTables() {
        periodTablesCancellable = repo.observeAllPeriodTables()
            .catch { _ in Just<[PeriodTableEntity]>([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tables in
                self?.allPeriodTables = tables
            }
    }

    // MARK: - 甲案 §2.1 编辑会话 API (← ScheduleViewModel.kt editStates)

    /// 取 (必要时建) 该课表的作息编辑会话状态。
    /// 同会话内视图反复调用返回同一实例 (策略/草稿得以存活)。
    /// 进入编辑页时须走 startEditSession 重建, 保证 original 是"本次进入"的快照。
    func editStateFor(tableId: Int64, originalEffectiveSchedule: PeriodTableEntity?) -> ScheduleEditPolicyState {
        if let existing = editStates[tableId] { return existing }
        let created = ScheduleEditPolicyState(tableId: tableId, originalEffectiveSchedule: originalEffectiveSchedule)
        editStates[tableId] = created
        return created
    }

    /// 开始一次新的编辑会话 (EditTableScreen 每次进入调用一次, 按 tableId keyed):
    /// originalEffectiveSchedule = 进入编辑时刻的实际生效作息快照
    /// (绑定 → 水合源 periodTable; 未绑定 → null)。旧会话残留策略一并作废。
    @discardableResult
    func startEditSession(tableId: Int64, originalEffectiveSchedule: PeriodTableEntity?) -> ScheduleEditPolicyState {
        let session = ScheduleEditPolicyState(tableId: tableId, originalEffectiveSchedule: originalEffectiveSchedule)
        editStates[tableId] = session
        return session
    }

    /// 该课表当前是否有已登记未执行的策略 (UI 待执行提醒 banner 依据)。
    func hasPendingPolicy(tableId: Int64) -> Bool {
        guard let policy = editStates[tableId]?.pendingSchedulePolicy else { return false }
        return policy != .none
    }

    /// 表删除/退出编辑时清理会话状态, 防止跨会话残留策略。
    func removeEditState(tableId: Int64) {
        editStates.removeValue(forKey: tableId)
    }

    /// 甲案 §4.1: 弹窗"另有 N 张课表绑定"提示 — 绑定到指定作息表的课表数。
    func repoTablesBoundToCount(periodTableId: Int64) -> Int {
        return ((try? repo.getTablesBoundTo(periodTableId)) ?? []).count
    }

    /// 甲案 (设计文档 §3.1-§3.3, §3.5): 执行已登记的作息策略 + 完成普通保存。
    /// 三选项共用同一份草稿源 (§3.4) = 用户编辑后的 draftEffectiveSchedule。
    /// 全程 UndoManager 批内 = 单撤回单元(§7: 绑定关系+作息内容一次回退)。
    /// 策略执行完清 pendingSchedulePolicy — 下次保存不再弹窗(invariant ④)。
    ///
    /// - Parameters:
    ///   - editedTable: 普通字段(名称/日期/周次)+本表节次兼容列写值, 由 UI 层构建
    ///   - onFinish: 普通保存(策略写库)完成后的 UI 回调(导航返回)
    func executePolicyAndSave(
        tableId: Int64,
        editedTable: TimeTableEntity,
        newTimeJson: String,
        smartConfigJson: String,
        nodesPerDay: Int,
        onFinish: @escaping () -> Void = {}
    ) {
        guard let editState = editStates[tableId] else { return }
        let policy = editState.pendingSchedulePolicy
        guard let draft = editState.draftEffectiveSchedule, policy != .none else { return }
        Task {
            UndoManager.shared.beginBatch()
            defer { UndoManager.shared.endBatch() }
            guard let current = try? repo.getTable(tableId) else { return }
            switch policy {
            case .detachCopy:
                // ① 写本表内置作息(兼容列) + 解绑; X 与其他绑定课表零改动
                // bindPeriodTable 内部走 restoredForUnbind 会把兼容列回滚到旧快照,
                // 所以先 updateTable 写入新内置作息, 再解绑会把快照值覆盖回去 —
                // 顺序必须反过来: 先解绑(恢复快照)再写内置列(草稿), 写入在最后保赢。
                try? repo.bindPeriodTable(timeTableId: tableId, periodTableId: nil)
                var detached = editedTable
                detached.periodTableId = nil
                detached.timeJson = newTimeJson
                detached.smartConfigJson = smartConfigJson
                detached.nodesPerDay = nodesPerDay
                try? repo.updateTableRemappingCourses(detached)
            case .createNew:
                // ② 按课表名新建独立作息表(全局唯一名顺延, §3.2) + 改绑; X 零改动
                let newId = insertPeriodTableWithUniqueName(
                    name: current.name,
                    defaultName: current.name,
                    timeJson: newTimeJson,
                    nodesPerDay: nodesPerDay,
                    smartConfigJson: smartConfigJson
                )
                guard newId > 0 else { return }   // insert 失败 = 整个策略中止(不动绑定)
                try? repo.bindPeriodTable(timeTableId: tableId, periodTableId: newId)
                var rebound = editedTable
                rebound.periodTableId = newId
                try? repo.updateTableRemappingCourses(rebound)
            case .sync:
                // ③ 写回共享作息表 X, 保持绑定; 全部绑定课表读到新作息
                if let boundId = current.periodTableId {
                    var synced = draft
                    synced.id = boundId
                    synced.timeJson = newTimeJson
                    synced.smartConfigJson = smartConfigJson
                    synced.nodesPerDay = nodesPerDay
                    try? repo.updatePeriodTable(synced)
                    try? repo.updateTable(editedTable)
                }
            case .none:
                break // unreachable — 前置 guard 已拦截
            }
            editState.selectPolicy(.none)
            onFinish()
        }
    }

    // ← loadTables: observeAllTables → 选表逻辑
    private func loadTables() {
        tablesCancellable = repo.observeAllTables()
            .catch { _ in Just<[TimeTableEntity]>([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tables in
                guard let self = self else { return }
                if tables.isEmpty {
                    // 没有课表就老实空着,不强行造占位表
                    self.state.tables = []
                    self.state.selectedTableId = nil
                    self.state.weekDisplayContext = nil
                    self.state.weekSelectionManual = false
                    return
                }
                let selectedId = self.state.selectedTableId
                let targetId: Int64
                if self.manualSelectDone, let selectedId = selectedId,
                   tables.contains(where: { $0.id == selectedId }) {
                    targetId = selectedId
                } else if let def = tables.first(where: { $0.isDefault }) {
                    targetId = def.id
                } else {
                    targetId = tables[0].id
                }
                self.state.tables = tables
                self.state.selectedTableId = targetId
                self.loadCourses(targetId)
            }
    }

    // ← loadCourses: 取消旧观察,避免多 observeCourses 同时写 state.courses 互相覆盖
    private func loadCourses(_ tableId: Int64) {
        coursesCancellable?.cancel()
        // issue#44: 拉一次该表调休映射; 设置页改完走 refreshTransfer 主动刷
        state.transfers = AppPrefs.shared.getHolidayTransfers(tableId)
        // issue#40: 课程流与绑定时间节次表流合并 — 时间节次表改动会 emit 新值,
        // 所有绑定课表立即按新作息解释节次(设计 §5.2 立即全部同步), 课程行不重算
        coursesCancellable = Publishers.CombineLatest(
            repo.observeCourses(tableId)
                .catch { _ in Just<[CourseEntity]>([]) },
            repo.observeEffectivePeriodTable(tableId: tableId)
                .catch { _ in Just<PeriodTableEntity?>(nil) }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] courses, periodTable in
            guard let self = self else { return }
            let rawTable = self.state.tables.first { $0.id == tableId }
            // 水合: 绑定存在时 nodesPerDay/timeJson/smartConfigJson 以时间节次表为准
            let table = rawTable.map { $0.hydratedWith(periodTable) }
            let displayContext = table.map {
                WeekDisplayResolver.resolve(
                    startDate: $0.startDate,
                    maxWeek: $0.maxWeek,
                    now: Date(),
                    courses: courses,
                    timeJson: $0.timeJson,
                    enabled: AppPrefs.shared.isNearestBusyDay()
                )
            }
            let week = displayContext?.actualWeek ?? 1
            // v7.10.16s: 只更新真实周(currentWeek, 供"回到本周"), 不再重置 selectedWeek —
            // 用户在第 x 周编辑/删课, 保存回来仍停在 x 周(此前被拽回真实周=跳回第一周体验)。
            // 首次加载(initial=true)仍落目标周, 保持原行为
            self.state.courses = courses
            self.state.currentWeek = week
            self.state.selectedWeek = self.weekForNextTick(week: week, targetWeek: displayContext?.targetWeek)
            self.state.weekDisplayContext = displayContext
            self.state.initialWeekSettled = true
            self.state.nodesPerDay = table?.nodesPerDay ?? 12
            self.state.effectivePeriodTable = periodTable
            // 课程数据变更后刷新所有 widget
            self.onWidgetsNeedReload()
        }
    }

    /// ← Android when { !initialWeekSettled -> targetWeek ?: week
    ///                  !weekSelectionManual -> targetWeek ?: week
    ///                  else -> selectedWeek }
    private func weekForNextTick(week: Int, targetWeek: Int?) -> Int {
        if !state.initialWeekSettled || !state.weekSelectionManual {
            return targetWeek ?? week
        }
        return state.selectedWeek
    }

    // ← selectTable: 切表 + setDefault(小组件严格跟随 App 当前选中表)
    func selectTable(_ id: Int64) {
        manualSelectDone = true
        // 切表 = 新学期语境, 周选择回到该表真实周(initialWeekSettled 复位, loadCourses 重新落周)
        state.selectedTableId = id
        state.initialWeekSettled = false
        state.weekSelectionManual = false
        state.weekDisplayContext = nil
        loadCourses(id)
        Task {
            try? repo.setDefault(id)
            onWidgetsNeedReload()
        }
    }

    /// v7.10.16 撤回最近一次数据改动(导入/加课/编辑/删课/删表/建表...)。
    /// 返回 false = 没有可撤回的操作(调用方 toast 提示)。
    @discardableResult
    func undoLastChange() -> Bool {
        let ok = (try? repo.restoreLastSnapshot()) ?? false
        if ok {
            manualSelectDone = false   // 恢复后选中态交回 default 表
            onWidgetsNeedReload()
        }
        return ok
    }

    /// 2026-09-21 用户令: 取消最近一次撤回(单级 redo)。
    /// 返回 false = 没有可取消的撤回(调用方 toast 提示)。
    @discardableResult
    func redoLastUndo() -> Bool {
        let ok = (try? repo.redoLastUndo()) ?? false
        if ok {
            manualSelectDone = false   // 恢复后选中态交回 default 表(与 undo 同语义)
            onWidgetsNeedReload()
        }
        return ok
    }

    /// Create a new empty table with auto-generated name. ← createEmptyTable
    /// - Parameter commitSelection: true=立刻切到新表; false=只插入不切(调用方回滚/后切)
    @discardableResult
    func createEmptyTable(commitSelection: Bool = true) -> Int64 {
        let existingNames = Set(state.tables.map { $0.name })
        var index = state.tables.count + 1
        var name = L10n.format("default_table_with_num", index)
        while existingNames.contains(name) {
            index += 1
            name = L10n.format("default_table_with_num", index)
        }
        // 上周一(本周一往前 7 天 — iOS weekday 数学)
        let cal = DateUtils.isoCalendar
        let now = Date()
        let todayDow = DateUtils.todayDayOfWeek(today: now)
        let lastWeekMonday = cal.date(byAdding: .day, value: -(todayDow - 1 + 7), to: now) ?? now
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = DateUtils.isoCalendar.timeZone
        // 没有任何表时,新表自动 isDefault = true,避免"无默认表"
        let isFirstTable = state.tables.isEmpty
        let table = TimeTableEntity(
            name: name,
            startDate: f.string(from: lastWeekMonday),
            isDefault: isFirstTable)
        let id = (try? repo.insertTable(table)) ?? 0
        if isFirstTable {
            // 数据库侧 isDefault 唯一性保证
            try? repo.setDefault(id)
        }
        // observeAllTables 在 receive(on: DispatchQueue.main) 后异步回调。
        // 先同步补入内存状态,让立即打开的 EditTableScreen 能解析新表。
        if id != 0, !state.tables.contains(where: { $0.id == id }) {
            var insertedTable = table
            insertedTable.id = id
            state.tables.append(insertedTable)
        }
        if commitSelection {
            manualSelectDone = true
            state.selectedTableId = id
            loadCourses(id)
        }
        onWidgetsNeedReload()
        return id
    }

    func updateTable(_ table: TimeTableEntity) {
        Task { try? repo.updateTable(table) }
    }

    /// v7.10.15 创建课表副本 — 全量复制表配置+课程, 新副本不接管默认表也不切选中,
    /// 命名沿用导入路径的去重规则(原名+"2"/"3"...)。
    func duplicateTable(_ id: Int64) {
        Task {
            guard let source = try? repo.getTable(id) else { return }
            let courses = (try? repo.getCourses(id)) ?? []
            let existingNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
            var index = 2
            var name = "\(source.name)2"
            while existingNames.contains(name) { index += 1; name = "\(source.name)\(index)" }
            var copy = source
            copy.id = 0
            copy.name = name
            copy.isDefault = false
            copy.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            // v7.10.16w: 建表+插课是一个撤回动作 — beginBatch 保首快照, 撤回一次整步回退
            // (此前两步写两次覆盖快照, 撤回只删掉课程行留下空表壳)。
            UndoManager.shared.beginBatch()
            defer { UndoManager.shared.endBatch() }
            let newId = (try? repo.insertTable(copy)) ?? 0
            if newId != 0 && !courses.isEmpty {
                // groupId 整组映射到新 UUID — 同一门课的节次共享新组 ID, 副本内仍可整组编辑
                var groupMap: [String: String] = [:]
                for c in courses where groupMap[c.groupId] == nil {
                    groupMap[c.groupId] = UUID().uuidString
                }
                let newCourses = courses.map { c -> CourseEntity in
                    var n = c
                    n.id = 0
                    n.groupId = groupMap[c.groupId] ?? c.groupId
                    n.tableId = newId
                    return n
                }
                try? repo.insertCourses(newCourses)
            }
            onWidgetsNeedReload()
        }
    }

    func deleteTable(_ id: Int64) {
        editStates.removeValue(forKey: id)
        Task {
            try? repo.deleteTable(id)
            self.manualSelectDone = false
        }
    }

    /// Discard a newly-created table that was never saved. ← discardNewTable
    func discardNewTable(_ newId: Int64, fallbackId: Int64?) {
        editStates.removeValue(forKey: newId)
        Task {
            try? self.repo.deleteTable(newId)
            self.manualSelectDone = false
            let remaining = ((try? self.repo.getAllTables()) ?? []).filter { $0.id != newId }
            let targetId: Int64?
            if let fallbackId = fallbackId, remaining.contains(where: { $0.id == fallbackId }) {
                targetId = fallbackId
            } else if let def = remaining.first(where: { $0.isDefault }) {
                targetId = def.id
            } else {
                targetId = remaining.first?.id
            }
            if let targetId = targetId {
                self.selectTable(targetId)
            }
        }
    }

    func changeWeek(_ week: Int) {
        // 防呆: 下限 1, 上限 maxWeek — 之前只有下限, 右箭头可以无限翻出学期范围外
        let maxWeek = state.currentTable?.maxWeek ?? 20
        guard week >= 1, week <= maxWeek else { return }
        // 甲案语境: 用户手动翻周 = 停止自动跟随 targetWeek
        state.selectedWeek = week
        state.weekSelectionManual = true
    }

    /// issue#44: 设置页保存调休映射后, 通知 VM 重新拉当前表的映射。
    /// 现有 courses 列表不需重查, 只需刷新 dayFor() 的真源, 一次 reload 即生效。
    func refreshTransfer() {
        guard let id = state.selectedTableId else { return }
        state.transfers = AppPrefs.shared.getHolidayTransfers(id)
    }

    /// ← recalculateWeekDisplay (Android): 外部语境变化(如回到本周)后重算展示周。
    /// weekSelectionManual=true 时保留用户所选周, 否则跟随 targetWeek。
    func recalculateWeekDisplay() {
        guard let table = state.effectiveCurrentTable else { return }
        let context = WeekDisplayResolver.resolve(
            startDate: table.startDate,
            maxWeek: table.maxWeek,
            now: Date(),
            courses: state.courses,
            timeJson: table.timeJson,
            enabled: AppPrefs.shared.isNearestBusyDay()
        )
        let selected = state.weekSelectionManual ? state.selectedWeek : context.targetWeek
        state.currentWeek = context.actualWeek
        state.weekDisplayContext = context
        state.selectedWeek = selected
    }

    func openCourse(_ id: Int64) {
        state.selectedCourseId = id
        state.showCourseDialog = true
    }

    func dismissCourseDialog() {
        state.showCourseDialog = false
    }

    // ← addEmptyCourse: 没课表就先生成一张,再加课
    func addEmptyCourse() {
        let tableId = state.selectedTableId ?? createEmptyTable()
        let empty = CourseEntity(
            groupId: UUID().uuidString,
            tableId: tableId,
            courseName: L10n.format("new_course"),
            teacher: "",
            room: "",
            day: DateUtils.todayDayOfWeek(),
            startNode: 1,
            step: 1,
            startWeek: state.currentWeek,
            endWeek: state.currentWeek + 16,
            color: "#FF6750A4")
        let id = (try? repo.insertCourse(empty)) ?? 0
        openCourse(id)
    }

    func updateCourse(_ course: CourseEntity) {
        Task { try? repo.updateCourse(course) }
    }

    func deleteCourse(_ id: Int64) {
        Task {
            try? repo.deleteCourse(id)
            self.dismissCourseDialog()
        }
    }
}

// MARK: - PeriodTable 面 (issue#40 / v1.0.56 T7-T9, ← ScheduleViewModel.kt L297-497)

extension ScheduleViewModel {

    /// 全部作息表(管理页列表)。
    /// ← Android allPeriodTables.value (ScheduleViewModel.kt L77 StateFlow):
    /// 返回实时发布缓存, 库内变化后调用方读到最新值(§5.2 立即全部同步)。
    /// 冷启动首次 emit 未到达时缓存为空 → 回落一次同步读库, 防止调用方拿到假空列表。
    func loadAllPeriodTables() -> [PeriodTableEntity] {
        if !allPeriodTables.isEmpty { return allPeriodTables }
        return (try? repo.getAllPeriodTables()) ?? []
    }

    /// 复制作息表预填名 — 原名参与全局唯一名顺延, 原名本身不占位。nil = 源不存在。
    func suggestPeriodTableCopyName(sourceId: Int64) -> String? {
        guard let src = (try? repo.getAllPeriodTables())?.first(where: { $0.id == sourceId }) else { return nil }
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        return TimeTableUtils.suggestUniqueName(src.name, courseTableNames: courseNames, periodTableNames: periodNames)
    }

    /// 按用户确认的名字建副本。返回新副本 id; 源不存在 -1; 撞名 -2。
    func copyPeriodTableAs(sourceId: Int64, newName: String) -> Int64 {
        guard let src = try? repo.getPeriodTable(sourceId) else { return -1 }
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        if !newName.isBlank,
           TimeTableUtils.isTableNameTaken(newName, courseTableNames: courseNames, periodTableNames: periodNames) {
            return -2
        }
        let finalName = newName.isBlank ? src.name : newName
        return (try? repo.copyPeriodTableAs(sourceId: sourceId, newName: finalName)) ?? -1
    }

    /// 新建空白时间节次表(创建即落库, 编辑页把它当"未保存新表"处理)。
    @discardableResult
    func insertPeriodTable(
        name: String,
        timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON,
        nodesPerDay: Int = 12,
        smartConfigJson: String = ""
    ) -> Int64 {
        let entity = PeriodTableEntity(
            name: name, nodesPerDay: nodesPerDay,
            timeJson: timeJson, smartConfigJson: smartConfigJson
        )
        return (try? repo.insertPeriodTable(entity)) ?? -1
    }

    /// 新建作息表(自动唯一命名) — 全局唯一名顺延, 空名走默认名。
    @discardableResult
    func insertPeriodTableWithUniqueName(
        name: String,
        defaultName: String,
        timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON,
        nodesPerDay: Int = 12,
        smartConfigJson: String = ""
    ) -> Int64 {
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        let unique = TimeTableUtils.suggestUniqueName(
            name, courseTableNames: courseNames, periodTableNames: periodNames, defaultName: defaultName
        )
        return insertPeriodTable(name: unique, timeJson: timeJson, nodesPerDay: nodesPerDay, smartConfigJson: smartConfigJson)
    }

    /// issue#40: 修改共享时间节次表内容 — 全部绑定课表立即生效, 课程行零改动(← Android updatePeriodTableContent)
    /// repo.savePeriodTable 是同步方法; 行为与 updateTable 保持一致 — 在 fire-and-forget Task 内执行,
    /// 失败吞(→ repo update 抛错时上层按 updateTable 同语义吞掉, 数据层不会半写)。
    func updatePeriodTableContent(_ table: PeriodTableEntity) {
        Task { try? repo.savePeriodTable(table) }
    }

    /// issue#40: 换绑课程表的时间节次表(只写 periodTableId, 课程行零改动)
    func bindPeriodTable(timeTableId: Int64, periodTableId: Int64?) {
        Task { try? repo.bindPeriodTable(timeTableId: timeTableId, periodTableId: periodTableId) }
    }

    /// issue#40: 复制时间节次表, 返回新副本 id (-1 = 源不存在)
    @discardableResult
    func copyPeriodTable(sourceId: Int64) -> Int64 {
        return (try? repo.copyPeriodTable(sourceId: sourceId)) ?? -1
    }

    /// 2026-09-23 症状3修复: 仅写课程表元数据, 不动绑定关系。
    func updateTableMetadata(_ table: TimeTableEntity, writeTimeDomain: Bool = false) {
        Task { try? repo.updateTableMetadata(table, writeTimeDomain: writeTimeDomain) }
    }

    /// 2026-09-23 症状3修复: 元数据 + 共享作息表内容, 单事务原子双写。
    func updateTableMetadataWithPeriodTable(table: TimeTableEntity, periodTable: PeriodTableEntity) {
        Task { try? repo.updateTableMetadataWithPeriodTable(table: table, periodTable: periodTable) }
    }

    /// 2026-09-23 症状3修复: 元数据 + 换绑/解绑(+目标作息表内容), 单事务原子完成。
    func updateTableMetadataAndBind(
        table: TimeTableEntity,
        periodTableId: Int64?,
        periodContent: PeriodTableEntity? = nil
    ) {
        Task { try? repo.updateTableMetadataAndBind(table: table, periodTableId: periodTableId, periodContent: periodContent) }
    }

    /// issue#28 P3: 保存课表编辑 — timeJson 变更时课程节次按绝对时间自适应
    func updateTableRemappingCourses(_ table: TimeTableEntity) {
        Task { try? repo.updateTableRemappingCourses(table) }
    }

    /// 删除时间节次表(被引用时 false, UI 提示先改绑)。
    @discardableResult
    func deletePeriodTable(id: Int64) -> Bool {
        return (try? repo.deletePeriodTable(id)) ?? false
    }

    /// 丢弃一个从未保存过的新建时间节次表(残留清理; 不走删除守卫)。
    func discardNewPeriodTable(id: Int64) {
        _ = try? repo.deletePeriodTable(id)
    }

    /// issue#40: 全库课程(保存预览用) — 预览须覆盖所有绑定表的课。
    func getAllCoursesOnce() -> [CourseEntity] {
        return (try? repo.getAllCourses()) ?? []
    }

    /// v1.0.56 T9: 全局唯一名预填用 — 课表名 + 作息表名。
    func getAllTableNamesOnce() -> [String] {
        return ((try? repo.getAllTables()) ?? []).map { $0.name }
    }
    func getAllPeriodTableNamesOnce() -> [String] {
        return ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
    }
}
