// SystemCalendarManager.swift — 系统日历导入引擎 (v1.0.61 对齐, ← 原版本 SystemCalendarManager.kt 441L, 行为对齐非逐行翻译)
//
// 平台映射:
// - 内容库 ContentProvider 写系统日历 → EventKit EKEventStore (系统 framework, 无新 SPM 依赖)
// - WRITE/READ_CALENDAR 权限 → EKEventStore.requestAccess(to: .event);
//   16.4 SDK 无 .fullAccess/.writeOnly 分支, 授权即 authorizationStatus == .authorized
// - 可写日历 = allowsContentModifications && type != .local/.calDAV (ACCESS_LEVEL >= CONTRIBUTOR && VISIBLE, 16.4 无 isSelectable)
// - v1.0.62 B6: writableCalendars 改走 LocalCalendarFallback — 可写日历为空时
//   ensureCalendar 兜底自建「Sleepy」本地日历(LocalCalendarFallback);
//   自建日历恒纳入可写列表, 否则兜底产物永远选不中
// - 记录 eventId ← 内容库 _ID(Long) → EKCalendarItem.externalIdentifier (String)
// - 描述行尾 marker "Sleepy import key: tableId:courseId:yyyy-MM-dd" 保留(存 EKCalendarItem.notes),
//   记录丢失后可按 marker 恢复, 对齐 原版本 findEventByMarker
// - 原版本 "ALARM(闹钟)" 提醒 → iOS 16.4 EKAlarm 无 type/soundName(.audio/.display 均不可用),
//   提醒恒以 EKAlarm(relativeOffset:) 写入、系统默认提醒呈现; 期望的 method(ALARM/ALERT) 由我方记录
//   alarmRequested 字段承载, 读回(readReminder)恒分类为 .alert。alarmFallback 计数对齐 原版本 语义:
//   原版本 仅在 METHOD_ALARM 插入失败且 METHOD_ALERT 兜底插入成功时计数; iOS EKAlarm 为单阶段写入、
//   不存在两阶段兜底 → 写入成功即视为期望 method 生效(insertReminder(method) 成功分支),
//   写入失败返回 nil 计 errors(两阶段均失败分支)。成功路径 alarmFallback 不增长, 与原实现一致。
// - 事件时区 EKEvent 无公开 API → 指纹恒以 TimeZone.current.identifier 固定(与 原版本 ZoneId.systemDefault().id 同位)
// - EventKit 无"导入历史"原生概念 → 仓内 CalendarImportRecordDao/Entity (calendar_import_records 表) 承担记录职责
// - v1.0.62 B6 调休口径(SystemCalendarManager.kt v1.0.62):
//   导入日期范围纳入调休目标日(源日在学期内的 targetDate 可把区间撑出学期末);
//   事件内容按源日(courseDateForDate/coursesForDate — 放假日无课、补班日上源日的课),
//   显示与闹钟按目标日(事件落位在 targetDate 当天)。

import EventKit
import Foundation
import CryptoKit

// MARK: - 选项 / 预览 / 结果 (与 原 data class 同名同字段)

/// 日历导入范围枚举 (CalendarImportRange enum)
enum CalendarImportRange: String, CaseIterable, Identifiable {
    case NEXT_WEEK = "NEXT_WEEK"
    case NEXT_MONTH = "NEXT_MONTH"
    case SEMESTER = "SEMESTER"
    var id: String { rawValue }
}

/// 可写日历信息 (SystemCalendarInfo data class)
struct SystemCalendarInfo: Identifiable {
    let id: String          // EKCalendar.calendarIdentifier
    let displayName: String // EKCalendar.title
    let accountName: String // EKCalendar.source.title
}

struct CalendarImportOptions {
    /// 目标 EKCalendar.calendarIdentifier (calendarId: Long, 平台映射)
    var calendarId: String
    /// 导入范围
    var range: CalendarImportRange
    var applyHolidayTransfers: Bool
    /// 普通提醒提前分钟; nil = 不加普通提醒 (reminderMinutes: Int?)
    var reminderMinutes: Int?
    var firstPeriodAlarmEnabled: Bool
    /// 首次课强制提醒提前分钟 (firstPeriodAlarmMinutes)
    var firstPeriodAlarmMinutes: Int

    init(
        calendarId: String,
        range: CalendarImportRange = .NEXT_WEEK,
        applyHolidayTransfers: Bool = false,
        reminderMinutes: Int? = nil,
        firstPeriodAlarmEnabled: Bool = false,
        firstPeriodAlarmMinutes: Int = 60
    ) {
        self.calendarId = calendarId
        self.range = range
        self.applyHolidayTransfers = applyHolidayTransfers
        self.reminderMinutes = reminderMinutes
        self.firstPeriodAlarmEnabled = firstPeriodAlarmEnabled
        self.firstPeriodAlarmMinutes = firstPeriodAlarmMinutes
    }
}

enum CalendarImportError: Error { case permissionDenied, noWritableCalendar }

/// ← 原版本 CalendarImportPreviewRow (UI 预览行, 与 CalendarPreviewRow 同构)
typealias CalendarImportPreviewRow = CalendarPreviewRow

struct CalendarPreviewRow {
    var date: Date
    var startHHmm: String
    var endHHmm: String
    var courseName: String
    var teacher: String
    var room: String
    var week: Int
    var transferred: Bool
    var firstPeriodAlarm: Bool

    /// UI convenience: display start time
    var start: String { startHHmm }
    /// UI convenience: display end time
    var end: String { endHHmm }
}

struct CalendarImportPreview {
    var rows: [CalendarPreviewRow]
    var skippedInvalidTime: Int
    var from: Date
    var until: Date
}

struct CalendarImportResult {
    var inserted: Int = 0
    var updated: Int = 0
    var unchanged: Int = 0
    var skippedEdited: Int = 0
    var skippedInvalidTime: Int = 0
    /// ← 原版本 imported.alarmFallback: 仅当期望闹钟(.alarm)但闹钟提醒未能按期望生效时计数。
    /// 平台裁决: iOS EKAlarm 单阶段写入无两阶段兜底 → 写入成功即视为期望 method 生效, 成功路径不计数;
    /// 计数保留给未来的真实兜底场景(当前 16.4 恒为 0, 语义与 原版本 成功路径一致)。
    var alarmFallback: Int = 0
    var errors: Int = 0
}

final class SystemCalendarManager {

    static let shared = SystemCalendarManager()

    let store = EKEventStore()
    private let markerPrefix = "Sleepy import key:"

    // v1.0.62 B6 ← 原版本 localCalendarFallback: 可写日历走兜底策略(空则自建「Sleepy」本地日历)
    private static let fallback = LocalCalendarFallback()
    /// 与 shared.store 同实例 — 自建日历创建后立即可见可写
    private static let eventKitStore = EventKitLocalCalendarStore(store: shared.store)

    enum ReminderMethod: String, Comparable {
        case alert, alarm
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct ReminderDesc { var method: ReminderMethod; var minutes: Int }

    struct EventSpec {
        var course: CourseEntity
        var date: Date
        var week: Int
        var start: Date
        var end: Date
        /// 节次时间字符串 (HH:mm), 供预览行展示 — spec.start/end 是当日零点起算的 Date, 无法直接反解
        var startHHmm: String
        var endHHmm: String
        var description: String
        var key: String
        var reminderMinutes: Int?
        /// 首次课且早间课 (wantsAlarm)
        var wantsAlarm: Bool
    }

    // MARK: - 权限 / 日历发现

    /// ← 原 hasCalendarPermissions (iOS 16.4: 静态 authorizationStatus, 授权即 .authorized)
    func hasCalendarPermissions() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    /// 未授权时弹一次授权; 用户拒绝/未决 = false
    @MainActor
    func ensureCalendarPermissions() async -> Bool {
        if hasCalendarPermissions() { return true }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// ← 原版本 findWritableCalendar: 可写(AccessLevel>=CONTRIBUTOR & VISIBLE) && 非 calDAV
    /// (16.4 无 isSelectable; 平台等价 = allowsContentModifications 且排除 .local/.calDAV 源)
    /// 排序对齐 原 `ORDER BY IS_PRIMARY DESC, CALENDAR_DISPLAY_NAME COLLATE NOCASE`:
    /// EKCalendar 无 isPrimary API → defaultCalendarForNewEvents 作为 primary 代理恒排首位,
    /// 其余按 title  localizedCaseInsensitive 比较(← COLLATE NOCASE)。
    /// displayName = title.isBlank ? accountName : title (displayName.ifBlank { accountName }, 含纯空白)
    ///
    /// v1.0.62 B6 ← 原版本 writableCalendars(context): 改走 LocalCalendarFallback —
    /// 可写日历为空时 ensureCalendar 兜底自建「Sleepy」本地日历; 查询失败整体回落空列表。
    static func writableCalendars() async -> [SystemCalendarInfo] {
        await fallback.writable(store: eventKitStore)
    }

    /// ← 原版本 ensureLocalCalendar(context): 无可写日历时自建本地日历(幂等, 串行化)。
    static func ensureLocalCalendar() async -> SystemCalendarInfo? {
        await fallback.ensure(store: eventKitStore)
    }

    // MARK: - 日期区间 (selectedDateRange, 公式逐一对齐)

    /// v1.0.62 B6 ← 原版本: 导入日期范围纳入调休目标日 — 源日在学期内的 targetDate
    /// 可把 effectiveEnd 撑出学期末, 也可把 start 提前到学期初之前(补班日早于开学)。
    static func selectedDateRange(
        table: TimeTableEntity,
        range: CalendarImportRange,
        today: Date,
        transfers: [HolidayTransferEntry] = []
    ) -> (start: Date, end: Date) {
        let cal = CourseOccurrences.calendar
        let today = cal.startOfDay(for: today)
        let tableStart = CourseOccurrences.parseDate(table.startDate) ?? today
        let semesterStart = cal.date(byAdding: .day, value: 1 - CourseOccurrences.day(tableStart), to: tableStart) ?? tableStart
        let semesterEnd = cal.date(byAdding: .day, value: 7 * table.maxWeek, to: semesterStart) ?? semesterStart
        // ← 原版本 validTargets: 源日仍在学期内的映射才参与区间扩展
        let validTargets = transfers
            .filter {
                guard let week = CourseOccurrences.week(startDate: table.startDate, date: $0.sourceDate) else { return false }
                return week <= table.maxWeek
            }
            .map { cal.startOfDay(for: $0.targetDate) }
        // ← 原 effectiveEnd = maxOf(semesterEnd, validTargets.max()?.plusDays(1) ?: semesterEnd)
        let effectiveEnd = max(semesterEnd, validTargets.max().flatMap { cal.date(byAdding: .day, value: 1, to: $0) } ?? semesterEnd)
        // ← 原 start = maxOf(today, minOf(semesterStart, validTargets.min() ?: semesterStart))
        let rangeStart = validTargets.min().map { min(semesterStart, $0) } ?? semesterStart
        let start = max(today, rangeStart)
        let requestedEnd: Date
        switch range {
        case .NEXT_MONTH: requestedEnd = cal.date(byAdding: .month, value: 1, to: today) ?? today
        case .SEMESTER: requestedEnd = effectiveEnd
        case .NEXT_WEEK: requestedEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today
        }
        return (start, min(requestedEnd, effectiveEnd))
    }

    // MARK: - 预览

    /// ← 原版本 buildPreview(table, courses, options, today) — today 可注入, 默认当前日期 (today: LocalDate = LocalDate.now())
    static func buildPreview(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        today: Date = Date()
    ) -> CalendarImportPreview {
        // ← 原版本: 区间扩展用与事件展开同一份调休映射(applyHolidayTransfers 闸门一致)
        let transfers = options.applyHolidayTransfers ? AppPrefs.shared.getHolidayTransfers(table.id) : []
        let (from, until) = selectedDateRange(table: table, range: options.range, today: today, transfers: transfers)
        let (specs, invalid) = shared.buildEventSpecs(table: table, courses: courses, options: options, from: from, until: until)
        let alarmKeys = shared.firstPeriodAlarmKeys(specs)
        let rows = specs.map { spec -> CalendarPreviewRow in
            CalendarPreviewRow(
                date: spec.date,
                startHHmm: spec.startHHmm,
                endHHmm: spec.endHHmm,
                courseName: spec.course.courseName,
                teacher: spec.course.teacher,
                room: spec.course.room,
                week: spec.week,
                transferred: spec.description.contains("调课安排："),
                firstPeriodAlarm: alarmKeys[spec.date] == spec.key
            )
        }
        return CalendarImportPreview(rows: rows, skippedInvalidTime: invalid, from: from, until: until)
    }

    /// 生成事件 spec (buildEventSpecs: 逐日 调课映射 + 周过滤 + 节次→时间 + marker 描述)
    func buildEventSpecs(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        from: Date,
        until: Date
    ) -> (specs: [EventSpec], invalid: Int) {
        var invalid = 0
        var specs: [EventSpec] = []
        guard from < until else { return ([], 0) }
        let transfers = options.applyHolidayTransfers
            ? AppPrefs.shared.getHolidayTransfers(table.id)
            : []
        let calendar = CourseOccurrences.calendar
        var day = calendar.startOfDay(for: from)
        let limit = calendar.startOfDay(for: until)
        while day < limit {
            // v1.0.62 B6 ← 原版本: 事件内容按源日、显示与闹钟按目标日 —
            // sourceDate = 该展示日的课实际来自哪天(放假日 nil / 补班日 = 被调走的源日);
            // selected = coursesForDate 按源日星期+源日周次取课(学期外空)。
            let sourceDate = HolidayTransferOps.courseDateForDate(day, transfers)
            let selected = HolidayTransferOps.coursesForDate(
                day, startDate: table.startDate, maxWeek: table.maxWeek,
                courses: courses, transfers: transfers
            )
            for course in selected {
                // 定日事件的周次/星期属于展示自然日，循环课才继承调休源日。
                let courseDate = course.fixedDate != nil ? day : (sourceDate ?? day)
                let week = CourseOccurrences.week(startDate: table.startDate, date: courseDate) ?? 1
                let classDay = CourseOccurrences.day(courseDate)
                guard let (startHHmm, endHHmm) = TimeTableUtils.effectiveCourseTime(
                    isIrregularTime: course.isIrregularTime || course.ownTime,
                    startTime: course.startTime,
                    endTime: course.endTime,
                    startNode: course.startNode,
                    step: course.step,
                    timeJson: table.timeJson
                ) else {
                    invalid += 1
                    continue
                }
                let start = appendTime(day, startHHmm)
                let end = appendTime(day, endHHmm)
                guard end > start else { invalid += 1; continue }
                // ← 原 transferred = sourceDate != date: 仅补班日为 true(放假日 sourceDate=nil → false)
                let transferred = course.fixedDate == nil
                    && (sourceDate.map { HolidayTransferOps.dayKey($0) != HolidayTransferOps.dayKey(day) } ?? false)
                specs.append(EventSpec(
                    course: course,
                    date: day,
                    week: week,
                    start: start,
                    end: end,
                    startHHmm: startHHmm,
                    endHHmm: endHHmm,
                    description: buildDescription(tableId: table.id, course: course, week: week, transferred: transferred, classDay: classDay, eventDate: day),
                    key: "\(table.id):\(course.id):\(DateUtils.fullDate(day))",
                    reminderMinutes: options.reminderMinutes.map { $0.clamped0999 },
                    wantsAlarm: options.firstPeriodAlarmEnabled
                        && course.startNode <= 1
                        && course.startNode + course.step > 1
                        && (TimeTableUtils.hmMinutes(startHHmm) ?? 0) < 720
                ))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? until
        }
        return (specs, invalid)
    }

    /// 描述 (← 原版本: 周/节次 + 教师 + 备注 + 调课提示 + 行尾 marker)
    /// marker 与 EventSpec.key 同源 table.id ("$SLEEPY_MARKER_PREFIX${table.id}:${course.id}:${fullDate}")
    private func buildDescription(tableId: Int64, course: CourseEntity, week: Int, transferred: Bool, classDay: Int, eventDate: Date) -> String {
        var text = "第\(week)周 · 第\(course.startNode)—\(course.startNode + course.step - 1)节"
        // ← 原 isNotBlank(): 纯空白不算有内容(教师/备注行为对齐)
        if !course.teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text += "\n教师：\(course.teacher)" }
        if !course.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text += "\n备注：\(course.note)" }
        if transferred { text += "\n调课安排：按\(DateUtils.chineseDay(classDay))课程" }
        text += "\n\(markerPrefix)\(tableId):\(course.id):\(DateUtils.fullDate(eventDate))"
        return text
    }

    /// 每天只取最早的 (起始时间, courseId) 那条 spec 的 key (firstPeriodAlarmKeys)
    func firstPeriodAlarmKeys(_ specs: [EventSpec]) -> [Date: String] {
        var best: [Date: (start: Date, courseKey: Int64, key: String)] = [:]
        for spec in specs where spec.wantsAlarm {
            let cand = (start: spec.start, courseKey: spec.course.id, key: spec.key)
            if let old = best[spec.date] {
                if cand.start < old.start || (cand.start == old.start && cand.courseKey < old.courseKey) {
                    best[spec.date] = cand
                }
            } else {
                best[spec.date] = cand
            }
        }
        return best.mapValues { $0.key }
    }

    // MARK: - 导入 (import: 逐 spec 读旧/比对/写入 → 记录 upsert)

    @discardableResult
    func importCourses(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        from: Date,
        until: Date,
        batchId: String
    ) throws -> CalendarImportResult {
        guard hasCalendarPermissions() else { throw CalendarImportError.permissionDenied }
        let db = AppDatabase.getShared()
        // batchId = 调用方生成并持久化 (import(batchId) 透传, 不再重新生成)
        let (specs, invalid) = buildEventSpecs(table: table, courses: courses, options: options, from: from, until: until)
        let alarmKeys = firstPeriodAlarmKeys(specs)

        let startInclusive = DateUtils.fullDate(from)
        let endExclusive = DateUtils.fullDate(until)
        let existing = try db.calendarImportRecordDao.forTable(table.id)
            .filter {
                $0.calendarId == options.calendarId
                    && ($0.eventDate as String).compare(startInclusive) != .orderedAscending
                    && ($0.eventDate as String).compare(endExclusive) == .orderedAscending
            }
            .reduce(into: [String: CalendarImportRecordEntity]()) { dict, rec in
                dict["\(rec.courseId):\(rec.eventDate)"] = rec
            }

        var inserted = 0, updated = 0, unchanged = 0, skippedEdited = 0, alarmFallback = 0, errors = 0
        let skippedInvalid = invalid

        for spec in specs {
            let recordKey = "\(spec.course.id):\(DateUtils.fullDate(spec.date))"
            var record = existing[recordKey]
            let wantsAlarm = alarmKeys[spec.date] == spec.key
            let desiredMethod: ReminderMethod? = wantsAlarm ? .alarm : (spec.reminderMinutes != nil ? .alert : nil)
            let desiredMinutes: Int? = wantsAlarm ? options.firstPeriodAlarmMinutes.clamped0999 : spec.reminderMinutes

            if let rec = record {
                let old = readEvent(eventId: rec.eventId)
                if old == nil {
                    // ← 原版本: 记录有但事件没了 → 删记录后 fall-through 到 marker 恢复/新建
                    try? db.calendarImportRecordDao.deleteById(rec.id)
                    record = nil
                } else {
                    let oldReminders = readReminder(eventId: rec.eventId) ?? []
                    if fingerprint(old!, oldReminders) != rec.fingerprint {
                        skippedEdited += 1
                        continue
                    }
                    if eventMatchesSpec(old!, spec: spec, calendarId: options.calendarId)
                        && remindersMatch(oldReminders, expectedMethod: desiredMethod, expectedMinutes: desiredMinutes, allowAlarmFallback: wantsAlarm) {
                        unchanged += 1
                        continue
                    }
                    guard writeEventValues(old!, spec: spec) else { errors += 1; continue }
                    let finalMethod = replaceReminder(event: old!, desiredMethod: desiredMethod, desiredMinutes: desiredMinutes)
                    if wantsAlarm && finalMethod != .alarm { alarmFallback += 1 }
                    if desiredMethod != nil && finalMethod == nil { errors += 1 }
                    guard let after = readEvent(eventId: old!.calendarItemExternalIdentifier) else { errors += 1; continue }
                    let afterReminders = readReminder(eventId: after.calendarItemExternalIdentifier) ?? []
                    record = CalendarImportRecordEntity(
                        tableId: table.id,
                        courseId: spec.course.id,
                        eventDate: DateUtils.fullDate(spec.date),
                        calendarId: options.calendarId,
                        eventId: after.calendarItemExternalIdentifier,
                        batchId: batchId,
                        fingerprint: fingerprint(after, afterReminders),
                        alarmRequested: wantsAlarm,
                        createdAt: rec.createdAt,
                        id: rec.id
                    )
                    try db.calendarImportRecordDao.upsert(record!)
                    updated += 1
                    continue
                }
            }

            // marker 恢复 / 新建
            let recovered = findEventByMarker(calendarId: options.calendarId, key: spec.key, date: spec.date)
            if let r = recovered, !eventMatchesSpec(r, spec: spec, calendarId: options.calendarId) {
                skippedEdited += 1
                continue
            }
            let target = recovered ?? insertEvent(spec: spec, calendarId: options.calendarId)
            if target == nil { errors += 1; continue }
            let finalMethod = replaceReminder(event: target!, desiredMethod: desiredMethod, desiredMinutes: desiredMinutes)
            if wantsAlarm && finalMethod != .alarm { alarmFallback += 1 }
            if desiredMethod != nil && finalMethod == nil { errors += 1 }
            guard let after = readEvent(eventId: target!.calendarItemExternalIdentifier) else { errors += 1; continue }
            let afterReminders = readReminder(eventId: after.calendarItemExternalIdentifier) ?? []
            let newRecord = CalendarImportRecordEntity(
                tableId: table.id,
                courseId: spec.course.id,
                eventDate: DateUtils.fullDate(spec.date),
                calendarId: options.calendarId,
                eventId: after.calendarItemExternalIdentifier,
                batchId: batchId,
                fingerprint: fingerprint(after, afterReminders),
                alarmRequested: wantsAlarm,
                createdAt: Int64(Date.now.timeIntervalSince1970 * 1000),
                id: 0
            )
            try db.calendarImportRecordDao.upsert(newRecord)
            if recovered != nil {
                unchanged += 1  // ← 原实现: marker 恢复路径计 unchanged
            } else {
                inserted += 1
            }
        }
        return CalendarImportResult(
            inserted: inserted,
            updated: updated,
            unchanged: unchanged,
            skippedEdited: skippedEdited,
            skippedInvalidTime: skippedInvalid,
            alarmFallback: alarmFallback,
            errors: errors
        )
    }

    // MARK: - 删除已管理事件 (deleteManagedForTable: 指纹不一致 = 用户改过 → 保留)

    /// 返回 (deleted, skippedEdited, missing) — 与 原版本 CalendarDeleteResult 同构
    func deleteManagedForTable(tableId: Int64, calendarId: String? = nil) -> (deleted: Int, skippedEdited: Int, missing: Int) {
        guard hasCalendarPermissions() else { return (0, 0, 0) }
        let db = AppDatabase.getShared()
        var deleted = 0, skippedEdited = 0, missing = 0
        for record in (try? db.calendarImportRecordDao.forTable(tableId)) ?? [] {
            if let cid = calendarId, record.calendarId != cid { continue }
            guard let event = readEvent(eventId: record.eventId) else {
                try? db.calendarImportRecordDao.deleteById(record.id)
                missing += 1
                continue
            }
            let reminders = readReminder(eventId: event.calendarItemExternalIdentifier) ?? []
            guard fingerprint(event, reminders) == record.fingerprint else {
                skippedEdited += 1  // 用户改过 → 事件与记录都保留
                continue
            }
            // 16.4: save/remove 的 label 顺序 span: 先于 commit:, 且可能 throw → try?
            if (try? store.remove(event, span: .thisEvent, commit: true)) != nil {
                try? db.calendarImportRecordDao.deleteById(record.id)
                deleted += 1
            }
        }
        return (deleted, skippedEdited, missing)
    }

    func deleteAllForTable(tableId: Int64) throws {
        try AppDatabase.getShared().calendarImportRecordDao.deleteForTable(tableId)
    }

    // MARK: - 静态接口 (UI 直接调用 SystemCalendarManager.import / buildPreview / deleteManagedForTable)

    /// ← 原版本 import: 计算区间 → 导入 → 返回结果
    @discardableResult
    static func `import`(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        batchId: String
    ) async -> CalendarImportResult {
        let today = Date()
        // ← 原版本: 区间扩展与事件展开用同一份调休映射
        let transfers = options.applyHolidayTransfers ? AppPrefs.shared.getHolidayTransfers(table.id) : []
        let (from, until) = selectedDateRange(table: table, range: options.range, today: today, transfers: transfers)
        do {
            // ← 原版本: options.calendarId 必须在 fallback 感知的可写集合内(可写且可见),
            //   仅在 store.calendars 中存在不足以证明可写; 兜底自建日历也在该集合内。
            let calendars = await writableCalendars()
            guard calendars.contains(where: { $0.id == options.calendarId }) else {
                throw CalendarImportError.noWritableCalendar
            }
            return try shared.importCourses(table: table, courses: courses, options: options,
                                            from: from, until: until, batchId: batchId)
        } catch {
            // ← 原版本 L166/L169: permissionDenied / noWritableCalendar → errors = 1
            //   (全零结果在对话框结果行(CalendarImportDialog L400 显示 r.errors)与空成功不可区分)
            return CalendarImportResult(
                inserted: 0, updated: 0, unchanged: 0,
                skippedEdited: 0, skippedInvalidTime: 0,
                alarmFallback: 0, errors: 1
            )
        }
    }

    /// ← 原 deleteManagedForTable (异步包装)
    static func deleteManagedForTable(tableId: Int64) async -> (deleted: Int, skippedEdited: Int, missing: Int) {
        await withCheckedContinuation { cont in
            cont.resume(returning: shared.deleteManagedForTable(tableId: tableId))
        }
    }

    // MARK: - 事件读写 (记录 eventId = EKCalendarItem.externalIdentifier, String)

    private func readEvent(eventId: String) -> EKEvent? {
        guard let item = store.calendarItem(withIdentifier: eventId) as? EKEvent else {
            // externalIdentifier 跨库稳定; 本地 identifier 失效时按 external 兜底
            return store.calendarItems(withExternalIdentifier: eventId).first as? EKEvent
        }
        return item
    }

    private func readReminder(eventId: String) -> [ReminderDesc]? {
        guard let item = store.calendarItem(withIdentifier: eventId)
            ?? store.calendarItems(withExternalIdentifier: eventId).first else { return nil }
        return (item.alarms ?? []).map { alarm in
            let minutes = Int((-alarm.relativeOffset / 60).rounded())
            // 平台裁决: 16.4 无 EKAlarm.type → 读回恒 .alert(期望 method 由记录 alarmRequested 承载)
            return ReminderDesc(method: .alert, minutes: minutes)
        }
    }

    /// marker 恢复: 当天窗口内按 notes 尾部 key 精确匹配 (LIKE %"Sleepy import key:…"% 于当天事件)
    private func findEventByMarker(calendarId: String, key: String, date: Date) -> EKEvent? {
        guard let cal = store.calendar(withIdentifier: calendarId) else { return nil }
        let rangeEnd = Calendar.isoAddDays(date, 1)
        // 16.4 Swift 改名: predicateForEventsWithStartDate: → predicateForEvents(withStart:end:calendars:)
        let predicate = store.predicateForEvents(withStart: date, end: rangeEnd, calendars: [cal])
        let suffix = "\(markerPrefix)\(key)"
        for candidate in store.events(matching: predicate) where candidate.calendar?.calendarIdentifier == calendarId {
            if candidate.notes?.hasSuffix(suffix) == true { return candidate }
        }
        return nil
    }

    private func insertEvent(spec: EventSpec, calendarId: String) -> EKEvent? {
        guard let cal = store.calendar(withIdentifier: calendarId) else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        event.isAllDay = false
        event.startDate = spec.start
        event.endDate = spec.end
        event.title = spec.course.courseName
        event.location = spec.course.room.isEmpty ? nil : spec.course.room
        event.notes = spec.description
        guard (try? store.save(event, span: .thisEvent)) != nil else { return nil }
        return event.calendarItemExternalIdentifier.isEmpty ? nil : event
    }

    private func writeEventValues(_ event: EKEvent, spec: EventSpec) -> Bool {
        event.title = spec.course.courseName
        event.location = spec.course.room.isEmpty ? nil : spec.course.room
        event.notes = spec.description
        event.startDate = spec.start
        event.endDate = spec.end
        return (try? store.save(event, span: .thisEvent, commit: true)) != nil
    }

    /// 提醒替换 (replaceReminder; 返回值 = 实际生效的 method, nil = 未挂提醒或写入失败)
    /// 平台裁决: iOS EKAlarm 单阶段写入, 不存在 原版本 的 ALARM 失败→ALERT 兜底两阶段。
    /// 语义映射: 写入成功 = 原版本 insertReminder(method) 成功分支 → 返回期望 method(不降为 .alert),
    /// 成功路径 alarmFallback 不增长; 写入失败 = 原版本 两阶段均失败 → 返回 nil(← 计 errors)。
    /// 期望 method(ALARM/ALERT) 的呈现差异由记录 alarmRequested 字段承载, 读回恒 .alert。
    private func replaceReminder(event: EKEvent, desiredMethod: ReminderMethod?, desiredMinutes: Int?) -> ReminderMethod? {
        for alarm in (event.alarms ?? []) { event.removeAlarm(alarm) }
        guard let method = desiredMethod, let minutes = desiredMinutes else {
            _ = try? store.save(event, span: .thisEvent, commit: true)
            return nil
        }
        // 16.4: EKAlarm 无 type/soundName → 系统默认提醒呈现; 期望 .alarm 由 alarmRequested 记录承载
        event.addAlarm(EKAlarm(relativeOffset: -Double(minutes * 60)))
        guard (try? store.save(event, span: .thisEvent, commit: true)) != nil else {
            return nil  // ← 原实现: 期望 method 与 ALERT 兜底均插入失败 → null
        }
        return method
    }

    // MARK: - 指纹 / 比对 (fingerprint / eventMatchesSpec / remindersMatch, 字段顺序一致)

    /// SHA-256 hex of [calendarId, title, location, notes, startMs, endMs, tz, 排序 "method:minutes"] (分隔符 \u{1F})
    func fingerprint(_ event: EKEvent, _ reminders: [ReminderDesc]) -> String {
        var parts: [String] = []
        parts.append(event.calendar?.calendarIdentifier ?? "")
        parts.append(event.title ?? "")
        parts.append(event.location ?? "")
        parts.append(event.notes ?? "")
        parts.append(Int64(event.startDate.timeIntervalSince1970 * 1000).description)
        parts.append(Int64(event.endDate.timeIntervalSince1970 * 1000).description)
        parts.append(TimeZone.current.identifier)
        let sorted = reminders.sorted {
            if $0.method != $1.method { return $0.method.rawValue < $1.method.rawValue }
            return $0.minutes < $1.minutes
        }
        parts.append(sorted.map { "\($0.method.rawValue):\($0.minutes)" }.joined(separator: ","))
        let joined = parts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// ← 原版本 eventMatchesSpec: 字段逐一比对(用户没改过才重挂提醒)
    func eventMatchesSpec(_ event: EKEvent, spec: EventSpec, calendarId: String) -> Bool {
        guard event.calendar?.calendarIdentifier == calendarId else { return false }
        guard event.title == spec.course.courseName else { return false }
        guard event.location ?? "" == (spec.course.room.isEmpty ? "" : spec.course.room) else { return false }
        guard event.notes == spec.description else { return false }
        guard event.startDate == spec.start, event.endDate == spec.end else { return false }
        return true
    }

    /// ← 原版本 remindersMatch
    func remindersMatch(
        _ actual: [ReminderDesc],
        expectedMethod: ReminderMethod?,
        expectedMinutes: Int?,
        allowAlarmFallback: Bool
    ) -> Bool {
        guard expectedMethod != nil || expectedMinutes != nil else { return actual.isEmpty }
        guard let m = expectedMethod, let minutes = expectedMinutes else { return false }
        if actual.count == 1, actual[0].method == m, actual[0].minutes == minutes { return true }
        return allowAlarmFallback
            && m == .alarm
            && actual.count == 1
            && actual[0].method == .alert
            && actual[0].minutes == minutes
    }

    // MARK: - 工具

    /// "HH:mm" 拼到当日零点起 (24:00 = 次日 0 点, 对齐节次时间解析语义)
    private func appendTime(_ day: Date, _ hm: String) -> Date {
        switch hm {
        case "24:00": return Calendar.isoAddDays(day, 1)
        default:
            let parts = hm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return day }
            return day.addingTimeInterval(TimeInterval(parts[0] * 3600 + parts[1] * 60))
        }
    }

    private static func hhmmString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// ← 原版本 coerceIn(0, 999)
private extension Int {
    var clamped0999: Int { Swift.min(Swift.max(self, 0), 999) }
}
