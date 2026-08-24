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
    var nodesPerDay: Int = 12
    var selectedCourseId: Int64? = nil
    var showCourseDialog: Bool = false
    var error: String? = nil

    var currentTable: TimeTableEntity? { tables.first { $0.id == selectedTableId } }

    var currentWeekCourses: [CourseEntity] {
        let list = courses.filter { $0.inWeek(selectedWeek) }
        guard let tj = currentTable?.timeJson else { return list }
        return list.map { $0.normalizeNode(timeJson: tj) }
    }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var state = ScheduleState()

    private let repo: ScheduleRepository
    /// 数据变更 → 刷 WidgetKit timeline(← WidgetUpdater.notifyDataChanged)
    private let onWidgetsNeedReload: () -> Void

    /// Whether the user has explicitly selected a table (vs auto-picking default on load)
    private var manualSelectDone = false
    private var tablesCancellable: AnyCancellable?
    private var coursesCancellable: AnyCancellable?

    init(repo: ScheduleRepository, onWidgetsNeedReload: @escaping () -> Void = {}) {
        self.repo = repo
        self.onWidgetsNeedReload = onWidgetsNeedReload
        loadTables()
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
        coursesCancellable = repo.observeCourses(tableId)
            .catch { _ in Just<[CourseEntity]>([]) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courses in
                guard let self = self else { return }
                let table = self.state.tables.first { $0.id == tableId }
                let week = table.map { DateUtils.currentWeek(startDate: $0.startDate) } ?? 1
                self.state.courses = courses
                self.state.currentWeek = week
                self.state.selectedWeek = week
                self.state.nodesPerDay = table?.nodesPerDay ?? 12
                // 课程数据变更后刷新所有 widget
                self.onWidgetsNeedReload()
            }
    }

    // ← selectTable: 切表 + setDefault(小组件严格跟随 App 当前选中表)
    func selectTable(_ id: Int64) {
        manualSelectDone = true
        state.selectedTableId = id
        loadCourses(id)
        Task {
            try? repo.setDefault(id)
            onWidgetsNeedReload()
        }
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

    func deleteTable(_ id: Int64) {
        Task {
            try? repo.deleteTable(id)
            self.manualSelectDone = false
        }
    }

    /// Discard a newly-created table that was never saved. ← discardNewTable
    func discardNewTable(_ newId: Int64, fallbackId: Int64?) {
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
        guard week >= 1 else { return }
        state.selectedWeek = week
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
