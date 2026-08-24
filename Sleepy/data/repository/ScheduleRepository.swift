// ScheduleRepository.swift — ← ScheduleRepository.kt
// 课表仓库 — 业务数据访问的唯一入口。
//
// UI 层只调这个类,不直接碰 DAO。
// (Flow → AsyncStream/Combine 视调用方需要;先落 suspend 等价 = 同步 throws)

import Foundation
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
    }

    // ========== TimeTable ==========

    func getAllTables() throws -> [TimeTableEntity] { try tableDao.getAll() }

    func getTable(_ id: Int64) throws -> TimeTableEntity? { try tableDao.getById(id) }

    func getDefaultTable() throws -> TimeTableEntity? { try tableDao.getDefault() }

    @discardableResult
    func insertTable(_ table: TimeTableEntity) throws -> Int64 {
        let id = try tableDao.insert(table)
        let count = try tableDao.count()
        if table.isDefault || count == 1 {
            try tableDao.setDefault(id)
        }
        return id
    }

    func updateTable(_ table: TimeTableEntity) throws {
        try tableDao.update(table)
        onDataChanged()
    }

    func deleteTable(_ id: Int64) throws {
        // ★ 删除前先取该表全部课程 id:外键 CASCADE 级联删课程,
        //   删完后这些 id 已不在库里,当天的课前闹钟会残留到点继续响。
        //   因此必须在删除前捕获 id 列表,删除后对这些"孤儿 id"显式取消通知。
        let orphanCourseIds = try courseDao.getByTable(id).map { $0.id }
        try tableDao.deleteById(id)
        if !orphanCourseIds.isEmpty {
            NotificationScheduler.shared.cancelCourseNotifications(orphanCourseIds)
        }
        onDataChanged()
    }

    func setDefault(_ id: Int64) throws {
        try tableDao.setDefault(id)
        onDataChanged()
    }

    func tableCount() throws -> Int { try tableDao.count() }

    // ========== Course ==========

    func getCourses(_ tableId: Int64) throws -> [CourseEntity] { try courseDao.getByTable(tableId) }

    func getCoursesByDay(_ tableId: Int64, day: Int) throws -> [CourseEntity] {
        try courseDao.getByTableAndDay(tableId, day: day)
    }

    func getCourse(_ id: Int64) throws -> CourseEntity? { try courseDao.getById(id) }

    @discardableResult
    func insertCourse(_ course: CourseEntity) throws -> Int64 {
        let id = try courseDao.insert(course)
        onDataChanged()
        return id
    }

    @discardableResult
    func insertCourses(_ courses: [CourseEntity]) throws -> [Int64] {
        // 导入时以规范化课程名为身份;时间、教师、教室只属于课程的一个时段。
        let withGroupIds = assignGroupIds(courses)
        let ids = try courseDao.insertAll(withGroupIds)
        onDataChanged()
        return ids
    }

    func updateCourse(_ course: CourseEntity) throws {
        try courseDao.update(course)
        onDataChanged()
    }

    /// 查同 groupId 下所有课程(用于编辑回填,按时段分 block)
    func getGroupCourses(_ tableId: Int64, _ groupId: String) throws -> [CourseEntity] {
        try courseDao.getByGroupId(tableId, groupId)
    }

    /// 编辑课程组:原子地删除同 groupId 全部记录并插入新草稿(DAO 层事务)
    func updateCourseGroup(_ tableId: Int64, _ groupId: String, _ newCourses: [CourseEntity]) throws {
        try courseDao.replaceGroup(tableId: tableId, groupId: groupId, newCourses: newCourses)
        onDataChanged()
    }

    func deleteCourse(_ id: Int64) throws {
        try courseDao.deleteById(id)
        onDataChanged()
    }

    /// 删除同 groupId 全部记录
    func deleteCourseGroup(_ tableId: Int64, _ groupId: String) throws {
        try courseDao.deleteByGroupId(tableId, groupId)
        onDataChanged()
    }

    func countCourses(_ tableId: Int64) throws -> Int { try courseDao.countByTable(tableId) }

    func totalCourseCount() throws -> Int { try courseDao.totalCount() }

    /// 覆盖式导入(先删后插)
    func replaceCourses(_ tableId: Int64, _ courses: [CourseEntity]) throws {
        let withGroupIds = assignGroupIds(courses)
        try courseDao.replaceAll(tableId: tableId, courses: withGroupIds)
        onDataChanged()
    }

    /// 数据变更后:刷新所有 widget,并在提醒开启时重排通知。
    /// ★ 修复(继承自 Android):之前只刷 widget 不重排通知,导致编辑课表后课前提醒仍按旧时间。
    private func onDataChanged() {
        onDataChangedHook?()
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
