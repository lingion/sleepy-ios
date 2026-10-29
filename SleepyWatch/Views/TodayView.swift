// TodayView.swift — 手表今日课表 (2026-10 watch 伴侣 App)
// ← TodayScreen 语义的手表重设计: 头卡 (日期 + 周次/节数两枚 Stat) +
// 「进行中/下一节」角标 + 冲突分栏行 (ConflictLayoutEngine.weekLaneRows 同源)。
// 数据口径与 TodayWidgetLoader 同源 (调休 effectiveDayOfWeek + 当前周过滤 + 节次排序);
// ownTime 课渲染前 normalizeNode (← TodayScreen 用户报障 2026-09-10 同口径)。
//
// 手表独创交互 (数据源仍来自手机镜像, 仅交互方式利用手表硬件):
// · Digital Crown 滚动: .focusable() + .digitalCrownRotation 绑定 List offset,
//   转表冠滚课程列表 — 比手指滑小屏精确 (watchOS 最自然的滚动输入)。
// · 触觉反馈: .sensoryFeedback(.success, trigger:) 在「进行中」课程变化时触发,
//   不用看屏幕就知道该上课了 (Taptic Engine 是手表独有输出通道)。
// · 全屏倒计时入口: 头卡日期行 → NavigationLink 到 CountdownView (大字沉浸式)。

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    /// Digital Crown 滚动偏移 (归一化值, 映射到 List scroll position)
    @State private var crownOffset: Double = 0
    /// 触觉反馈触发器: 当前进行中课程的 id, 变化时触发 .success haptic
    @State private var hapticTrigger: Int64 = 0

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
        // ownTime 课按时间域归一化节点 (← TodayScreen: 落库占位节点不得影响分组/排序)
        let courses = store.todayCourses(table: table)
            .map { $0.normalizeNode(timeJson: table.timeJson) }
            .sorted { $0.startNode < $1.startNode }
        let marks = status == .inRange ? classState(courses: courses, table: table, now: today) : [:]
        // 触觉反馈: 当前进行中课程 id 作为 trigger (变化 → haptic)
        let currentId: Int64 = {
            guard let entry = marks.first(where: { $0.value == .current }),
                  entry.key < courses.count else { return 0 }
            return courses[entry.key].id
        }()

        // 冲突分栏 — 与 iOS 今日页/周视图同一引擎同一分组; 手表窄屏多栏并排
        let laneRows = ConflictLayoutEngine.weekLaneRows(courses, timeJson: table.timeJson)
        List {
            headerRow(status: status, table: table, count: courses.count, scheme: scheme)
            if courses.isEmpty {
                Text(status == .inRange ? L10n.t("schedule_no_course_today") : L10n.t("today_semester_out_hint"))
                    .font(.footnote).foregroundColor(scheme.onSurfaceVariant)
            } else {
                ForEach(Array(laneRows.enumerated()), id: \.offset) { _, row in
                    if row.laneCount == 1, let only = row.courses.first {
                        courseLink(only, courses: courses, table: table, scheme: scheme,
                                   mark: markOf(only, in: courses, marks: marks))
                    } else {
                        // 多栏行: 横向均分, 栏间 0.5pt hairline 竖线 (← TodayLaneRow 同款)
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(0..<row.laneCount, id: \.self) { li in
                                if li > 0 {
                                    Rectangle()
                                        .fill(scheme.onSurface.opacity(SleepyTheme.Alpha.hairline))
                                        .frame(width: 0.5)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(row.courses.filter { row.laneOf[$0.id] == li }) { c in
                                        courseLink(c, courses: courses, table: table, scheme: scheme,
                                                   mark: markOf(c, in: courses, marks: marks))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        // ★ Digital Crown 滚动 — 转表冠滚课程列表 (watchOS 最自然的滚动输入)
        .focusable()
        .digitalCrownRotation($crownOffset, from: 0, through: Double(max(courses.count, 1)),
                              by: 0.5, sensitivity: .medium, isContinuous: false)
        // ★ 触觉反馈 — 进行中课程变化时触发 success haptic
        .sensoryFeedback(.success, trigger: hapticTrigger)
        .onChange(of: currentId) { newId in
            hapticTrigger = newId
        }
    }

    /// 单课链接 — groupRows 传同 groupId 行集 (issue#22 取色按组判定, 全量传会歪)
    private func courseLink(_ course: CourseEntity, courses: [CourseEntity],
                            table: TimeTableEntity, scheme: WidgetScheme,
                            mark: CourseMark?) -> some View {
        NavigationLink {
            CourseDetailView(course: course, table: table,
                             groupRows: courses.filter { $0.groupId == course.groupId })
        } label: {
            CourseRowView(course: course, table: table, scheme: scheme, mark: mark,
                          groupRows: courses.filter { $0.groupId == course.groupId })
        }
    }

    private func markOf(_ course: CourseEntity, in courses: [CourseEntity],
                        marks: [Int: CourseMark]) -> CourseMark? {
        courses.firstIndex(where: { $0.id == course.id }).flatMap { marks[$0] }
    }

    /// 头卡 — ← TodayHeader 降维: 日期行 (可点进全屏倒计时) + 「第 N 周 / N 节」两枚 Stat
    @ViewBuilder
    private func headerRow(status: DateUtils.SemesterStatus, table: TimeTableEntity,
                           count: Int, scheme: WidgetScheme) -> some View {
        let comps = DateUtils.isoCalendar.dateComponents([.month, .day, .weekday], from: Date())
        VStack(alignment: .leading, spacing: 3) {
            // ★ 日期行 = 全屏倒计时入口 (双击/单击进入沉浸式大字倒计时)
            NavigationLink {
                CountdownView(table: table)
            } label: {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(L10n.format("date_long_format", comps.month ?? 1, comps.day ?? 1))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(scheme.onSurface)
                    Text(DateUtils.localizedDay(((comps.weekday ?? 2) + 5) % 7 + 1))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(scheme.onSurfaceVariant)
                    Spacer(minLength: 0)
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundColor(scheme.primary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                stat(weekOrStatusText(status, table: table),
                     bg: scheme.primaryContainer, fg: scheme.onPrimaryContainer, scheme: scheme)
                // 节数 chip = 课程清单 push 入口 (手表今日页唯一入口位; 语义
                // ← iOS「我的页课程数卡 → CourseListScreen」同路径降维)。
                // 键 = n_course_periods ← TodayHeader:190 实况 (非 n_periods)。
                NavigationLink { CourseListView(table: table) } label: {
                    stat(count == 0 ? L10n.t("no_course") : L10n.format("n_course_periods", count),
                         bg: scheme.surfaceVariant, fg: scheme.onSurfaceVariant, scheme: scheme)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekOrStatusText(_ status: DateUtils.SemesterStatus, table: TimeTableEntity) -> String {
        switch status {
        case .inRange:
            return L10n.format("schedule_current_week",
                               DateUtils.currentWeek(startDate: table.startDate, today: Date()))
        case .beforeStart: return L10n.t("semester_not_started")
        case .afterEnd: return L10n.t("semester_ended")
        }
    }

    private func stat(_ label: String, bg: Color, fg: Color, scheme: WidgetScheme) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
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
