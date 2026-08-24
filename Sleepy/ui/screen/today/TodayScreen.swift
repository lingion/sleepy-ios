// TodayScreen.swift — ← ui/screen/today/TodayScreen.kt
// 今天页: 头卡(日期+周次/门数 Stat) + 今日课程列表(时间槽 76dp + 课程名/教师·教室)。
// 空态: EmptyToday(时钟图标 + 两行文案)。

import SwiftUI

struct TodayScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @ObservedObject var viewModel: ScheduleViewModel

    var body: some View {
        let state = viewModel.state
        let today = Date()
        let dayOfWeek = DateUtils.todayDayOfWeek(today: today)
        let actualWeek = state.currentTable.map {
            DateUtils.currentWeek(startDate: $0.startDate, today: today)
        } ?? state.currentWeek
        let todayCourses = state.courses
            .filter { $0.day == dayOfWeek && $0.inWeek(actualWeek) }
            .sorted { $0.startNode < $1.startNode }

        ScrollView {
            VStack(spacing: 16) {
                TodayHeader(date: today, week: actualWeek, count: todayCourses.count)

                if todayCourses.isEmpty {
                    EmptyToday()
                } else {
                    SectionHead(title: L10n.format("widget_today_label"),
                                action: L10n.format("n_periods", todayCourses.count))
                    ForEach(todayCourses) { course in
                        TodayCourseCard(course: course, timeJson: state.currentTable?.timeJson)
                    }
                }
            }
            .padding(16)
        }
        .background(colors.background)
    }
}

// ← TodayHeader
private struct TodayHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let date: Date
    let week: Int
    let count: Int

    var body: some View {
        let comps = DateUtils.isoCalendar.dateComponents([.month, .day, .weekday], from: date)
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("today_today"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 6)
            HStack(alignment: .bottom, spacing: 8) {
                Text(L10n.format("date_long_format", comps.month ?? 1, comps.day ?? 1))
                    .font(.system(size: 22))
                    .foregroundColor(colors.onSurface)
                // ISO weekday (周一=1)
                Text(DateUtils.localizedDay(((comps.weekday ?? 2) + 5) % 7 + 1))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 4)
            }
            Spacer().frame(height: 8)
            HStack(spacing: 12) {
                Stat(label: L10n.format("schedule_current_week", week),
                     bg: colors.primaryContainer, fg: colors.onPrimaryContainer)
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundColor(colors.onSurfaceVariant)
            Text(L10n.format("schedule_no_course_today"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("today_no_course"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
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

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        // 统一取色入口 — hue 源自动对齐 groupId
        let bg = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: isDark, neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        let time: String? = {
            if course.ownTime, !course.startTime.isEmpty, !course.endTime.isEmpty {
                return "\(course.startTime)-\(course.endTime)"
            }
            guard let tj = timeJson else { return nil }
            return TimeTableUtils.courseTimeString(courseStartNode: course.startNode,
                                                   courseStep: course.step, timeJson: tj)
        }()

        HStack(alignment: .top, spacing: 12) {
            // 时间槽 — 固定宽度避免 "10:20-12:45" 被截断
            VStack(alignment: .leading, spacing: 0) {
                Text(course.nodeString(isShort: true))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(fg)
                    .lineLimit(1)
                if let time = time {
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(course.courseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(fg)
                    .lineLimit(2)
                let meta: String = {
                    var s = ""
                    if !course.teacher.isEmpty { s += course.teacher }
                    if !course.room.isEmpty {
                        if !s.isEmpty { s += " · " }
                        s += course.room
                    }
                    return s
                }()
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(bg)
        .cornerRadius(SleepyShapes.large)
    }
}
