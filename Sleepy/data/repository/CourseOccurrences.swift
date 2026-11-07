import Foundation

/// 存储身份与展示日分离；调休后的星期、归一化节次不能替代原行。
struct CourseOccurrence {
    let course: CourseEntity
    let sourceDate: Date
    let displayDate: Date
}

enum CourseOccurrences {
    enum ValidationError: LocalizedError {
        case invalidDate, invalidOccurrence, invalidNodes, invalidTime
        var errorDescription: String? {
            switch self {
            case .invalidDate: return "请选择学期内的有效日期。"
            case .invalidOccurrence: return "该次课程已发生变化，请重新打开。"
            case .invalidNodes: return "所选节次不在当前作息表中。"
            case .invalidTime: return "请输入有效起止时间，结束时间须晚于开始时间。"
            }
        }
    }

    /// 与调休日键共用民事日时区，避免 CI / 海外设备将零点解释成前一天。
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func parseDate(_ value: String, calendar: Calendar? = nil) -> Date? {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
              let date = DateUtils.parseDate(value), HolidayTransferOps.dayKey(date) == value else { return nil }
        return date
    }

    static func day(_ date: Date, calendar: Calendar? = nil) -> Int {
        let cal = calendar ?? Self.calendar
        return (cal.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func date(startDate: String, week: Int, day: Int, calendar: Calendar? = nil) -> Date? {
        let cal = calendar ?? Self.calendar
        guard week >= 1, week <= Int.max / 7, (1...7).contains(day), let start = parseDate(startDate, calendar: cal) else { return nil }
        return cal.date(byAdding: .day, value: (week - 1) * 7 + day - Self.day(start, calendar: cal), to: start)
    }

    static func week(startDate: String, date: Date, calendar: Calendar? = nil) -> Int? {
        let cal = calendar ?? Self.calendar
        guard let start = Self.date(startDate: startDate, week: 1, day: 1, calendar: cal),
              let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day,
              days >= 0 else { return nil }
        return days / 7 + 1
    }

    static func coursesForDate(_ date: Date, startDate: String, maxWeek: Int,
                               courses: [CourseEntity], transfers: [HolidayTransferEntry]) -> [CourseEntity] {
        let fixed = courses.filter { $0.fixedDate == HolidayTransferOps.dayKey(date) }
        guard let source = HolidayTransferOps.courseDateForDate(date, transfers),
              let week = week(startDate: startDate, date: source), week <= maxWeek else {
            return fixed.sorted { $0.startNode < $1.startNode }
        }
        return (courses.filter { $0.fixedDate == nil && $0.day == day(source) && $0.inWeek(week) } + fixed)
            .sorted { $0.startNode < $1.startNode }
    }

    static func resolve(course: CourseEntity, displayDate: Date,
                        table: TimeTableEntity, transfers: [HolidayTransferEntry]) -> CourseOccurrence? {
        guard coursesForDate(displayDate, startDate: table.startDate, maxWeek: table.maxWeek,
                             courses: [course], transfers: transfers).count == 1 else { return nil }
        let source = course.fixedDate.flatMap { parseDate($0, calendar: nil) }
            ?? HolidayTransferOps.courseDateForDate(displayDate, transfers)
        return source.map { CourseOccurrence(course: course, sourceDate: $0, displayDate: displayDate) }
    }

    static func without(_ course: CourseEntity, sourceDate: Date, startDate: String) throws -> [CourseEntity] {
        if let fixed = course.fixedDate {
            guard fixed == HolidayTransferOps.dayKey(sourceDate) else { throw ValidationError.invalidOccurrence }
            return []
        }
        guard let week = week(startDate: startDate, date: sourceDate), course.day == day(sourceDate),
              course.inWeek(week), course.startWeek > 0, course.endWeek >= course.startWeek,
              course.endWeek <= 10_000 else { throw ValidationError.invalidOccurrence }
        let ranges = [(course.startWeek, week - 1), (week + 1, course.endWeek)]
        var result: [CourseEntity] = []
        for (first, last) in ranges where first <= last {
            let weeks = (first...last).filter { course.inWeek($0) }
            guard let first = weeks.first, let last = weeks.last else { continue }
            var row = course
            row.id = result.isEmpty ? course.id : 0
            row.startWeek = first
            row.endWeek = last
            result.append(row)
        }
        return result
    }

    static func atDate(_ course: CourseEntity, date: Date, table: TimeTableEntity, fixed: Bool) throws -> CourseEntity {
        guard let week = week(startDate: table.startDate, date: date), week <= table.maxWeek else {
            throw ValidationError.invalidDate
        }
        var row = course
        row.id = 0
        row.tableId = table.id
        row.day = day(date)
        row.startWeek = week
        row.endWeek = week
        row.type = 0
        row.fixedDate = fixed ? HolidayTransferOps.dayKey(date) : nil
        return row
    }

    static func dates(table: TimeTableEntity, transfers: [HolidayTransferEntry]) -> [Date] {
        guard table.maxWeek > 0, table.maxWeek <= 10_000 else { return [] }
        var dates: Set<Date> = []
        for week in 1...table.maxWeek {
            for day in 1...7 {
                if let date = date(startDate: table.startDate, week: week, day: day) { dates.insert(date) }
            }
        }
        for transfer in transfers { dates.insert(calendar.startOfDay(for: transfer.targetDate)) }
        return dates.sorted()
    }

    /// 合并的必要条件是实际周集合精确相等；重叠行（重复课程）不去重。
    static func mergeMatchingRows(_ rows: [CourseEntity]) -> [CourseEntity] {
        var result = rows.sorted { $0.startWeek == $1.startWeek ? $0.id < $1.id : $0.startWeek < $1.startWeek }
        func weeks(_ row: CourseEntity) -> Set<Int> {
            guard row.startWeek > 0, row.endWeek >= row.startWeek, row.endWeek <= 10_000 else { return [] }
            return Set((row.startWeek...row.endWeek).filter { row.inWeek($0) })
        }
        func identity(_ row: CourseEntity) -> CourseEntity {
            var row = row
            row.id = 0; row.startWeek = 0; row.endWeek = 0; row.type = 0
            return row
        }
        var changed = true
        while changed {
            changed = false
            search: for i in result.indices {
                let left = result[i]
                guard left.fixedDate == nil, !left.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                for j in (i + 1)..<result.count {
                    let right = result[j]
                    guard identity(left) == identity(right) else { continue }
                    let a = weeks(left), b = weeks(right)
                    guard !a.isEmpty, !b.isEmpty, a.isDisjoint(with: b) else { continue }
                    var candidate = (left.id > 0 && (right.id <= 0 || left.id < right.id)) ? left : right
                    candidate.startWeek = min(left.startWeek, right.startWeek)
                    candidate.endWeek = max(left.endWeek, right.endWeek)
                    for type in [candidate.type, 0, 1, 2] {
                        candidate.type = type
                        if weeks(candidate) == a.union(b) {
                            result[i] = candidate
                            result.remove(at: j)
                            changed = true
                            break search
                        }
                    }
                }
            }
        }
        return result
    }

    static func validateTime(_ row: CourseEntity, table: TimeTableEntity) throws {
        let nodes = Set(TimeTableUtils.parseTimeSlotRows(table.timeJson).map { $0.node })
        guard row.step > 0, row.step <= nodes.count, row.startNode <= Int.max - row.step,
              (row.startNode..<(row.startNode + row.step)).allSatisfy({ nodes.contains($0) }) else {
            throw ValidationError.invalidNodes
        }
        if row.ownTime || row.isIrregularTime {
            guard let start = TimeTableUtils.hmToSeconds(row.startTime),
                  let end = TimeTableUtils.hmToSeconds(row.endTime), end > start else { throw ValidationError.invalidTime }
        }
    }

    /// 保存预览和冲突确认走同一日历展开，跨周调休也参与判断。
    static func conflictDetails(drafts: [CourseEntity], stored: [CourseEntity],
                                table: TimeTableEntity, transfers: [HolidayTransferEntry]) -> [String] {
        var details: [String] = []
        for date in dates(table: table, transfers: transfers) {
            let incoming = coursesForDate(date, startDate: table.startDate, maxWeek: table.maxWeek,
                                           courses: drafts, transfers: transfers)
            let existing = coursesForDate(date, startDate: table.startDate, maxWeek: table.maxWeek,
                                           courses: stored, transfers: transfers)
            for (index, row) in incoming.enumerated() {
                for other in existing + Array(incoming.dropFirst(index + 1)) {
                    let a = TimeTableUtils.effectiveCourseTime(isIrregularTime: row.ownTime || row.isIrregularTime,
                        startTime: row.startTime, endTime: row.endTime, startNode: row.startNode, step: row.step, timeJson: table.timeJson)
                    let b = TimeTableUtils.effectiveCourseTime(isIrregularTime: other.ownTime || other.isIrregularTime,
                        startTime: other.startTime, endTime: other.endTime, startNode: other.startNode, step: other.step, timeJson: table.timeJson)
                    guard let a, let b, let aStart = TimeTableUtils.hmToSeconds(a.0), let aEnd = TimeTableUtils.hmToSeconds(a.1),
                          let bStart = TimeTableUtils.hmToSeconds(b.0), let bEnd = TimeTableUtils.hmToSeconds(b.1),
                          aStart < bEnd, bStart < aEnd else { continue }
                    let detail = "\(HolidayTransferOps.dayKey(date)) · \(row.courseName) / \(other.courseName) · \(a.0)-\(a.1)"
                    if !details.contains(detail) { details.append(detail) }
                }
            }
        }
        return details
    }
}
