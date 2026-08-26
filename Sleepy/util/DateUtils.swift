// DateUtils.swift — ← util/DateUtils.kt 逐行翻译 (GPL-3.0)
// LocalDate → Foundation Date(当日零点,语义同 Kotlin LocalDate)

import Foundation

/// 日期/周次工具 — 完全不依赖 UI,单元测试方便。
enum DateUtils {

    static let isoCalendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        c.minimumDaysInFirstWeek = 1
        return c
    }()

    static func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!  // LocalDate 无时区,固定锚
        return c.date(from: comps)
    }

    static func dayStart(_ d: Date, calendar: Calendar = isoCalendar) -> Date {
        calendar.startOfDay(for: d)
    }

    enum SemesterStatus { case beforeStart, inRange, afterEnd }

    static func semesterStatus(startDate: String, maxWeek: Int, today: Date = Date()) -> SemesterStatus {
        guard let start = parseDate(startDate) else { return .inRange }
        let cal = isoCalendar
        let todayStart = cal.startOfDay(for: today)
        let startDay = cal.startOfDay(for: start)
        if todayStart < startDay { return .beforeStart }
        let days = cal.dateComponents([.day], from: startDay, to: todayStart).day ?? 0
        if days / 7 + 1 > maxWeek { return .afterEnd }
        return .inRange
    }

    /// 计算当前是学期第几周（1-based）；学期外统一钳制到可浏览范围。
    static func currentWeek(startDate: String, today: Date = Date()) -> Int {
        guard let start = parseDate(startDate) else { return 1 }
        let cal = isoCalendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: today)).day ?? 0
        return max(1, days / 7 + 1)
    }

    /// 今天是星期几（1=周一, 7=周日）
    static func todayDayOfWeek(today: Date = Date()) -> Int {
        // Java DayOfWeek.MONDAY = 1 ... SUNDAY = 7
        let cal = isoCalendar
        let weekday = cal.component(.weekday, from: today)  // Sunday=1 ... Saturday=7
        return weekday == 1 ? 7 : weekday - 1
    }

    /// 从周数和星期几得到具体日期
    static func dateOfWeek(startDate: String, week: Int, dayOfWeek: Int) -> Date? {
        guard let start = parseDate(startDate) else { return nil }
        let cal = isoCalendar
        return cal.date(byAdding: DateComponents(day: dayOfWeek - 1 + (week - 1) * 7), to: start)
    }

    /// 同一周内指定星期几的日期（以 ref 为参照，1=周一 7=周日）
    static func dateOfWeekDay(ref: Date, dayOfWeek: Int) -> Date {
        let cal = isoCalendar
        let offset = dayOfWeek - todayDayOfWeek(today: ref)
        return cal.date(byAdding: .day, value: offset, to: ref) ?? ref
    }

    /// ISO 周编号
    static func isoWeekNumber(_ date: Date) -> Int {
        isoCalendar.component(.weekOfYear, from: date)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = isoCalendar
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 短日期 (MM-dd)
    static func shortDate(_ date: Date) -> String {
        fmt.dateFormat = "MM-dd"
        return fmt.string(from: date)
    }

    /// 完整日期 (yyyy-MM-dd)
    static func fullDate(_ date: Date) -> String {
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// 中文星期
    static func chineseDay(_ dayOfWeek: Int) -> String {
        switch dayOfWeek {
        case 1: return "周一"
        case 2: return "周二"
        case 3: return "周三"
        case 4: return "周四"
        case 5: return "周五"
        case 6: return "周六"
        case 7: return "周日"
        default: return ""
        }
    }

    /// Locale-aware 星期 — day_names 数组键(L10n.dayName)
    static func localizedDay(_ dayOfWeek: Int) -> String {
        let idx = dayOfWeek - 1
        return (0...6).contains(idx) ? L10n.dayName(idx) : ""
    }

    /// 短日期格式 M/d（无前导零）
    static func shortDateSlash(_ date: Date) -> String {
        let c = isoCalendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 1)/\(c.day ?? 1)"
    }
}

/// ICS 解析用的 ISO 周工具(Swift Date 版 java.time.LocalDate 语义)
extension Calendar {
    /// 两个日期之间的整天数(b - a)
    static func isoDaysBetween(_ a: Date, _ b: Date) -> Int {
        let ca = DateUtils.isoCalendar.startOfDay(for: a)
        let cb = DateUtils.isoCalendar.startOfDay(for: b)
        return DateUtils.isoCalendar.dateComponents([.day], from: ca, to: cb).day ?? 0
    }

    /// 日期 + n 天
    static func isoAddDays(_ d: Date, _ n: Int) -> Date {
        DateUtils.isoCalendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    /// 该日期所在 ISO 周的周一
    static func isoMondayOfWeek(_ d: Date) -> Date {
        let start = DateUtils.isoCalendar.startOfDay(for: d)
        let dow = DateUtils.isoCalendar.component(.weekday, from: start)  // 1=Sun..7=Sat
        let isoDow = dow == 1 ? 7 : dow - 1                               // 1=Mon..7=Sun
        return DateUtils.isoCalendar.date(byAdding: .day, value: -(isoDow - 1), to: start) ?? start
    }

    /// yyyy-MM-dd(无时区歧义,当日零点)
    static func isoString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = DateUtils.isoCalendar
        f.timeZone = DateUtils.isoCalendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
