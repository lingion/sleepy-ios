// LockScreenCourseWidget.swift — iOS 16+ Lock Screen course widgets (#475).

import SwiftUI
import WidgetKit

#if os(iOS)
@available(iOS 16.0, *)
struct LockScreenCourseWidget: Widget {
    static let widgetKind = "LockScreenCourseWidget"

    struct Row: Equatable {
        let course: CourseEntity
        let timeLabel: String
        let startMinute: Int?
        let endMinute: Int?
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.widgetKind, provider: LockScreenCourseProvider()) { entry in
            LockScreenCourseEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }

    static func visibleCourses(data: WidgetData, nowMin: Int?, limit: Int) -> [Row] {
        guard limit > 0 else { return [] }
        let mapped: [Row] = data.courses.map { course in
            let range = TimeTableUtils.effectiveCourseTime(
                isIrregularTime: course.isIrregularTime || course.ownTime,
                startTime: course.startTime,
                endTime: course.endTime,
                startNode: course.startNode,
                step: course.step,
                timeJson: data.timeJson
            )
            let startMin = range.flatMap { TimeTableUtils.hmMinutes($0.0) }
            let endMin = range.flatMap { TimeTableUtils.hmMinutes($0.1) }
            let label: String
            if let range, startMin != nil, endMin != nil {
                label = "\(range.0)–\(range.1)"
            } else {
                label = ""
            }
            return Row(course: course, timeLabel: label, startMinute: startMin, endMinute: endMin)
        }
        let filtered: [Row]
        if data.isToday, let nowMin {
            filtered = mapped.filter { row in
                guard let end = row.endMinute else { return true }
                return end > nowMin
            }
        } else {
            filtered = mapped
        }
        let sorted = filtered.sorted { lhs, rhs in
            switch (lhs.startMinute, rhs.startMinute) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            switch (lhs.endMinute, rhs.endMinute) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            if lhs.course.startNode != rhs.course.startNode {
                return lhs.course.startNode < rhs.course.startNode
            }
            return lhs.course.id < rhs.course.id
        }
        return Array(sorted.prefix(limit))
    }

    static func title(for data: WidgetData) -> String {
        let prefix: String
        if data.weekDisplayStatus == .nearestBusyDay {
            prefix = L10n.format("schedule_nearest_busy_day")
        } else if data.isToday {
            prefix = L10n.format("today_today")
        } else {
            prefix = L10n.format("tomorrow")
        }
        return "\(prefix) · \(data.dayName)"
    }
}

@available(iOS 16.0, *)
struct LockScreenCourseProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(
            date: Date(),
            data: WidgetData(date: Date(), courses: [], timeJson: TimeTableUtils.DEFAULT_TIME_JSON, hasTable: false),
            nowMin: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        Task {
            let now = Date()
            let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV", now: now)
            completion(TodayWidgetEntry(date: now, data: data, nowMin: data.isToday ? WidgetWindows.nowMinutes(now) : nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        Task {
            let timeline = await Self.timeline()
            completion(timeline)
        }
    }

    static func timeline(overrideTableId: Int64? = nil) async -> Timeline<TodayWidgetEntry> {
        let now = Date()
        let navKey = "TodayWidgetRV"
        let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV", now: now,
                                                  overrideTableId: overrideTableId, navKey: navKey)
        let nextDayData = await TodayWidgetProvider.loadNextDayData(kind: "TodayWidgetRV", current: data,
                                                                    from: now, overrideTableId: overrideTableId,
                                                                    navKey: navKey)
        let entries = TodayWidgetProvider.timelineEntries(data: data, nextDayData: nextDayData, from: now,
                                                          navKey: navKey)
        var cal = DateUtils.isoCalendar
        cal.timeZone = .current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        return Timeline(entries: entries, policy: .after(refresh))
    }
}

#if compiler(>=5.9)
@available(iOS 17.0, *)
struct LockScreenCourseIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        LockScreenCourseProvider().placeholder(in: context)
    }

    func snapshot(for configuration: SelectTimetableIntent, in context: Context) async -> TodayWidgetEntry {
        let now = Date()
        let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV", now: now,
                                                  overrideTableId: configuration.timetable?.id,
                                                  navKey: "TodayWidgetRV")
        return TodayWidgetEntry(date: now, data: data, nowMin: data.isToday ? WidgetWindows.nowMinutes(now) : nil)
    }

    func timeline(for configuration: SelectTimetableIntent, in context: Context) async -> Timeline<TodayWidgetEntry> {
        await LockScreenCourseProvider.timeline(overrideTableId: configuration.timetable?.id)
    }
}

@available(iOS 17.0, *)
struct LockScreenCourseIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: LockScreenCourseWidget.widgetKind, intent: SelectTimetableIntent.self,
                               provider: LockScreenCourseIntentProvider()) { entry in
            LockScreenCourseEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
#endif

@available(iOS 16.0, *)
private struct LockScreenCourseEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        let prefs = AppPrefs.shared
        let useAlias = prefs.isWidgetUseAlias()
        let nowMin = Calendar.current.isDate(entry.date, inSameDayAs: entry.data.date) ? entry.nowMin : nil
        let rows = LockScreenCourseWidget.visibleCourses(data: entry.data, nowMin: nowMin, limit: 3)

        Group {
            switch family {
            case .accessoryCircular:
                circularView(rows: rows)
            case .accessoryInline:
                inlineView(rows: rows, useAlias: useAlias)
            default:
                rectangularView(rows: rows, useAlias: useAlias)
            }
        }
        .widgetURL(URL(string: "sleepy://open"))
        .sleepyWidgetBackground { Color.clear }
    }

    @ViewBuilder
    private func circularView(rows: [LockScreenCourseWidget.Row]) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if !entry.data.hasTable {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
            } else if entry.data.semesterStatus != .inRange || rows.isEmpty {
                VStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("0")
                        .font(.system(size: 10, weight: .medium))
                }
            } else {
                VStack(spacing: 1) {
                    Text("\(rows.count)")
                        .font(.system(size: 18, weight: .bold))
                        .widgetAccentable()
                    Text(rows[0].timeLabel.split(separator: "–").first.map(String.init) ?? "")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineView(rows: [LockScreenCourseWidget.Row], useAlias: Bool) -> some View {
        if !entry.data.hasTable {
            Text(L10n.format("widget_create_schedule"))
        } else if entry.data.semesterStatus == .beforeStart {
            Text(L10n.format("semester_not_started"))
        } else if entry.data.semesterStatus == .afterEnd {
            Text(L10n.format("semester_ended"))
        } else if let first = rows.first {
            let name = CourseDisplayUtil.displayName(first.course, useAlias)
            Text(first.timeLabel.isEmpty ? name : "\(first.timeLabel) \(name)")
        } else {
            Text(L10n.format("today_no_course"))
        }
    }

    @ViewBuilder
    private func rectangularView(rows: [LockScreenCourseWidget.Row], useAlias: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LockScreenCourseWidget.title(for: entry.data))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .widgetAccentable()
            if !entry.data.hasTable {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 12))
                    .lineLimit(2)
            } else if entry.data.semesterStatus != .inRange {
                Text(entry.data.semesterStatus == .beforeStart
                     ? L10n.format("semester_not_started")
                     : L10n.format("semester_ended"))
                    .font(.system(size: 12))
                    .lineLimit(1)
            } else if rows.isEmpty {
                Text(L10n.format("today_no_course"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(rows, id: \.course.id) { row in
                    HStack(spacing: 4) {
                        if !row.timeLabel.isEmpty {
                            Text(row.timeLabel.split(separator: "–").first.map(String.init) ?? row.timeLabel)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(CourseDisplayUtil.displayName(row.course, useAlias))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if !row.course.room.isEmpty {
                            Text(row.course.room)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
