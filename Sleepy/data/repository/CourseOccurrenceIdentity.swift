import Foundation

/// 库内某次上课的周/星期；与渲染副本的展示周、展示列分开保存。
/// 起拖时把此值与原 course.id/tableId 一起捕获，翻页后不再从展示周推断源周。
struct CourseOccurrenceIdentity: Equatable {
    let week: Int
    let day: Int

    func matches(_ course: CourseEntity, startDate: String) -> Bool {
        if let fixed = course.fixedDate {
            guard let date = CourseOccurrences.parseDate(fixed) else { return false }
            return CourseOccurrences.week(startDate: startDate, date: date) == week && CourseOccurrences.day(date) == day
        }
        return course.day == day && course.inWeek(week)
    }

    /// 定日课程拖动目标是自然日；循环课程目标仍反查调休源日。
    static func destination(course: CourseEntity, startDate: String, maxWeek: Int,
                            displayWeek: Int, displayDay: Int,
                            transfers: [HolidayTransferEntry]) -> CourseOccurrenceIdentity? {
        if course.fixedDate != nil {
            guard maxWeek > 0, displayWeek >= 1, displayWeek <= maxWeek,
                  CourseOccurrences.date(startDate: startDate, week: displayWeek, day: displayDay) != nil else { return nil }
            return CourseOccurrenceIdentity(week: displayWeek, day: displayDay)
        }
        return resolve(startDate: startDate, maxWeek: maxWeek, displayWeek: displayWeek,
                       displayDay: displayDay, transfers: transfers)
    }

    /// 定日课程不服从调休映射；调用者传存储行而非渲染副本。
    static func resolve(course: CourseEntity, startDate: String, maxWeek: Int,
                        displayWeek: Int, displayDay: Int,
                        transfers: [HolidayTransferEntry]) -> CourseOccurrenceIdentity? {
        guard let fixed = course.fixedDate else {
            return resolve(startDate: startDate, maxWeek: maxWeek, displayWeek: displayWeek,
                           displayDay: displayDay, transfers: transfers)
        }
        guard let date = CourseOccurrences.parseDate(fixed),
              let displayed = CourseOccurrences.date(startDate: startDate, week: displayWeek, day: displayDay),
              HolidayTransferOps.dayKey(displayed) == fixed,
              let week = CourseOccurrences.week(startDate: startDate, date: date), week <= maxWeek else { return nil }
        return CourseOccurrenceIdentity(week: week, day: CourseOccurrences.day(date))
    }

    /// 源列与目标列共用的解析入口，与 renderCoursesForWeek 的逐日取课口径一致。
    /// 展示周可以超过 maxWeek；是否合法取决于映射后的真实源日是否在学期内。
    static func resolve(startDate: String, maxWeek: Int,
                        displayWeek: Int, displayDay: Int,
                        transfers: [HolidayTransferEntry]) -> CourseOccurrenceIdentity? {
        // dateOfWeek 内部计算 (week - 1) * 7 + day - 1，先挡住非法坐标及整数溢出。
        guard maxWeek > 0, displayWeek >= 1, displayWeek <= Int.max / 7,
              (1...7).contains(displayDay),
              let displayDate = DateUtils.dateOfWeek(
                startDate: startDate, week: displayWeek, dayOfWeek: displayDay),
              let courseDate = HolidayTransferOps.courseDateForDate(displayDate, transfers),
              DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek, today: courseDate) == .inRange
        else { return nil }

        return CourseOccurrenceIdentity(
            week: DateUtils.currentWeek(startDate: startDate, today: courseDate),
            day: DateUtils.todayDayOfWeek(today: courseDate))
    }
}
