// WeekDisplayResolver.swift — ← util/WeekDisplayResolver.kt 逐行翻译 (GPL-3.0)

import Foundation

/// 展示日期的单一事实来源。
///
/// v2 (用户 2026-09-20 改向):
///   焦点从"切下周"改成"显示最近一个还有课的日子"。
///   - 今天还有未结束的课 → 落在今天
///   - 今天之后（学期范围内）还有任何课 → 落在那个日子
///   - 全空（学期结束/开关关/无课） → 落在今天，让 UI 用 semesterStatus 自己画状态文案
///
/// 老 API (displayWeek / NEXT_WEEK / WEEKEND_CURRENT / CURRENT_ENDED) 已彻底删除；
/// widget/UI 在后续 slice 内切到 targetDate / targetWeek。
enum WeekDisplayStatus {
    /// 落在今天或用户手动选择周，没有自动跳转。
    case normal
    /// 已自动跳到今天之后最近的某一天有课那天。
    case nearestBusyDay
}

struct WeekDisplayContext {
    /// 当前学期周数（不随开关或跳转变化）。
    let actualWeek: Int
    /// 默认应该展示的日期（语义：nil 已不可能——今日或跳到的未来某天）。
    let targetDate: Date
    /// targetDate 所在周（1-based）。
    let targetWeek: Int
    /// 今天是否还有未结束的课；false 表示今天已空但跳到了之后某天。
    let todayHasRemaining: Bool
    let status: WeekDisplayStatus
    let semesterStatus: DateUtils.SemesterStatus
    let today: Date
    let enabled: Bool
}

enum WeekDisplayResolver {
    static func resolve(
        startDate: String,
        maxWeek: Int,
        now: Date,
        courses: [CourseEntity],
        timeJson: String,
        enabled: Bool,
        transfers: [HolidayTransferEntry] = []
    ) -> WeekDisplayContext {
        let safeMaxWeek = max(maxWeek, 1)
        let today = DateUtils.dayStart(now)
        let semesterStatus = DateUtils.semesterStatus(startDate: startDate, maxWeek: safeMaxWeek, today: today)
        let actualWeek = min(max(DateUtils.currentWeek(startDate: startDate, today: today), 1), safeMaxWeek)

        // ← Kotlin: todayHasRemaining 改走 coursesForDate(today) 调休感知口径
        // (非开关门控的 semesterStatus==IN_RANGE && hasRemainingCourse 旧式):
        // 放假日挪走后当天无课 → 应跳最近有课日; 旧口径仍按自然星期算"有课"。
        let todayHasRemaining = HolidayTransferOps.coursesForDate(
            today, startDate: startDate, maxWeek: safeMaxWeek,
            courses: courses, transfers: transfers
        ).contains { course in
            guard let end = courseEndMinutes(course, timeJson) else { return true }
            return end > nowMinutesOf(now)
        }

        let targetDate: Date
        if !enabled || semesterStatus != .inRange || todayHasRemaining {
            targetDate = today
        } else {
            targetDate = findNearestBusyDays(
                startDate: startDate,
                actualWeek: actualWeek,
                maxWeek: safeMaxWeek,
                today: today,
                courses: courses,
                count: 1,
                transfers: transfers
            ).first ?? today
        }
        // ← Kotlin targetWeek 门补调休条件: 今天有"补班映射" (targetDate==today 且其
        // sourceDate 在学期内) 时不取 actualWeek, 按 currentWeek 反解。
        let hasWorkdayTransferToday = transfers.contains(where: {
            HolidayTransferOps.dayKey($0.targetDate) == HolidayTransferOps.dayKey(today)
                && DateUtils.semesterStatus(startDate: startDate, maxWeek: safeMaxWeek,
                                            today: $0.sourceDate) == .inRange
        })
        let targetWeek = (targetDate == today && !hasWorkdayTransferToday)
            ? actualWeek
            : min(max(DateUtils.currentWeek(startDate: startDate, today: targetDate), 1), safeMaxWeek)

        let status: WeekDisplayStatus
        if !enabled || semesterStatus != .inRange {
            status = .normal
        } else if targetDate == today {
            status = .normal
        } else {
            status = .nearestBusyDay
        }
        return WeekDisplayContext(
            actualWeek: actualWeek,
            targetDate: targetDate,
            targetWeek: targetWeek,
            todayHasRemaining: todayHasRemaining,
            status: status,
            semesterStatus: semesterStatus,
            today: today,
            enabled: enabled
        )
    }

    /// 给主界面 / 可手动导航的 widget 计算当前展示日的标题状态：
    /// 仅当展示日恰好等于自动选中的最近有课日（非今天）时显示 NEAREST_BUSY_DAY 文案，
    /// 同周内翻到其他日子 / 其他周 / 今天 / 关闭开关时统一 NORMAL。
    ///
    /// 按日期而非周次比较：「最近有课的一天」语义指向具体那一天，
    /// 同周内的其他日子即使落在同一周也不该继续顶这个标签。
    static func statusForSelectedDate(context: WeekDisplayContext, selectedDate: Date) -> WeekDisplayStatus {
        if !context.enabled { return .normal }
        if context.status == .nearestBusyDay && selectedDate == context.targetDate { return .nearestBusyDay }
        return .normal
    }

    /// 从今天（不含）开始按日历顺序取未来有课日期。结果最多 `count` 个；没有结果时
    /// 返回 today，调用方可据此保持原有 NORMAL 降级语义。
    ///
    /// 关键不变量：扫描上限是 maxWeek 的周天，不会跨学期跳出；日期顺序永远递增。
    /// ← Kotlin 同源: 逐日走 coursesForDate 判定 (调休感知 — 放假日挪走/补班日补上),
    /// endDate 额外纳入"sourceDate 在学期内"的映射 targetDate (补班日可能越过学期末)。
    static func findNearestBusyDays(
        startDate: String,
        actualWeek: Int,
        maxWeek: Int,
        today: Date,
        courses: [CourseEntity],
        count: Int = 2,
        transfers: [HolidayTransferEntry] = []
    ) -> [Date] {
        if count <= 0 { return [] }
        guard let semesterEnd = DateUtils.dateOfWeek(startDate: startDate, week: maxWeek, dayOfWeek: 7) else { return [today] }
        // ← Kotlin: endDate = maxOf(semesterEnd, 学期内 source 的最大 targetDate)
        let endDate = transfers.compactMap {
            DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek, today: $0.sourceDate) == .inRange
                ? $0.targetDate : nil
        }.max().map { $0 > semesterEnd ? $0 : semesterEnd } ?? semesterEnd
        var result: [Date] = []
        let cal = DateUtils.isoCalendar
        var cursor = cal.date(byAdding: .day, value: 1, to: today) ?? today
        while cursor <= endDate && result.count < count {
            if !HolidayTransferOps.coursesForDate(
                cursor, startDate: startDate, maxWeek: maxWeek,
                courses: courses, transfers: transfers
            ).isEmpty {
                result.append(cursor)
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? endDate
        }
        return result.isEmpty ? [today] : result
    }

    /// now 的"当日分钟数" ← Kotlin now.hour*60+now.minute (Asia/Shanghai 口径)
    private static func nowMinutesOf(_ now: Date) -> Int {
        // isoCalendar 已固定锚 Asia/Shanghai (DateUtils L22), 与其余日期口径同源
        let comps = DateUtils.isoCalendar.dateComponents([.hour, .minute], from: now)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private static func courseEndMinutes(_ course: CourseEntity, _ timeJson: String) -> Int? {
        guard let effective = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: course.isIrregularTime || course.ownTime,
            startTime: course.startTime,
            endTime: course.endTime,
            startNode: course.startNode,
            step: course.step,
            timeJson: timeJson
        ) else { return nil }
        guard let end = TimeTableUtils.hmMinutes(effective.1) else { return nil }
        return end
    }
}
