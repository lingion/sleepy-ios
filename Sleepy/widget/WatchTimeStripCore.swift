import Foundation

enum WatchTimeStripCore {
    static let windowDuration: TimeInterval = 90 * 60
    static let updateInterval: TimeInterval = 5 * 60

    enum State: Equatable {
        case today, tomorrowPreview, noClasses, finished, tomorrowEmpty, unavailable
    }

    struct Segment: Equatable {
        let start: Date
        let end: Date
        let courses: [WatchAgendaCore.ClassItem]
        let isBreak: Bool

        var widthFraction: Double { end.timeIntervalSince(start) / windowDuration }

        func offsetFraction(from windowStart: Date) -> Double {
            start.timeIntervalSince(windowStart) / windowDuration
        }
    }

    struct Snapshot: Equatable {
        let state: State
        let day: Date
        let windowStart: Date
        let segments: [Segment]
        let items: [WatchAgendaCore.ClassItem]

        var windowEnd: Date { windowStart.addingTimeInterval(windowDuration) }
        var isTomorrow: Bool { state == .tomorrowPreview || state == .tomorrowEmpty }
    }

    static func snapshot(now: Date, today: [WatchAgendaCore.ClassItem],
                         tomorrow: [WatchAgendaCore.ClassItem], showsTomorrow: Bool,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> Snapshot {
        let today = validItems(today)
        let day = calendar.startOfDay(for: now)
        let lastEnd = today.map(\.endDate).max()
        if let lastEnd = lastEnd, now < lastEnd {
            let windowEnd = now.addingTimeInterval(windowDuration)
            let entering = tomorrow.filter { $0.startDate < windowEnd && $0.endDate > now }
            return makeSnapshot(state: .today, day: day, start: now,
                                items: validItems(today + entering))
        }
        guard showsTomorrow else {
            return Snapshot(state: today.isEmpty ? .noClasses : .finished,
                            day: day, windowStart: now, segments: [], items: today)
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let tomorrow = validItems(tomorrow)
        guard let first = tomorrow.first,
              let end = tomorrow.map(\.endDate).max() else {
            return Snapshot(state: .tomorrowEmpty, day: nextDay,
                            windowStart: nextDay, segments: [], items: [])
        }
        // Preview time is not wall-clock time: anchor it to today's end and label it separately.
        let elapsed = max(0, now.timeIntervalSince(lastEnd ?? day))
        let offset = elapsed.truncatingRemainder(dividingBy: end.timeIntervalSince(first.startDate))
        return makeSnapshot(state: .tomorrowPreview, day: nextDay,
                            start: first.startDate.addingTimeInterval(offset), items: tomorrow)
    }

    static func unavailable(at date: Date,
                            calendar: Calendar = Calendar(identifier: .gregorian)) -> Snapshot {
        Snapshot(state: .unavailable, day: calendar.startOfDay(for: date),
                 windowStart: date, segments: [], items: [])
    }

    static func timelineDates(now: Date, courseBoundaries: [Date],
                              calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        let end = now.addingTimeInterval(24 * 60 * 60)
        var dates: Set<Date> = [now, end]
        var tick = now.addingTimeInterval(updateInterval)
        while tick < end {
            dates.insert(tick)
            tick = tick.addingTimeInterval(updateInterval)
        }
        dates.formUnion(courseBoundaries.filter { $0 > now && $0 < end })
        var day = calendar.startOfDay(for: now)
        while let midnight = calendar.date(byAdding: .day, value: 1, to: day), midnight < end {
            guard midnight > day else { break }
            if midnight > now { dates.insert(midnight) }
            day = midnight
        }
        return dates.sorted()
    }

    private static func validItems(_ items: [WatchAgendaCore.ClassItem]) -> [WatchAgendaCore.ClassItem] {
        items.filter {
            $0.startDate.timeIntervalSinceReferenceDate.isFinite &&
            $0.endDate.timeIntervalSinceReferenceDate.isFinite && $0.endDate > $0.startDate
        }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
            if $0.courseName != $1.courseName { return $0.courseName < $1.courseName }
            return $0.room < $1.room
        }
    }

    private static func makeSnapshot(state: State, day: Date, start: Date,
                                     items: [WatchAgendaCore.ClassItem]) -> Snapshot {
        let end = start.addingTimeInterval(windowDuration)
        let visible = items.filter { $0.endDate > start && $0.startDate < end }
        var boundaries: Set<Date> = [start, end]
        for item in visible {
            boundaries.insert(max(start, item.startDate))
            boundaries.insert(min(end, item.endDate))
        }
        let sorted = boundaries.sorted()
        let firstStart = items.first?.startDate ?? start
        let lastEnd = items.map(\.endDate).max() ?? end
        let segments = zip(sorted, sorted.dropFirst()).map { left, right in
            let active = visible.filter { $0.startDate < right && $0.endDate > left }
            return Segment(start: left, end: right, courses: active,
                           isBreak: active.isEmpty && left >= firstStart && right <= lastEnd)
        }
        return Snapshot(state: state, day: day, windowStart: start, segments: segments, items: items)
    }
}
