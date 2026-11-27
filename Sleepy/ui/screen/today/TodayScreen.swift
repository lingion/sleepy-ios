// TodayScreen.swift — ← ui/screen/today/TodayScreen.kt
// 今天页: 头卡(日期+周次/门数 Stat) + 今日课程列表(时间槽 76dp + 课程名/教师·教室)。
// 空态: EmptyToday(时钟图标 + 两行文案)。

import SwiftUI

/// 补课日的周次/学期状态跟随取课源日期，日期标题仍显示实际今天。
/// ← TodayScreen.kt / CompactTodayPane: courseDateFor(today) ?: today。
struct TodayDisplayContext {
    let date: Date
    let actualWeek: Int
    let semesterStatus: DateUtils.SemesterStatus

    init(state: ScheduleState, today: Date, civilDate: Date? = nil) {
        date = today
        let civil = civilDate ?? today
        let courseDate = state.courseDateFor(civil) ?? civil
        if let table = state.currentTable,
           let first = CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1) {
            let week = CourseOccurrences.week(startDate: table.startDate, date: courseDate)
            actualWeek = week ?? 1
            if courseDate < first { semesterStatus = .beforeStart }
            else if actualWeek > table.maxWeek { semesterStatus = .afterEnd }
            else { semesterStatus = .inRange }
        } else {
            actualWeek = state.currentWeek
            semesterStatus = .inRange
        }
    }
}

struct TodayScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @Environment(\.localCoursePalette) private var palette
    @ObservedObject var viewModel: ScheduleViewModel
    /// ★ 平板双栏右半紧凑变体(TodayScreen.kt CompactTodayPane, PR#114):
    ///   无页面背景(surfaceContainerLow 卡片透出)、水平 16/垂直 12 内衬、
    ///   卡间距 12、无底部药丸余量(rail 模式 env 缺省 0, 此处直接不挂)。
    ///   手机版(默认 false)保持原样式逐字不变。
    var compact: Bool = false
    var onEditCourse: ((CourseEntity) -> Void)? = nil
    // ← selectedCourse: 点课卡 → 详情 BottomSheet(与课表页同一组件同一交互)
    @State private var selectedCourse: CourseEntity? = nil
    @State private var selectedCourseDate: Date? = nil
    @State private var contentWidth: CGFloat = 360
    @ScaledMetric(relativeTo: .body) private var todayTextSize: CGFloat = 16

    var body: some View {
        let state = viewModel.state
        let today = AppClock.now
        let civil = CourseReminderCalendar(timeZone: .current).civilDay(containing: today) ?? today
        let dateContext = TodayDisplayContext(state: state, today: today, civilDate: civil)
        let effectiveTimeJson = state.effectiveRenderTimeJson(on: civil)
        // ★ 学期外感知: BEFORE_START/AFTER_END 时今日课不按周过滤展示
        let semesterStatus = dateContext.semesterStatus
        let todayCourses: [CourseEntity] = {
            let list = state.currentTable.map { table in
                HolidayTransferOps.coursesForDate(civil, startDate: table.startDate, maxWeek: table.maxWeek,
                    courses: state.courses, transfers: state.transfers)
            } ?? []
            // 用户报障 2026-09-10: ownTime 课渲染前按真实时间归一化节点(与网格同一
            // 预处理), 落库的表单占位节点不再影响今日页分组与显示。
            guard let tj = effectiveTimeJson else {
                return list.sorted { $0.startNode < $1.startNode }
            }
            return list.map { $0.normalizeNode(timeJson: tj) }.sorted { $0.startNode < $1.startNode }
        }()
        // v7.10.10 今日页冲突分栏 — 与周视图同一引擎同一分组(weekLaneRows):
        // 冲突区域一行内并排分栏(栏间浅细竖线), 无冲突课整宽单行。
        // 用户报障 2026-09-10: 分组走时间域(带 timeJson), 时间零交集的 ownTime 课对
        // 不再因节点占位值相同被并成假冲突行。
        let laneRows = ConflictLayoutEngine.weekLaneRows(
            todayCourses, timeJson: effectiveTimeJson)
        let groupRowsById = Dictionary(grouping: todayCourses, by: \.groupId)

        ScrollView {
            VStack(spacing: compact ? 12 : 16) {
                TodayHeader(date: dateContext.date, week: dateContext.actualWeek, count: todayCourses.count,
                            semesterStatus: semesterStatus)

                if state.hasPeriodConflict {
                    PeriodConflictBanner(message: L10n.format("period_conflict_detected_banner", state.periodValidation.errorMessage))
                }

                if todayCourses.isEmpty {
                    EmptyToday(semesterStatus: semesterStatus)
                } else {
                    SectionHead(title: L10n.format("widget_today_label"),
                                action: L10n.format("n_periods", todayCourses.count))
                    // v7.10.10 冲突分栏: 单栏整宽; 多栏并排+栏间浅细竖线(与周视图同款)
                    ForEach(laneRows, id: \.courses.first!.id) { row in
                        if row.laneCount == 1 {
                            ForEach(row.courses) { course in
                                TodayCourseCard(course: course, timeJson: effectiveTimeJson,
                                                groupRows: groupRowsById[course.groupId] ?? [course],
                                                availableWidth: contentWidth,
                                                textSize: todayTextSize) {
                                    selectedCourseDate = civil
                                    selectedCourse = course
                                }
                            }
                        } else {
                            TodayLaneRow(row: row, timeJson: effectiveTimeJson,
                                         groupRowsById: groupRowsById,
                                         availableWidth: contentWidth,
                                         textSize: todayTextSize) { c in
                                selectedCourseDate = civil
                                selectedCourse = c
                            }
                        }
                    }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TodayContentWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(TodayContentWidthKey.self) { width in
                if width > 0 { contentWidth = width }
            }
            .padding(compact ? EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                             : EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            // 悬浮底栏额外余量(→ 原版本 LocalNavExtraBottomPadding): 镜像原实现
            //   padding(bottom = 16.dp + navExtra) 让最后一张课卡不被悬浮药丸遮住。
            //   compact(平板双栏右半)不挂 —— ← CompactTodayPane 无 navExtra padding。
            .padding(.bottom, compact ? 0 : navExtra)
        }
        // compact: 无背景(CompactTodayPane Column 无 background,
        // surfaceContainerLow 卡片透出); 手机版原样 colors.background。
        .background(compact ? Color.clear : colors.background)
        // 详情 Bottom Sheet — 与课表页同一组件同一交互(← TodayScreen.kt CourseDetailSheet)
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(
                course: course,
                timeString: course.nodeString(),
                // 对齐 原版本 (TodayScreen.kt:169/274 `allCourses = todayCourses`):
                // sheet 聚簇必须与今日列表同一份数据 — 已按 day+周过滤且 normalizeNode
                // 后的今日子集。此前传整周未归一化行, ownTime 课带表单占位节点进 sheet
                // 聚簇 = 2026-09-10 同类报障在 iOS sheet 路径的残留。
                allCourses: todayCourses,
                onEdit: { c in
                    selectedCourse = nil
                    onEditCourse?(state.courses.first { $0.id == c.id } ?? c)
                },
                timeJson: state.effectiveRenderTimeJson(on: selectedCourseDate ?? civil),
                displayDate: selectedCourseDate,
                occurrenceTable: state.effectiveCurrentTable,
                occurrenceRepository: viewModel.occurrenceRepository,
                onOccurrenceSaved: {
                    selectedCourse = nil
                    viewModel.occurrenceSaved()
                })
        }
    }
}

struct PeriodConflictBanner: View {
    @Environment(\.localWakeUpColors) private var colors
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AndroidSettingsIcon(name: .notifications, size: 20)
                .accessibilityHidden(true)
            Text(message).font(SleepyTypography.bodySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(colors.onErrorContainer)
        .padding(12)
        .background(colors.errorContainer.opacity(0.4))
        .cornerRadius(SleepyShapes.medium)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("period_conflict_banner")
    }
}

// v7.10.10 冲突分栏行 — 按 lane 并排(每栏均分), 同栏课程纵向堆叠;
// 栏间浅细竖线: 0.5dp 宽, onSurface hairline 透明度, 高度随行(与周视图分栏同款)
private struct TodayContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

enum TodayAgendaLayout {
    static let laneGap: CGFloat = 6
    static let dividerWidth: CGFloat = 0.5

    static func laneWidth(available: CGFloat, count: Int, textSize: CGFloat = 16) -> CGFloat? {
        guard count > 1 else { return nil }
        let totalGap = CGFloat(count - 1) * (laneGap * 2 + dividerWidth)
        let width = (available - totalGap) / CGFloat(count)
        return width >= max(150, 9.5 * textSize) ? width : nil
    }

    static func showsSideSlot(width: CGFloat, textSize: CGFloat = 16) -> Bool {
        width >= max(220, 13.75 * textSize)
    }
}

private struct TodayLaneRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let row: ConflictLayoutEngine.WeekLaneRow
    var timeJson: String? = nil
    var groupRowsById: [String: [CourseEntity]] = [:]
    var availableWidth: CGFloat = 360
    var textSize: CGFloat = 16
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        if let laneW = TodayAgendaLayout.laneWidth(available: availableWidth, count: row.laneCount, textSize: textSize) {
            let coursesByLane = Dictionary(grouping: row.courses, by: { row.laneOf[$0.id] ?? -1 })
            HStack(alignment: .top, spacing: TodayAgendaLayout.laneGap) {
                ForEach(0..<row.laneCount, id: \.self) { li in
                    if li > 0 {
                        Rectangle()
                            .fill(colors.onSurface.opacity(SleepyTheme.Alpha.hairline))
                            .frame(width: TodayAgendaLayout.dividerWidth)
                    }
                    let laneCourses = coursesByLane[li] ?? []
                    VStack(spacing: 6) {
                        ForEach(laneCourses) { laneCourse in
                            TodayCourseCard(course: laneCourse, timeJson: timeJson,
                                            groupRows: groupRowsById[laneCourse.groupId] ?? [laneCourse],
                                            availableWidth: laneW,
                                            textSize: textSize) {
                                onCourseClick(laneCourse)
                            }
                        }
                    }
                    .frame(width: laneW, alignment: .leading)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(row.courses) { laneCourse in
                    TodayCourseCard(course: laneCourse, timeJson: timeJson,
                                    groupRows: groupRowsById[laneCourse.groupId] ?? [laneCourse],
                                    availableWidth: availableWidth,
                                    textSize: textSize) {
                        onCourseClick(laneCourse)
                    }
                }
            }
        }
    }
}

// ← TodayHeader
private struct TodayHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let date: Date
    let week: Int
    let count: Int
    var semesterStatus: DateUtils.SemesterStatus = .inRange

    var body: some View {
        let comps = DateUtils.isoCalendar.dateComponents([.month, .day, .weekday], from: date)
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("today_today"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 6)
            HStack(alignment: .bottom, spacing: 8) {
                Text(L10n.format("date_long_format", comps.month ?? 1, comps.day ?? 1))
                    .font(.system(size: 28))
                    .foregroundColor(colors.onSurface)
                // ISO weekday (周一=1)
                Text(DateUtils.localizedDay(((comps.weekday ?? 2) + 5) % 7 + 1))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 4)
            }
            Spacer().frame(height: 8)
            HStack(spacing: 12) {
                // ★ 学期外: 周次 chip 换学期状态, 不再显示误导性的"第 1 周"
                switch semesterStatus {
                case .beforeStart:
                    Stat(label: L10n.format("semester_not_started"),
                         bg: colors.secondaryContainer, fg: colors.onSecondaryContainer)
                case .afterEnd:
                    Stat(label: L10n.format("semester_ended"),
                         bg: colors.secondaryContainer, fg: colors.onSecondaryContainer)
                case .inRange:
                    Stat(label: L10n.format("schedule_current_week", week),
                         bg: colors.primaryContainer, fg: colors.onPrimaryContainer)
                }
                Stat(label: count == 0 ? L10n.format("no_course")
                                       : L10n.format("n_course_periods", count),
                     bg: colors.tertiaryContainer, fg: colors.onTertiaryContainer)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← Stat
private struct Stat: View {
    let label: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bg)
            .cornerRadius(SleepyShapes.medium)
    }
}

// ← EmptyToday
private struct EmptyToday: View {
    @Environment(\.localWakeUpColors) private var colors
    var semesterStatus: DateUtils.SemesterStatus = .inRange

    var body: some View {
        VStack(spacing: 12) {
            AndroidSettingsIcon(name: .schedule, size: 48)
                .foregroundColor(colors.onSurfaceVariant)
            // ★ 学期外: 主副文案换学期状态(不是"今天没课")
            if semesterStatus != .inRange {
                Text(semesterStatus == .beforeStart
                     ? L10n.format("semester_not_started")
                     : L10n.format("semester_ended"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("today_semester_out_hint"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
            } else {
                Text(L10n.format("schedule_no_course_today"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("today_no_course"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← TodayCourseCard
private struct TodayCourseCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let course: CourseEntity
    var timeJson: String? = nil
    /// issue#22: 同 groupId 全行(含自身) — AUTO/CUSTOM 取色按行判; 空则回退 [course](= 原 `listOf(course)` 默认值)
    var groupRows: [CourseEntity] = []
    var availableWidth: CGFloat = 360
    var textSize: CGFloat = 16
    var onClick: (() -> Void)? = nil

    // 统一取色入口 — hue 源自动对齐 groupId; issue#22 改走 *WithGroupRows 三态入口
    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: groupRows.isEmpty ? [course] : groupRows,
            isDark: isDark, neutralColor: colors.secondaryContainer,
            colorless: AppPrefs.shared.isCourseColorless(),
            persistedHue: CourseHueStore.hueFor(groupId: course.groupId))
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        let time: String? = {
            guard let parts = TimeTableUtils.effectiveCourseTime(
                isIrregularTime: course.ownTime || course.isIrregularTime,
                startTime: course.startTime, endTime: course.endTime,
                startNode: course.startNode, step: course.step, timeJson: timeJson ?? ""),
                  let start = TimeTableUtils.hmToSeconds(parts.0),
                  let end = TimeTableUtils.hmToSeconds(parts.1), end > start else { return nil }
            return "\(parts.0)-\(parts.1)"
        }()
        let showsSide = TodayAgendaLayout.showsSideSlot(width: availableWidth, textSize: textSize)
        let meta: String = {
            var s = ""
            if !course.teacher.isEmpty { s += course.teacher }
            if !course.room.isEmpty {
                if !s.isEmpty { s += " · " }
                s += course.room
            }
            return s
        }()

        Button {
            onClick?()
        } label: {
            Group {
                if showsSide {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.nodeString(isShort: true))
                                .font(.system(size: textSize, weight: .bold))
                                .foregroundColor(fg)
                            if let time = time {
                                Text(time)
                                    .font(.system(size: max(11, textSize * 11 / 16), weight: .medium).monospacedDigit())
                                    .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                        }
                        .frame(minWidth: 76, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.courseName)
                                .font(.system(size: textSize, weight: .semibold))
                                .foregroundColor(fg)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            if !meta.isEmpty {
                                Text(meta)
                                    .font(.system(size: max(12, textSize * 12 / 16)))
                                    .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(course.nodeString(isShort: true))
                                .font(.system(size: max(13, textSize * 14 / 16), weight: .bold))
                                .foregroundColor(fg)
                            if let time = time {
                                Text(time)
                                    .font(.system(size: max(11, textSize * 11 / 16), weight: .medium).monospacedDigit())
                                    .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                            }
                            Spacer(minLength: 0)
                        }
                        Text(course.courseName)
                            .font(.system(size: textSize, weight: .semibold))
                            .foregroundColor(fg)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: max(12, textSize * 12 / 16)))
                                .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(12)
        }
        .buttonStyle(SleepyButtonStyle())
        .background(bg)
        .cornerRadius(SleepyShapes.large)
        .accessibilityIdentifier("today_course_\(course.id)")
        .accessibilityLabel(course.courseName)
    }
}
