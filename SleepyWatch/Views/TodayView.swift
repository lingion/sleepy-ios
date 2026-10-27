// TodayView.swift — 手表今日课表 (2026-10 watch 伴侣 App)
// ← TodayScreen 语义的手表重设计: 学期状态行 + 「进行中/下一节」角标 + 全天列表。
// 数据口径与 TodayWidgetLoader 同源 (调休 effectiveDayOfWeek + 当前周过滤 + 节次排序)。

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        Group {
            if let table = store.currentTable() {
                content(table, scheme: WatchPalette.scheme(envDark: envScheme == .dark))
            } else {
                emptyState(scheme: WatchPalette.scheme(envDark: envScheme == .dark))
            }
        }
        .navigationTitle(Text(L10n.t("today_today")))
    }

    @ViewBuilder
    private func content(_ table: TimeTableEntity, scheme: WidgetScheme) -> some View {
        let today = Date()
        let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: today)
        let courses = store.todayCourses(table: table)
        let marks = status == .inRange ? classState(courses: courses, table: table, now: today) : [:]
        List {
            statusRow(status, table: table, scheme: scheme)
            if courses.isEmpty {
                Text(status == .inRange ? L10n.t("schedule_no_course_today") : L10n.t("today_semester_out_hint"))
                    .font(.footnote).foregroundColor(scheme.onSurfaceVariant)
            } else {
                ForEach(Array(courses.enumerated()), id: \.offset) { idx, c in
                    NavigationLink {
                        CourseDetailView(course: c, table: table, groupRows: courses)
                    } label: {
                        CourseRowView(course: c, table: table, scheme: scheme, mark: marks[idx])
                    }
                }
            }
        }
    }

    /// 学期状态行 — 学期内「第 N 周」, 外显状态文案 (键与 iOS 同源)
    @ViewBuilder
    private func statusRow(_ status: DateUtils.SemesterStatus, table: TimeTableEntity, scheme: WidgetScheme) -> some View {
        switch status {
        case .inRange:
            let week = DateUtils.currentWeek(startDate: table.startDate, today: Date())
            Text(L10n.format("schedule_current_week", week))
                .font(.caption).foregroundColor(scheme.onSurfaceVariant)
        case .beforeStart:
            Text(L10n.t("semester_not_started")).font(.caption).foregroundColor(scheme.onSurfaceVariant)
        case .afterEnd:
            Text(L10n.t("semester_ended")).font(.caption).foregroundColor(scheme.onSurfaceVariant)
        }
    }

    private func emptyState(scheme: WidgetScheme) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundColor(scheme.onSurfaceVariant)
            Text(L10n.t("watch_no_table_hint"))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(scheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// 当前节状态标注 ← TodayScreen 的 now-line 语义降维:
    /// 手表不画实时线, 只给「进行中/下一节」两枚角标。ownTime 课直读时钟,
    /// 节次课查水合表 (与 store.timeRange 同口径)。
    private func classState(courses: [CourseEntity], table: TimeTableEntity, now: Date) -> [Int: CourseMark] {
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func clock(_ s: String) -> Date? {
            guard let p = SleepyNativeFormat.parseClock(s) else { return nil }
            return day.addingTimeInterval(TimeInterval(p.h * 3600 + p.min * 60))
        }
        /// 课程在「今天」的起止时刻; 非常规/缺节次 → nil 不参与标注
        func interval(_ c: CourseEntity) -> (Date, Date)? {
            if (c.ownTime || c.isIrregularTime), !c.startTime.isEmpty, !c.endTime.isEmpty,
               let st = clock(c.startTime), let en = clock(c.endTime) {
                return (st, en)
            }
            if c.isIrregularNode { return nil }
            guard let s = nodes.first(where: { $0.node == c.startNode }),
                  let e = nodes.first(where: { $0.node == c.startNode + c.step - 1 })
            else { return nil }
            // NodeTime 只有时刻有效 → 钉到今天
            let st = combine(cal, day, s.start)
            let en = combine(cal, day, e.end)
            return (st, en)
        }
        var marks: [Int: CourseMark] = [:]
        var nextIdx: Int? = nil
        for (idx, c) in courses.enumerated() {
            guard let (st, en) = interval(c) else { continue }
            if now >= st && now < en {
                marks[idx] = .current
            } else if now < st, nextIdx == nil {
                nextIdx = idx
            }
        }
        if let ni = nextIdx { marks[ni] = .next }
        return marks
    }

    /// 节次 Date 只有时刻有意义 → 钉到今天的日期
    private func combine(_ cal: Calendar, _ day: Date, _ time: Date) -> Date {
        let secs = cal.component(.hour, from: time) * 3600 + cal.component(.minute, from: time) * 60
        return day.addingTimeInterval(TimeInterval(secs))
    }
}

enum CourseMark { case current, next }
