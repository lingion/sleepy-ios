// SystemCalendarManager.swift — 系统日历导入引擎 (v1.0.61 对齐, ← Android SystemCalendarManager.kt 441L, 行为对齐非逐行翻译)
//
// 平台映射:
// - 内容库 ContentProvider 写系统日历 → EventKit EKEventStore (系统 framework, 无新 SPM 依赖)
// - WRITE/READ_CALENDAR 权限 → EKEventStore.requestAccess(to: .event);
//   16.4 SDK 无 .fullAccess/.writeOnly 分支, 授权即 authorizationStatus == .authorized
// - 可写日历 = allowsContentModifications && type != .local/.calDAV (← Android ACCESS_LEVEL >= CONTRIBUTOR && VISIBLE, 16.4 无 isSelectable)
// - 记录 eventId ← 内容库 _ID(Long) → EKCalendarItem.externalIdentifier (String)
// - 描述行尾 marker "Sleepy import key: tableId:courseId:yyyy-MM-dd" 保留(存 EKCalendarItem.notes),
//   记录丢失后可按 marker 恢复, 对齐 Android findEventByMarker
// - Android "ALARM(闹钟)" 提醒 → iOS 16.4 EKAlarm 无 type/soundName(.audio/.display 均不可用),
//   提醒恒以 EKAlarm(relativeOffset:) 写入、系统默认提醒呈现; 期望的 method(ALARM/ALERT) 由我方记录
//   alarmRequested 字段承载, 读回(readReminder)恒分类为 .alert。alarmFallback 计数对齐 Android 语义:
//   Android 仅在 METHOD_ALARM 插入失败且 METHOD_ALERT 兜底插入成功时计数; iOS EKAlarm 为单阶段写入、
//   不存在两阶段兜底 → 写入成功即视为期望 method 生效(← Android insertReminder(method) 成功分支),
//   写入失败返回 nil 计 errors(← Android 两阶段均失败分支)。成功路径 alarmFallback 不增长, 与 Android 一致。
// - 事件时区 EKEvent 无公开 API → 指纹恒以 TimeZone.current.identifier 固定(与 Android ZoneId.systemDefault().id 同位)
// - EventKit 无"导入历史"原生概念 → 仓内 CalendarImportRecordDao/Entity (calendar_import_records 表) 承担记录职责

import EventKit
import Foundation
import CryptoKit

// MARK: - 选项 / 预览 / 结果 (与 Android data class 同名同字段)

/// 日历导入范围枚举 (← Android CalendarImportRange enum)
enum CalendarImportRange: String, CaseIterable, Identifiable {
    case NEXT_WEEK = "NEXT_WEEK"
    case NEXT_MONTH = "NEXT_MONTH"
    case SEMESTER = "SEMESTER"
    var id: String { rawValue }
}

/// 可写日历信息 (← Android SystemCalendarInfo data class)
struct SystemCalendarInfo: Identifiable {
    let id: String          // EKCalendar.calendarIdentifier
    let displayName: String // EKCalendar.title
    let accountName: String // EKCalendar.source.title
}

struct CalendarImportOptions {
    /// 目标 EKCalendar.calendarIdentifier (← Android calendarId: Long, 平台映射)
    var calendarId: String
    /// 导入范围
    var range: CalendarImportRange
    var applyHolidayTransfers: Bool
    /// 普通提醒提前分钟; nil = 不加普通提醒 (← Android reminderMinutes: Int?)
    var reminderMinutes: Int?
    var firstPeriodAlarmEnabled: Bool
    /// 首次课强制提醒提前分钟 (← Android firstPeriodAlarmMinutes)
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

/// ← Android CalendarImportPreviewRow (UI 预览行, 与 CalendarPreviewRow 同构)
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
    /// ← Android imported.alarmFallback: 仅当期望闹钟(.alarm)但闹钟提醒未能按期望生效时计数。
    /// 平台裁决: iOS EKAlarm 单阶段写入无两阶段兜底 → 写入成功即视为期望 method 生效, 成功路径不计数;
    /// 计数保留给未来的真实兜底场景(当前 16.4 恒为 0, 语义与 Android 成功路径一致)。
    var alarmFallback: Int = 0
    var errors: Int = 0
}

final class SystemCalendarManager {

    static let shared = SystemCalendarManager()

    private let store = EKEventStore()
    private let markerPrefix = "Sleepy import key:"

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
        /// 首次课且早间课 (← Android wantsAlarm)
        var wantsAlarm: Bool
    }

    // MARK: - 权限 / 日历发现

    /// ← Android hasCalendarPermissions (iOS 16.4: 静态 authorizationStatus, 授权即 .authorized)
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

    /// ← Android findWritableCalendar: 可写(AccessLevel>=CONTRIBUTOR & VISIBLE) && 非 calDAV
    /// (16.4 无 isSelectable; 平台等价 = allowsContentModifications 且排除 .local/.calDAV 源)
    /// 排序对齐 Android `ORDER BY IS_PRIMARY DESC, CALENDAR_DISPLAY_NAME COLLATE NOCASE`:
    /// EKCalendar 无 isPrimary API → defaultCalendarForNewEvents 作为 primary 代理恒排首位,
    /// 其余按 title  localizedCaseInsensitive 比较(← COLLATE NOCASE)。
    /// displayName = title.isBlank ? accountName : title (← Android displayName.ifBlank { accountName }, 含纯空白)
    static func writableCalendars() -> [SystemCalendarInfo] {
        let defaultId = shared.store.defaultCalendarForNewEvents?.calendarIdentifier
        return shared.store.calendars(for: .event).filter {
            $0.allowsContentModifications && $0.type != .local && $0.type != .calDAV
        }.map { cal in
            SystemCalendarInfo(
                id: cal.calendarIdentifier,
                displayName: cal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cal.source.title : cal.title,
                accountName: cal.source.title
            )
        }.sorted { lhs, rhs in
            let lPrimary = lhs.id == defaultId
            let rPrimary = rhs.id == defaultId
            if lPrimary != rPrimary { return lPrimary }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    // MARK: - 日期区间 (← Android selectedDateRange, 公式逐一对齐)

    static func selectedDateRange(table: TimeTableEntity, range: CalendarImportRange, today: Date) -> (start: Date, end: Date) {
        let cal = DateUtils.isoCalendar
        let tableStart = DateUtils.parseDate(table.startDate) ?? today
        let semesterStart = Calendar.isoMondayOfWeek(tableStart)
        let semesterEnd = Calendar.isoAddDays(semesterStart, 7 * table.maxWeek)
        let requestedEnd: Date
        switch range {
        case .NEXT_MONTH: requestedEnd = cal.date(byAdding: .month, value: 1, to: today) ?? today
        case .SEMESTER: requestedEnd = semesterEnd
        case .NEXT_WEEK: requestedEnd = Calendar.isoAddDays(today, 7)
        }
        return (max(today, semesterStart), min(requestedEnd, semesterEnd))
    }

    // MARK: - 预览

    /// ← Android buildPreview(table, courses, options, today) — today 可注入, 默认当前日期 (← Android today: LocalDate = LocalDate.now())
    static func buildPreview(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        today: Date = Date()
    ) -> CalendarImportPreview {
        let (from, until) = selectedDateRange(table: table, range: options.range, today: today)
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

    /// 生成事件 spec (← Android buildEventSpecs: 逐日 调课映射 + 周过滤 + 节次→时间 + marker 描述)
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
        var day = DateUtils.dayStart(from)
        let limit = DateUtils.dayStart(until)
        while day < limit {
            let week = DateUtils.currentWeek(startDate: table.startDate, today: day)
            let naturalDow = DateUtils.todayDayOfWeek(today: day)
            let classDay = transfers.isEmpty ? naturalDow : HolidayTransferOps.effectiveDayOfWeek(day, transfers)
            for course in courses where course.day == classDay && course.inWeek(week) {
                guard let (startHHmm, endHHmm) = TimeTableUtils.effectiveCourseTime(
                    isIrregularTime: course.isIrregularTime,
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
                let transferred = transfers.isEmpty ? false : classDay != naturalDow
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
            day = Calendar.isoAddDays(day, 1)
        }
        return (specs, invalid)
    }

    /// 描述 (← Android: 周/节次 + 教师 + 备注 + 调课提示 + 行尾 marker)
    /// marker 与 EventSpec.key 同源 table.id (← Android "$SLEEPY_MARKER_PREFIX${table.id}:${course.id}:${fullDate}")
    private func buildDescription(tableId: Int64, course: CourseEntity, week: Int, transferred: Bool, classDay: Int, eventDate: Date) -> String {
        var text = "第\(week)周 · 第\(course.startNode)—\(course.startNode + course.step - 1)节"
        // ← Android isNotBlank(): 纯空白不算有内容(教师/备注行为对齐)
        if !course.teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text += "\n教师：\(course.teacher)" }
        if !course.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text += "\n备注：\(course.note)" }
        if transferred { text += "\n调课安排：按\(DateUtils.chineseDay(classDay))课程" }
        text += "\n\(markerPrefix)\(tableId):\(course.id):\(DateUtils.fullDate(eventDate))"
        return text
    }

    /// 每天只取最早的 (起始时间, courseId) 那条 spec 的 key (← Android firstPeriodAlarmKeys)
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

    // MARK: - 导入 (← Android import: 逐 spec 读旧/比对/写入 → 记录 upsert)

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
        // ← Android: options.calendarId 必须在 writableCalendars() 集合内(可写且可见),
        //   仅在 store.calendars 中存在不足以证明可写 (如 type == .local 已被 picker 过滤)。
        guard Self.writableCalendars().contains(where: { $0.id == options.calendarId }) else {
            throw CalendarImportError.noWritableCalendar
        }
        let db = AppDatabase.getShared()
        // batchId = 调用方生成并持久化 (← Android import(batchId) 透传, 不再重新生成)
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
                    // ← Android: 记录有但事件没了 → 删记录后 fall-through 到 marker 恢复/新建
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
                unchanged += 1  // ← Android: marker 恢复路径计 unchanged
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

    // MARK: - 删除已管理事件 (← Android deleteManagedForTable: 指纹不一致 = 用户改过 → 保留)

    /// 返回 (deleted, skippedEdited, missing) — 与 Android CalendarDeleteResult 同构
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

    /// ← Android import: 计算区间 → 导入 → 返回结果
    @discardableResult
    static func `import`(
        table: TimeTableEntity,
        courses: [CourseEntity],
        options: CalendarImportOptions,
        batchId: String
    ) async -> CalendarImportResult {
        let today = Date()
        let (from, until) = selectedDateRange(table: table, range: options.range, today: today)
        do {
            return try shared.importCourses(table: table, courses: courses, options: options,
                                            from: from, until: until, batchId: batchId)
        } catch {
            // ← Android L166/L169: permissionDenied / noWritableCalendar → errors = 1
            //   (全零结果在对话框结果行(CalendarImportDialog L400 显示 r.errors)与空成功不可区分)
            return CalendarImportResult(
                inserted: 0, updated: 0, unchanged: 0,
                skippedEdited: 0, skippedInvalidTime: 0,
                alarmFallback: 0, errors: 1
            )
        }
    }

    /// ← Android deleteManagedForTable (异步包装)
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

    /// marker 恢复: 当天窗口内按 notes 尾部 key 精确匹配 (← Android LIKE %"Sleepy import key:…"% 于当天事件)
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

    /// 提醒替换 (← Android replaceReminder; 返回值 = 实际生效的 method, nil = 未挂提醒或写入失败)
    /// 平台裁决: iOS EKAlarm 单阶段写入, 不存在 Android 的 ALARM 失败→ALERT 兜底两阶段。
    /// 语义映射: 写入成功 = Android insertReminder(method) 成功分支 → 返回期望 method(不降为 .alert),
    /// 成功路径 alarmFallback 不增长; 写入失败 = Android 两阶段均失败 → 返回 nil(← 计 errors)。
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
            return nil  // ← Android: 期望 method 与 ALERT 兜底均插入失败 → null
        }
        return method
    }

    // MARK: - 指纹 / 比对 (← Android fingerprint / eventMatchesSpec / remindersMatch, 字段顺序一致)

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

    /// ← Android eventMatchesSpec: 字段逐一比对(用户没改过才重挂提醒)
    func eventMatchesSpec(_ event: EKEvent, spec: EventSpec, calendarId: String) -> Bool {
        guard event.calendar?.calendarIdentifier == calendarId else { return false }
        guard event.title == spec.course.courseName else { return false }
        guard event.location ?? "" == (spec.course.room.isEmpty ? "" : spec.course.room) else { return false }
        guard event.notes == spec.description else { return false }
        guard event.startDate == spec.start, event.endDate == spec.end else { return false }
        return true
    }

    /// ← Android remindersMatch
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

/// ← Android coerceIn(0, 999)
private extension Int {
    var clamped0999: Int { Swift.min(Swift.max(self, 0), 999) }
}
